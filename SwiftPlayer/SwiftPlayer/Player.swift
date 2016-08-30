//
//  Player.swift
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 29..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

import Foundation
import ffmpeg
import SDL
import AVFoundation
import UIKit

struct AudioState {
    var audioContex: UnsafeMutablePointer<AVCodecContext>?
    
    var abuffer_ctx: UnsafeMutablePointer<AVFilterContext>?
    var abuffer_sink_ctx: UnsafeMutablePointer<AVFilterContext>?
    
    var audio_queue: UnsafeMutablePointer<AVQueue<AVFrame>>?
    
    var audio_filtered_frame: UnsafeMutablePointer<AVFrame>?
}

public class Player: Operation {
    
    public let capture_queue = DispatchQueue(label: "capture", qos: DispatchQoS.userInteractive, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit)
    public let decode_queue = DispatchQueue(label: "decode", qos: .background, attributes: .concurrent, autoreleaseFrequency: .inherit)
    
    public init(path: String) {
        super.init()
        
        self.path = path
        
        displayLink = CADisplayLink(target: self, selector: #selector(update(link:)))
        displayLink?.isPaused = true
    }
    
    deinit {
        avformat_network_deinit()
        if 0 < avcodec_is_open(videoContext) {
            avcodec_close(videoContext)
        }
        avcodec_free_context(&videoContext)
        
        if 0 < avcodec_is_open(audioContext) {
            avcodec_close(audioContext)
        }
        avcodec_free_context(&audioContext)
        
        avformat_close_input(&formatContext)
    }
    
    public override func main() {
        
        guard setupFFmpeg() else {
            print("find streams failed")
            return
        }
        
        guard setupSDL() else {
            print("SDL setup failed")
            return
        }
        
        let dstRect = AVMakeRect(aspectRatio: CGSize(width: Int(video_rect.w), height: Int(video_rect.h)), insideRect: CGRect(origin: CGPoint(), size: self.screenSize))
        
        self.dst_rect = SDL_Rect(x: Int32(dstRect.origin.x), y: Int32(dstRect.origin.y), w: Int32(dstRect.width), h: Int32(dstRect.height))
        
        self.startEventPulling()
        self.decodeFrames()
        
        self.startDisplayLink()
        
        SDL_PauseAudio(0)
    }
    
    func startDisplayLink() {
        displayLink?.isPaused = false
        displayLink?.add(to: RunLoop.current, forMode: .commonModes)
    }
    
    func stopDisplayLink() {
        displayLink?.isPaused = true
        displayLink?.invalidate()
    }
    
    var event = SDL_Event()
    func startEventPulling() {
        capture_queue.async {
            event_loop: while true {
                SDL_PollEvent(&self.event)
                
                switch self.event.type {
                case SDL_FINGERDOWN.rawValue, SDL_QUIT.rawValue:
                    self.capture_queue.async(execute: {
                        DispatchQueue.main.async(execute: {
                            self.displayLink?.isPaused = true
                            self.displayLink?.invalidate()
                            SDL_Quit()
                            exit(1)
                        })
                    })
                    break event_loop
                default:
                    break
                }
            }
        }
    }
    
    //MARK: - display link
    var displayLink: CADisplayLink?
    var first: CFTimeInterval = 0
    func update(link: CADisplayLink) {
        if 0 == first {
            first = link.timestamp
        }
        
        Player.videoQueue.read(time: link.timestamp - first) { (frame) in
            SDL_UpdateYUVTexture(texture, &video_rect, frame.pointee.data.0, frame.pointee.linesize.0, frame.pointee.data.1, frame.pointee.linesize.1, frame.pointee.data.2, frame.pointee.linesize.2)
            SDL_RenderClear(renderer)
            var dst = dst_rect!
            SDL_RenderCopy(renderer, texture, &video_rect, &dst)
            SDL_RenderPresent(renderer)
        }
    }
    
    var audio_callback: SDL_AudioCallback = {(userdata, stream, length) in
        guard let state = userdata?.assumingMemoryBound(to: AudioState.self) else {
            return
        }
        SDL_memset(stream, 0, Int(length))
        state.pointee.audio_queue?.pointee.read() { (frame) in
            var err = av_buffersrc_write_frame(state.pointee.abuffer_ctx, frame)
            guard 0 <= err else {
                print_averr(err: err)
                return
            }
            
            var length = length
            var stream = stream
            while true {
                err = av_buffersink_get_frame(state.pointee.abuffer_sink_ctx, state.pointee.audio_filtered_frame)
                guard 0 == is_eof(err) && err != err2averr(EAGAIN) else {
                    break
                }
                guard 0 <= err else {
                    print_averr(err: err)
                    return
                }
                guard let audio_frame = state.pointee.audio_filtered_frame else {
                    return
                }
                SDL_memcpy(stream, audio_frame.pointee.data.0, Int(audio_frame.pointee.linesize.0))
                stream = stream?.advanced(by: Int(audio_frame.pointee.linesize.0))
                length -= audio_frame.pointee.linesize.0
                if 0 >= length {
                    break
                }
            }
            
        }
        
    }
    
    static var videoQueue: AVQueue<AVFrame>!
    var audioQueue: AVQueue<AVFrame>!
    
    let pkt = av_packet_alloc()
    let frame = av_frame_alloc()
    let audio_filtered_frame = av_frame_alloc()!
    
    var got_frame: Int32 = 0
    var length: Int32 = 0
    
    func decodeFrames() {
        decode_queue.async {
            defer {
                print("👏🏽 decode finished")
            }
            decode: while true {
                if Player.videoQueue.fulled || self.audioQueue.fulled {
                    continue
                }
                guard 0 <= av_read_frame(self.formatContext, self.pkt) else {
                    break decode
                }
                
                if let pkt = self.pkt, let frame = self.frame {
                    if pkt.pointee.stream_index == self.video_index, let videoContext = self.videoContext {
                        let ret = self.decode(ctx: videoContext, packet: pkt, frame: frame, got_frame: &self.got_frame, length: &self.length)
                        guard 0 <= ret else {
                            print_err(ret)
                            continue
                        }
                        
                        Player.videoQueue.write(container: frame){
                            av_frame_unref(frame)
                        }
                    } else if pkt.pointee.stream_index == self.audio_index, let audioContext = self.audioContext {
                        let ret = self.decode(ctx: audioContext, packet: pkt, frame: frame, got_frame: &self.got_frame, length: &self.length)
                        guard 0 <= ret else {
                            print_err(ret)
                            continue
                        }
                        
                        self.audioQueue.write(container: frame){
                            av_frame_unref(frame)
                        }
                    }
                }
            }
        }
    }
    
    //MARK: - decode
    /// decode
    private func decode(ctx: UnsafeMutablePointer<AVCodecContext>, packet: UnsafeMutablePointer<AVPacket>, frame: UnsafeMutablePointer<AVFrame>, got_frame: inout Int32, length: inout Int32) -> Int32 {
        var ret: Int32 = 0
        got_frame = 0
        length = 0
        switch ctx.pointee.codec_type {
        case AVMEDIA_TYPE_AUDIO, AVMEDIA_TYPE_VIDEO:
            ret = avcodec_send_packet(ctx, packet)
            if 0 > ret {
                print_err(ret)
                return 1 == is_eof(ret) ? 0 : ret
            }
            
            ret = avcodec_receive_frame(ctx, frame)
            
            if 0 > ret && ret != err2averr(ret) && 1 != is_eof(ret) {
                return ret
            }
            
            got_frame = 1
            length = frame.pointee.pkt_size
            
        default:
            break
        }
        
        return ret
    }
    
    //MARK: - FFmpeg, SDL
    public let screenSize: CGSize = UIScreen.main.bounds.size
    
    public var path: String!
    
    public var formatContext: UnsafeMutablePointer<AVFormatContext>?
    
    public var video_index: Int32 = -1
    public var videoStream: UnsafeMutablePointer<AVStream>?
    public var videoCodec: UnsafeMutablePointer<AVCodec>?
    public var videoContext: UnsafeMutablePointer<AVCodecContext>?
    
    private(set) lazy var video_rect: SDL_Rect = {return SDL_Rect(x: 0, y: 0, w: self.videoContext?.pointee.width ?? 0, h: self.videoContext?.pointee.height ?? 0)}()
    private(set) var dst_rect: SDL_Rect!
    
    public var audio_index: Int32 = -1
    public var audioStream: UnsafeMutablePointer<AVStream>?
    public var audioCodec: UnsafeMutablePointer<AVCodec>?
    public var audioContext: UnsafeMutablePointer<AVCodecContext>?
    
    var audio_filter_graph: UnsafeMutablePointer<AVFilterGraph>!
    var abuffer: UnsafeMutablePointer<AVFilter>!
    var abuffer_sink: UnsafeMutablePointer<AVFilter>!
    var aformat: UnsafeMutablePointer<AVFilter>!
    var abuffer_ctx: UnsafeMutablePointer<AVFilterContext>?
    var aformat_ctx: UnsafeMutablePointer<AVFilterContext>?
    var abuffer_sink_ctx: UnsafeMutablePointer<AVFilterContext>?
    
    var audioState: AudioState?
    
    //MARK: - setupFFmpeg
    private func setupFFmpeg() -> Bool {
        
        av_register_all()
        avfilter_register_all()
        avformat_network_init()
        
        let c_path = path.cString(using: .utf8)!.withUnsafeBufferPointer(){$0}.baseAddress!
        var ret = avformat_open_input(&formatContext, c_path, nil, nil)
        
        if 0 > ret {
            print("Couldn't create format for \(String(cString: c_path))")
            return false
        }
        
        ret = avformat_find_stream_info(formatContext, nil)
        
        if 0 > ret {
            print("Couldn't find stream information")
            return false
        }
        
        video_index = av_find_best_stream(formatContext, AVMEDIA_TYPE_VIDEO, -1, -1, &videoCodec, 0)
        videoStream = formatContext?.pointee.streams.advanced(by: Int(video_index)).pointee
        videoContext = avcodec_alloc_context3(videoCodec)
        avcodec_parameters_to_context(videoContext, videoStream?.pointee.codecpar)
        guard 0 <= avcodec_open2(videoContext, videoCodec, nil) else {
            print("Couldn't open codec for \(String(cString: avcodec_get_name(videoContext?.pointee.codec_id ?? AV_CODEC_ID_NONE)))")
            return false
        }
        Player.videoQueue = AVQueue<AVFrame>(time_base: videoStream?.pointee.time_base ?? AVRational())
        
        audio_index = av_find_best_stream(formatContext, AVMEDIA_TYPE_AUDIO, -1, -1, &audioCodec, 0)
        audioStream = formatContext?.pointee.streams.advanced(by: Int(audio_index)).pointee
        audioContext = avcodec_alloc_context3(audioCodec)
        avcodec_parameters_to_context(audioContext, audioStream?.pointee.codecpar)
        
        guard 0 <= avcodec_open2(audioContext, audioCodec, nil) else {
            print("Couldn't open codec for \(String(cString: avcodec_get_name(audioContext?.pointee.codec_id ?? AV_CODEC_ID_NONE)))")
            return false
        }
        
        self.audioQueue = AVQueue<AVFrame>(time_base: audioStream!.pointee.time_base)
        
        guard let audio_filter_graph = avfilter_graph_alloc() else {
            print("Couldn't create audio filter")
            return false
        }
        
        guard let audio_buffer = avfilter_get_by_name("abuffer") else {
            print("Couldn't get audio buffer")
            return false
        }
        
        guard let audio_buffer_sink = avfilter_get_by_name("abuffersink") else {
            print("Couldn't get audio buffer sink")
            return false
        }
        
        guard let audio_format = avfilter_get_by_name("aformat") else {
            print("Couldn't get audio format")
            return false
        }
        
        self.audio_filter_graph = audio_filter_graph
        self.abuffer = audio_buffer
        self.abuffer_sink = audio_buffer_sink
        self.aformat = audio_format
        
        let audio_time_base = audioStream!.pointee.time_base
        let layout_s = String.init(audioContext!.pointee.channel_layout, radix: 16, uppercase: false)
        let abuffer_str: String = "time_base=\(audio_time_base.num)/\(audio_time_base.den):sample_rate=\(audioContext!.pointee.sample_rate):sample_fmt=\(String(cString: av_get_sample_fmt_name(audioContext!.pointee.sample_fmt))):channel_layout=0x\(layout_s)"
        var err = avfilter_graph_create_filter(&abuffer_ctx, abuffer, "audio_input", abuffer_str, nil, audio_filter_graph)
        guard 0 <= err else {
            print_averr(desc: "avfilter_graph_create_filter for audio input with \(abuffer_str)", err: err)
            return false
        }
        
        // output filter
        
        let output_ch_layout: String = String((AV_CH_FRONT_LEFT | AV_CH_FRONT_RIGHT), radix: 16, uppercase: false)
        let aformat_str = "sample_fmts=\(String(cString: av_get_sample_fmt_name(AV_SAMPLE_FMT_S16))):sample_rates=44100:channel_layouts=\(output_ch_layout)"
        err = avfilter_graph_create_filter(&aformat_ctx, aformat, "format_converter", aformat_str, nil, audio_filter_graph)
        guard 0 <= err else {
            print_averr(desc: "avfilter_graph_create_filter for format convert \(aformat_str)", err: err)
            return false
        }
        
        err = avfilter_graph_create_filter(&abuffer_sink_ctx, abuffer_sink, "buffer_sink", nil, nil, audio_filter_graph)
        guard 0 <= err else {
            print_averr(desc: "avfilter graph create filter for buffer sink", err: err)
            return false
        }
        
        err = avfilter_link(abuffer_ctx, 0, aformat_ctx, 0)
        guard 0 <= err else {
            print_averr(err: err)
            return false
        }
        
        err = avfilter_link(aformat_ctx, 0, abuffer_sink_ctx, 0)
        guard 0 <= err else {
            print_averr(err: err)
            return false
        }
        
        err = avfilter_graph_config(audio_filter_graph, nil)
        guard 0 <= err else {
            print_averr(err: err)
            return false
        }
        
        let ptr = withUnsafeMutablePointer(to: &self.audioQueue) { (ptr) -> UnsafeMutablePointer<AVQueue<AVFrame>> in
            return ptr.withMemoryRebound(to: AVQueue<AVFrame>.self, capacity: MemoryLayout<AVQueue<AVFrame>>.stride){$0}
        }
        
        self.audioState = AudioState(audioContex: audioContext, abuffer_ctx: abuffer_ctx, abuffer_sink_ctx: abuffer_sink_ctx, audio_queue: ptr, audio_filtered_frame: av_frame_alloc())
        
        return true
    }
    
    
    
    //MARK: - setupSDL
    var window: OpaquePointer!
    var renderer: OpaquePointer!
    var texture: OpaquePointer!
    
    private func setupSDL() -> Bool {
        
        SDL_SetMainReady()
        
        guard 0 <= SDL_Init(UInt32(SDL_INIT_TIMER | SDL_INIT_AUDIO | SDL_INIT_VIDEO)) else {
            print("SDL_Init: " + String(cString: SDL_GetError()))
            return false
        }
        
        guard let w = SDL_CreateWindow("SwiftPlayer", 0, 0, Int32(screenSize.width), Int32(screenSize.height), SDL_WINDOW_OPENGL.rawValue | SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_BORDERLESS.rawValue) else {
            print("SDL_CreateWindow: " + String(cString: SDL_GetError()))
            return false
        }
        
        window = w
        
        guard let r = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_TARGETTEXTURE.rawValue) else {
            print("SDL_CreateRenderer: " + String(cString: SDL_GetError()))
            return false
        }
        
        renderer = r
        
        print(video_rect)
        
        guard let t = SDL_CreateTexture(renderer, Uint32(SDL_PIXELFORMAT_IYUV), Int32(SDL_TEXTUREACCESS_TARGET.rawValue), self.video_rect.w, self.video_rect.h) else {
            print("SDL_CreateTexture: " + String(cString: SDL_GetError()))
            return false
        }
        
        texture = t
        
        var wanted = SDL_AudioSpec()
        var obtained = SDL_AudioSpec()
        wanted.channels = 2
        wanted.format = SDL_AudioFormat(AUDIO_S16SYS)
        wanted.freq = 44100
        wanted.silence = 0
        wanted.size = 1024
        wanted.callback = audio_callback
        wanted.userdata = UnsafeMutableRawPointer(&audioState)
        
        guard 0 <= SDL_OpenAudio(&wanted, &obtained) else {
            print("SDL_OpenAudio failed : \(String(cString: SDL_GetError()))")
            return false
        }
        
        return true
    }
    
}

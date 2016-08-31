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
    var audio_filtered_frame: UnsafeMutablePointer<AVFrame>?
    var filter_helper: AVFilterHelper?
    let audioQueue: AudioQueue = AudioQueue()
}

let AUDIO_OUTPUT_SAMPLE_RATE    = 44100
let AUDIO_OUTPUT_CHANNELS       = 2
let AUDIO_OUTPUT_BITS           = 16

let AUDIO_OUTPUT_BUFFER_LENGTH  = AUDIO_OUTPUT_SAMPLE_RATE * AUDIO_OUTPUT_CHANNELS * (AUDIO_OUTPUT_BITS / 8) * 1024

class AudioQueue {
    let buffer = NSMutableData()
    var rpos = 0
    
    var lock: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    func write(write_buffer: UnsafeMutablePointer<UInt8>?, length: Int) {
        self.wait()

        if let buf = write_buffer {
            buffer.append(buf, length: length)
        }
        
        self.signal()
    }
    
    func read(read_buffer: UnsafeMutablePointer<UInt8>?, length: Int, reads: inout Int) {
        self.wait()
        
        if let buf = read_buffer {
            let readLength = buffer.length > rpos ? min(buffer.length - rpos, length) : 0
            
            buffer.getBytes(buf, range: NSRange(location: rpos, length: readLength))
                
            reads = readLength
            rpos += readLength
        } else {
            reads = 0
        }
        
        self.signal()
    }
    
    func wait() {
        lock.wait()
    }
    
    func signal() {
        lock.signal()
    }
}

public class Player: Operation {
    
    public let capture_queue = DispatchQueue(label: "capture", qos: DispatchQoS.userInteractive, attributes: DispatchQueue.Attributes.concurrent, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit)
    public let decode_queue = DispatchQueue(label: "decode", qos: .background, attributes: .concurrent, autoreleaseFrequency: .inherit)
    
    
    public var path: String
    
    public init(path: String) {
        
        self.path = path
        super.init()
        
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
        
        guard setupAudio() else {
            print("Audio Engine setup failed")
            return
        }
        
        let dstRect = AVMakeRect(aspectRatio: CGSize(width: Int(video_rect.w), height: Int(video_rect.h)), insideRect: CGRect(origin: CGPoint(), size: self.screenSize))
        
        self.dst_rect = SDL_Rect(x: Int32(dstRect.origin.x), y: Int32(dstRect.origin.y), w: Int32(dstRect.width), h: Int32(dstRect.height))
        
        self.startEventPulling()
        self.decodeFrames()
        
        self.startDisplayLink()
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
        
        videoQueue?.read(time: link.timestamp - first) { (frame) in
            SDL_UpdateYUVTexture(texture, &video_rect, frame.pointee.data.0, frame.pointee.linesize.0, frame.pointee.data.1, frame.pointee.linesize.1, frame.pointee.data.2, frame.pointee.linesize.2)
            SDL_RenderClear(renderer)
            var dst = dst_rect!
            SDL_RenderCopy(renderer, texture, &video_rect, &dst)
            SDL_RenderPresent(renderer)
        }
    }
    
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
                if self.videoQueue?.fulled ?? true {
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
                        
                        self.videoQueue?.write(frame: frame){
                            av_frame_unref(frame)
                        }
                    }
                    else if pkt.pointee.stream_index == self.audio_index, let audioContext = self.audioContext {
                        let ret = self.decode(ctx: audioContext, packet: pkt, frame: frame, got_frame: &self.got_frame, length: &self.length)
                        guard 0 <= ret else {
                            print_err(ret)
                            continue
                        }
                        
                        self.audioState?.filter_helper?.input(frame)
                        let audioBuffer = NSMutableData()
                        while true {
                            if self.audioState?.filter_helper?.output(self.audioState?.audio_filtered_frame) ?? true {
                                break
                            }
                            guard let data = self.audioState?.audio_filtered_frame?.pointee.data.0, let len = self.audioState?.audio_filtered_frame?.pointee.linesize.0 else {
                                break
                            }
                            audioBuffer.append(data, length: Int(len))
                        }
                        
                        let pcm_buf = AVAudioPCMBuffer(pcmFormat: self.audioFormat!, frameCapacity: AVAudioFrameCount(audioBuffer.length) / self.audioFormat!.streamDescription.pointee.mBytesPerFrame)
                       
                        pcm_buf.frameLength = pcm_buf.frameCapacity
                        let channels = UnsafeBufferPointer.init(start: pcm_buf.floatChannelData, count: Int(pcm_buf.format.channelCount))
                        audioBuffer.getBytes(channels[0], length: audioBuffer.length)
                        
                        self.audioPlayer?.scheduleBuffer(pcm_buf, completionHandler: {
                            print("finished")
                        })
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
    
    public var audioFilterHelper: AVFilterHelper?
    
    var videoQueue: AVFrameQueue?
    var audioState: AudioState?
    
    //MARK: - setupFFmpeg
    private func setupFFmpeg() -> Bool {
        
        av_register_all()
        avfilter_register_all()
        avformat_network_init()
        formatContext = avformat_alloc_context()
        
        var ret = avformat_open_input(&formatContext, path, nil, nil)
        
        if 0 > ret {
            print("Couldn't create format for \(path)")
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
        videoQueue = AVFrameQueue(time_base: videoStream?.pointee.time_base ?? AVRational())
        
        audio_index = av_find_best_stream(formatContext, AVMEDIA_TYPE_AUDIO, -1, -1, &audioCodec, 0)
        audioStream = formatContext?.pointee.streams.advanced(by: Int(audio_index)).pointee
        audioContext = avcodec_alloc_context3(audioCodec)
        avcodec_parameters_to_context(audioContext, audioStream?.pointee.codecpar)
        
        guard 0 <= avcodec_open2(audioContext, audioCodec, nil) else {
            print("Couldn't open codec for \(String(cString: avcodec_get_name(audioContext?.pointee.codec_id ?? AV_CODEC_ID_NONE)))")
            return false
        }
        
        let helper = AVFilterHelper.audioHelper(
            withSampleRate: audioContext!.pointee.sample_rate,
            in: audioContext!.pointee.sample_fmt,
            inChannelLayout: Int32(audioContext!.pointee.channel_layout),
            inChannels: audioContext!.pointee.channels,
            outSampleFormats: AV_SAMPLE_FMT_FLT,
            outSampleRates: 44100,
            outChannelLayouts: (AV_CH_FRONT_LEFT | AV_CH_FRONT_RIGHT),
            timeBase: audioStream!.pointee.time_base, context: audioContext!)
        self.audioFilterHelper = helper
        self.audioState = AudioState()
        self.audioState?.audioContex = audioContext
        self.audioState?.filter_helper = helper
        self.audioState?.audio_filtered_frame = av_frame_alloc()
        
        return true
    }
    
    var interruptionNotification: NSObjectProtocol? = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVAudioSessionInterruption, object: nil, queue: .main) { (noti) in
        print("🤔 audio interruption -> " + noti.description)
    }
    
    var routeNotification: NSObjectProtocol? = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVAudioSessionRouteChange, object: nil, queue: .main) { (noti) in
        print("🤔 audio route change -> " + noti.description)
    }
    
    var mediaResetNotification: NSObjectProtocol? = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVAudioSessionMediaServicesWereReset, object: nil, queue: .main) { (noti) in
        print("🤔 audio media reset -> " + noti.description)
    }
    
    var audioEngine: AVAudioEngine?
    var audioPlayer: AVAudioPlayerNode?
    var audioFormat: AVAudioFormat?
    
    func setupAudio() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        let ioBufferDuration = 128 * AUDIO_OUTPUT_SAMPLE_RATE
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setPreferredIOBufferDuration(TimeInterval(ioBufferDuration))
            try audioSession.setActive(true)
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
            return false
        }
        
        audioEngine = AVAudioEngine()
        audioPlayer = AVAudioPlayerNode()
        
        audioEngine?.attach(audioPlayer!)
        
        let mixer = audioEngine?.mainMixerNode
        mixer!.outputVolume = 1.0
        
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: Double(AUDIO_OUTPUT_SAMPLE_RATE), channels: 2)
        audioEngine!.connect(audioPlayer!, to: mixer!, format: audioFormat)
        
        if audioEngine!.isRunning {
            return true
        }
        
        audioEngine!.prepare()
        
        do {
            try audioEngine!.start()
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
            return false
        }
        
        audioPlayer!.play()
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
        
        return true
    }
    
}

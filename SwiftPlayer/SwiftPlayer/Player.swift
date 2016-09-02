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
import Accelerate

extension AVAudioPlayerNode {
    func schedule(format: AVAudioFormat, left: UnsafePointer<UInt8>, right: UnsafePointer<UInt8>, bufferLength: Int, completion: AVAudioNodeCompletionHandler? ) {
        let lbuf = left.withMemoryRebound(to: Float.self, capacity: bufferLength / MemoryLayout<Float>.size){$0}
        let rbuf = right.withMemoryRebound(to: Float.self, capacity: bufferLength / MemoryLayout<Float>.size){$0}
        let pcm_buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferLength / MemoryLayout<Float>.size))
        pcm_buf.frameLength = pcm_buf.frameCapacity / 2
        guard let channels = pcm_buf.floatChannelData else {
            return
        }
        vDSP_vclr(channels[0], 1, vDSP_Length(pcm_buf.frameLength))
        vDSP_vclr(channels[1], 1, vDSP_Length(pcm_buf.frameLength))
        vDSP_vadd(channels[0], 1, lbuf, 1, channels[0], 1, vDSP_Length(pcm_buf.frameLength))
        vDSP_vadd(channels[1], 1, rbuf, 1, channels[1], 1, vDSP_Length(pcm_buf.frameLength))
        self.scheduleBuffer(pcm_buf, completionHandler:completion)
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
                            
                            self.audioPlayers.forEach(){$0.stop()}
                            
                            self.displayLink?.isPaused = true
                            self.displayLink?.invalidate()
                            SDL_Quit()
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
    let aframe = av_frame_alloc()
    let audio_filtered_frame = av_frame_alloc()!
    
    var got_frame: Int32 = 0
    var length: Int32 = 0
 
    func decodeFrames() {
        decode_queue.async {
            defer {
                print("👏🏽 decode finished")
            }
            decode: while true {
                if false == self.displayLink?.isPaused && self.videoQueue?.fulled ?? true {
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
                    else if pkt.pointee.stream_index == self.audio_index, let ctx = self.audioContext {
                        let ret = self.decode(ctx: ctx, packet: pkt, frame: self.aframe, got_frame: &self.got_frame, length: &self.length)
                        guard 0 <= ret else {
                            print_err(ret)
                            continue
                        }
                        guard let aframe = self.aframe else {
                            break decode
                        }
                        
                        let len = Int(aframe.pointee.linesize.0)
                        let datas = aframe.pointee.datas
                        let dataCount = datas.reduce(0, { (result, ptr) -> Int in
                            return nil != ptr ? result + 1 : result
                        })
                        for playerIndex in 0..<(dataCount / 2) {
                            self.audioPlayers[playerIndex].schedule(format: self.audioFormat!, left: datas[playerIndex * 2]!, right: datas[playerIndex * 2 + 1]!, bufferLength: len, completion: nil)
                        }
                        if 1 == dataCount % 2 {
                            let player = dataCount / 2 + 1
                            let l = player * 2
                            let r = l
                            self.audioPlayers[player].schedule(format: self.audioFormat!, left: datas[l]!, right: datas[r]!, bufferLength: len, completion: nil)
                        }
                        
                        if self.displayLink?.isPaused ?? true {
                            DispatchQueue.main.async {
                                if self.displayLink?.isPaused ?? true {
                                    self.startDisplayLink()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    //MARK: - decode
    /// decode
    private func decode(ctx: UnsafeMutablePointer<AVCodecContext>, packet: UnsafeMutablePointer<AVPacket>, frame: UnsafeMutablePointer<AVFrame>?, got_frame: inout Int32, length: inout Int32) -> Int32 {
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
            length = frame?.pointee.pkt_size ?? 0
            
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
    
    var videoQueue: AVFrameQueue?
    
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
        
        av_dump_format(formatContext, 0, path, 0)
        
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
        audioContext?.pointee.properties = audioStream?.pointee.codec.pointee.properties ?? 0
        audioContext?.pointee.qmin = audioStream?.pointee.codec.pointee.qmin ?? 0
        audioContext?.pointee.qmax = audioStream?.pointee.codec.pointee.qmax ?? 0
        audioContext?.pointee.coded_width = audioStream?.pointee.codec.pointee.coded_width ?? 0
        audioContext?.pointee.coded_height = audioStream?.pointee.codec.pointee.coded_height ?? 0
        audioContext?.pointee.time_base = audioStream?.pointee.time_base ?? AVRational()
        
        
        guard 0 <= avcodec_open2(audioContext, audioCodec, nil) else {
            print("Couldn't open codec for \(String(cString: avcodec_get_name(audioContext?.pointee.codec_id ?? AV_CODEC_ID_NONE)))")
            return false
        }
        
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
    
    let audioEngine: AVAudioEngine = AVAudioEngine()
    var audioFormat: AVAudioFormat?
    
    var audioPlayers: [AVAudioPlayerNode] = []
    
    func setupAudio() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setActive(true)
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
            return false
        }
        
        audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(self.audioStream!.pointee.codecpar.pointee.sample_rate), channels: 2, interleaved: false)
        
        let mixer = audioEngine.mainMixerNode
        mixer.outputVolume = 1.0
        for i in 0..<Int(self.audioContext!.pointee.channels / 2 + self.audioContext!.pointee.channels % 2) {
            self.audioPlayers.append(AVAudioPlayerNode())
            audioEngine.attach(self.audioPlayers[i])
            audioEngine.connect(self.audioPlayers[i], to: mixer, format: audioFormat)
        }
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
            return false
        }
        
        self.audioPlayers.forEach(){$0.play()}
        
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

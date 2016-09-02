//
//  Player.swift
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 29..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

import Foundation
import ffmpeg
import AVFoundation
import Accelerate

extension AVAudioPlayerNode {
    func schedule(at: AVAudioTime? = nil, channels c: Int, format: AVAudioFormat, audioDatas: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, bufferLength len: Int, completion: AVAudioNodeCompletionHandler? ) {
        guard let datas = audioDatas else {
            return
        }
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(len))
        buf.frameLength = buf.frameCapacity
        let channels = buf.floatChannelData
        for i in 0..<8 {
            guard let data = datas[i] else {
                break
            }
            guard let channel = channels?[i % c] else {
                break
            }
            let floats = data.withMemoryRebound(to: Float.self, capacity: len){$0}
            if i < c {
                cblas_scopy(Int32(len), floats, 1, channel, 1)
            } else {
                vDSP_vadd(channel, 1, floats, 1, channel, 1, vDSP_Length(len))
            }
        }
        
        self.scheduleBuffer(buf, completionHandler: completion)
    }
}

public class Player: Operation {
    
    var videoSize: CGSize {
        guard let ctx = self.videoContext else {
            return CGSize()
        }
        return CGSize(width: Int(ctx.pointee.width), height: Int(ctx.pointee.height))
    }
    
    lazy var decode_queue: DispatchQueue? = DispatchQueue(label: "decode", qos: .background, attributes: .concurrent, autoreleaseFrequency: .inherit)
    
    
    public var path: String
    
    public init(path: String) {
        
        self.path = path
        super.init()
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
    
    public override func cancel() {
        self.audioQueue?.stop()
        self.videoQueue?.stop()
        self.audioPlayQueue?.suspend()
        self.decode_queue?.suspend()
        self.audioPlayer.stop()
        self.audioEngine.stop()
        super.cancel()
    }
    
    public typealias PlayerStartCompletionHandle = () -> Void
    var completion: PlayerStartCompletionHandle?
    public func start(completion: PlayerStartCompletionHandle ) {
        self.completion = completion
        self.start()
    }
    
    public override func main() {
        
        guard setupFFmpeg() else {
            print("find streams failed")
            return
        }
        
        guard setupAudio() else {
            print("Audio Engine setup failed")
            return
        }

        self.decodeFrames()
        
        self.completion?()
        
        self.startAudioPlay()
    }
    
    public typealias PlayerDecodeHanlder = (UnsafePointer<UInt8>, UnsafePointer<UInt8>, UnsafePointer<UInt8>, Int) -> Void
    
    public func requestVideoFrame(time: Double, decodeCompletion: PlayerDecodeHanlder) {
        self.videoQueue?.read(time: time, handle: { (frame) in
            decodeCompletion(frame.pointee.data.0!, frame.pointee.data.1!, frame.pointee.data.2!, Int(frame.pointee.linesize.0))
        })
    }
    
    lazy var audioPlayQueue: DispatchQueue? = DispatchQueue(label: "audio.queue", qos: .background)
    private func startAudioPlay() {
        audioPlayQueue?.async(execute: {
            while false == self.isCancelled {
                if self.audioQueue?.stopped() ?? true {
                    break
                }
                self.audioQueue?.read(handle: { (aframe) in
                    let len = Int(aframe.pointee.nb_samples)
                    let datas = aframe.pointee.extended_data
                    self.audioPlayer.schedule(channels: AVAudioSession.sharedInstance().preferredOutputNumberOfChannels, format: self.audioFormat!, audioDatas: datas, bufferLength: len, completion: {
                        
                    })
                })
            }
        })
   
    }
    
    let pkt = av_packet_alloc()
    let frame = av_frame_alloc()
    let aframe = av_frame_alloc()
    let audio_filtered_frame = av_frame_alloc()!
    
    var got_frame: Int32 = 0
    var length: Int32 = 0
 
    func decodeFrames() {
        decode_queue?.async {
            defer {
                print("👏🏽 decode finished")
                avcodec_send_packet(self.videoContext, nil)
                avcodec_receive_frame(self.videoContext, nil)
                avcodec_send_packet(self.audioContext, nil)
                avcodec_receive_frame(self.audioContext, nil)
            }
            decode: while false == self.isCancelled {
                if self.audioQueue?.stopped() ?? true || self.videoQueue?.stopped() ?? true {
                    break decode
                }
                if self.videoQueue!.fulled || self.audioQueue!.fulled {
                    continue
                }
                guard 0 <= av_read_frame(self.formatContext, self.pkt) else {
                    break decode
                }
                defer {
                    av_packet_unref(self.pkt)
                }
                
                if let pkt = self.pkt, let frame = self.frame {
                    if pkt.pointee.stream_index == self.video_index, let videoContext = self.videoContext {
                        let ret = self.decode(ctx: videoContext, packet: pkt, frame: frame, got_frame: &self.got_frame, length: &self.length)
                        defer {
                            av_frame_unref(frame)
                        }
                        guard 0 <= ret else {
                            print_err(ret)
                            continue
                        }
                        
                        self.videoQueue?.write(frame: frame){
                            
                        }
                    }
                    else if pkt.pointee.stream_index == self.audio_index, let ctx = self.audioContext {
                        let ret = self.decode(ctx: ctx, packet: pkt, frame: self.aframe, got_frame: &self.got_frame, length: &self.length)
                        defer {
                            av_frame_unref(self.aframe)
                        }
                        guard 0 <= ret else {
                            print_err(ret)
                            continue
                        }
                        self.audioQueue?.write(frame: self.aframe!, completion: {
                            
                        })
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
    
    public var formatContext: UnsafeMutablePointer<AVFormatContext>?
    
    public var video_index: Int32 = -1
    public var videoStream: UnsafeMutablePointer<AVStream>?
    public var videoCodec: UnsafeMutablePointer<AVCodec>?
    public var videoContext: UnsafeMutablePointer<AVCodecContext>?
    
    private(set) lazy var video_rect: SDL_Rect = {return SDL_Rect(x: 0, y: 0, w: self.videoContext?.pointee.width ?? 0, h: self.videoContext?.pointee.height ?? 0)}()
    
    public var audio_index: Int32 = -1
    public var audioStream: UnsafeMutablePointer<AVStream>?
    public var audioCodec: UnsafeMutablePointer<AVCodec>?
    public var audioContext: UnsafeMutablePointer<AVCodecContext>?
    
    var videoQueue: AVFrameQueue?
    var audioQueue: AVFrameQueue?
    
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
        videoQueue = AVFrameQueue(type: AVMEDIA_TYPE_VIDEO, time_base: videoStream?.pointee.time_base ?? AVRational())
        
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
        audioQueue = AVFrameQueue(type: AVMEDIA_TYPE_AUDIO, queueCount: 4096, time_base: audioContext!.pointee.time_base)
        
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
    
    var audioPlayer: AVAudioPlayerNode = AVAudioPlayerNode()
    
    func setupAudio() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setActive(true)
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
            return false
        }
        
        audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(self.audioStream!.pointee.codecpar.pointee.sample_rate), channels: AVAudioChannelCount(audioSession.preferredOutputNumberOfChannels), interleaved: false)
        
        let mixer = audioEngine.mainMixerNode
        mixer.outputVolume = 1.0
        
        audioEngine.attach(audioPlayer)
        audioEngine.connect(audioPlayer, to: mixer, format: audioFormat)
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
            return false
        }
        
        self.audioPlayer.play()
        
        return true
    }
    
}

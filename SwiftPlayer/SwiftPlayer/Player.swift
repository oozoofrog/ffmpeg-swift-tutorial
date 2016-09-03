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

protocol MediaData {
    var datas: [Data] {get}
    var linesizes: [Int] {get}
    var timeStamp: Double {get}
    init?(timeBase: AVRational, frame: UnsafeMutablePointer<AVFrame>)
}
struct VideoData: MediaData {
    let y: Data
    let u: Data
    let v: Data
    var datas: [Data] {
        return [y, u, v]
    }
    var linesizes: [Int] {
        return [lumaLength, chromaLength, chromaLength]
    }
    let timeStamp: Double
    let lumaLength: Int
    var chromaLength: Int {
        return lumaLength / 2
    }
    init?(timeBase: AVRational, frame: UnsafeMutablePointer<AVFrame>) {
        self.lumaLength = Int(frame.pointee.linesize.0)
        let height = Int(frame.pointee.height)
        guard let y = frame.pointee.data.0 else {
            return nil
        }
        self.y = Data(bytes: y, count: self.lumaLength * height)
        guard let u = frame.pointee.data.1 else {
            return nil
        }
        
        self.u = Data(bytes: u, count: self.lumaLength / 2 * (height / 2))
        guard let v = frame.pointee.data.2 else {
            return nil
        }
        self.v = Data(bytes: v, count: self.lumaLength / 2 * (height / 2))
        self.timeStamp = Double(av_frame_get_best_effort_timestamp(frame)) * av_q2d(timeBase)
    }
}
struct AudioData: MediaData {
    var datas: [Data] = []
    var linesizes: [Int] = []
    let timeStamp: Double
    
    init?(timeBase: AVRational, frame: UnsafeMutablePointer<AVFrame>) {
        for i in 0..<8 {
            guard let buffer = frame.pointee.extended_data[i] else {
                break
            }
            datas.append(Data(bytes: buffer, count: Int(frame.pointee.linesize.0)))
            linesizes.append(Int(frame.pointee.linesize.0))
        }
        if 0 == datas.count {
            return nil
        }
        self.timeStamp = Double(av_frame_get_best_effort_timestamp(frame)) * av_q2d(timeBase)
    }
}


class AVFrameQueue<D: MediaData> {
    
    private var quit: Bool = false
    
    var time_base: AVRational
    
    var containerQueue: [D] = []
    let queueLimit: Int
    let queue_lock: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    let type: AVMediaType
    init(type: AVMediaType, queueCount: Int = 1024, time_base: AVRational) {
        self.type = type
        self.time_base = time_base
        self.queueLimit = queueCount
    }
    
    func stop() {
        lock()
        defer {
            unlock()
        }
        quit = true
        self.containerQueue = []
    }
    
    func stopped() -> Bool {
        lock()
        defer {
            unlock()
        }
        return quit
    }
    
    func lock() {
        queue_lock.wait()
    }
    
    func ingore() -> Bool {
        return queue_lock.wait(timeout: .now()) == .timedOut
    }
    
    func unlock() {
        queue_lock.signal()
    }
    
    var waiting: Bool {
        lock()
        defer {
            unlock()
        }
        return self.queueLimit < containerQueue.count
    }
    
    var readTimeStamp: Double = 0
    
    func write(_ frame: UnsafeMutablePointer<AVFrame>) {
        lock()
        defer {
            unlock()
        }
        if quit {
            return
        }
        guard let data = D(timeBase: self.time_base, frame: frame) else {
            return
        }
        containerQueue.insert(data, at: 0)
    }
    
    func read(time: Double = -1, handle: (D) -> Void) {
        lock()
        defer {
            unlock()
        }
        if quit || 0 == self.containerQueue.count {
            return
        }

        while 0 < self.containerQueue.count {
            guard let next = self.containerQueue.popLast() else {
                return
            }
            readTimeStamp = next.timeStamp
            if -1 == time || readTimeStamp >= time {
                handle(next)
                break
            }
        }
    }
}

extension AVAudioPlayerNode {
    func schedule(at: AVAudioTime? = nil, channels c: Int, format: AVAudioFormat, audioDatas datas: [UnsafePointer<UInt8>], bufferLength len: Int, completion: AVAudioNodeCompletionHandler? ) {
        
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(len))
        buf.frameLength = buf.frameCapacity
        let channels = buf.floatChannelData
        for i in 0..<datas.count {
            let data = datas[i]
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
        if 0 < avcodec_is_open(videoContext) {
            avcodec_close(videoContext)
        }
        avcodec_free_context(&videoContext)
        
        if 0 < avcodec_is_open(audioContext) {
            avcodec_close(audioContext)
        }
        avcodec_free_context(&audioContext)
        
        avformat_close_input(&formatContext)
        avformat_free_context(formatContext)
        
        avformat_network_deinit()
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
            let y: UnsafePointer<UInt8> = frame.datas[0].withUnsafeBytes(){$0}
            let u: UnsafePointer<UInt8> = frame.datas[1].withUnsafeBytes(){$0}
            let v: UnsafePointer<UInt8> = frame.datas[2].withUnsafeBytes(){$0}
            decodeCompletion(y, u, v, frame.linesizes[0])
        })
    }
    
    var audioPlayStarted: Bool = false
    lazy var audioPlayQueue: DispatchQueue? = DispatchQueue(label: "audio.queue", qos: .background)
    private func startAudioPlay() {
        audioPlayStarted = true
        audioPlayQueue?.async(execute: {
            while false == self.isCancelled {
                if self.audioQueue?.stopped() ?? true {
                    break
                }
                self.audioQueue?.read(handle: { (aframe) in
                    let len = aframe.linesizes[0] / MemoryLayout<Float>.size / 2
                    let datas: [UnsafePointer<UInt8>] = aframe.datas.flatMap(){$0.withUnsafeBytes(){$0}}
                    self.audioPlayer.schedule(channels: AVAudioSession.sharedInstance().preferredOutputNumberOfChannels, format: self.audioFormat!, audioDatas: datas, bufferLength: len, completion: {
                        
                    })
                })
            }
        })
    }
    
    let audio_filtered_frame = av_frame_alloc()!
    
    var got_frame: Int32 = 0
    var length: Int32 = 0
 
    func decodeFrames() {
        decode_queue?.async {
            
            var packet = AVPacket()
            var frame = AVFrame()
            defer {
                print("👏🏽 decode finished")
                
                av_packet_unref(&packet)
                av_frame_unref(&frame)
                avcodec_send_packet(self.videoContext, nil)
                avcodec_send_packet(self.audioContext, nil)
            }
            decode: while false == self.isCancelled {
                guard let video = self.videoQueue, let audio = self.audioQueue else {
                    break decode
                }
                if video.stopped() || audio.stopped() {
                    break decode
                }
                if video.waiting || audio.waiting {
                    continue
                }
                guard 0 <= av_read_frame(self.formatContext, &packet) else {
                    break decode
                }
                defer {
                    av_packet_unref(&packet)
                }
                
                if packet.stream_index == self.video_index, let videoContext = self.videoContext {
                    let ret = self.decode(ctx: videoContext, packet: &packet, frame: &frame, got_frame: &self.got_frame, length: &self.length)
                    guard 0 <= ret else {
                        print_err(ret)
                        continue
                    }
                    defer {
                        av_frame_unref(&frame)
                    }
                    video.write(&frame)
                }
                else if packet.stream_index == self.audio_index, let ctx = self.audioContext {
                    let ret = self.decode(ctx: ctx, packet: &packet, frame: &frame, got_frame: &self.got_frame, length: &self.length)
                    guard 0 <= ret else {
                        print_err(ret)
                        continue
                    }
                    defer {
                        av_frame_unref(&frame)
                    }
                    audio.write(&frame)
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
            av_packet_unref(packet)
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
    
    var videoQueue: AVFrameQueue<VideoData>?
    var audioQueue: AVFrameQueue<AudioData>?
    
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
        videoQueue = AVFrameQueue(type: AVMEDIA_TYPE_VIDEO, queueCount: 64, time_base: videoStream?.pointee.time_base ?? AVRational())
        
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
        audioQueue = AVFrameQueue(type: AVMEDIA_TYPE_AUDIO, queueCount: 128, time_base: audioContext!.pointee.time_base)
        
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
    var channels: Int = 0
    
    func setupAudio() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
            try audioSession.setActive(true)
        } catch let err as NSError {
            assertionFailure(err.localizedDescription)
            return false
        }
        
        channels = audioSession.preferredOutputNumberOfChannels
        
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

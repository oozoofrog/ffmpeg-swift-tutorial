//
//  main.swift
//  tutorial6
//
//  Created by Kwanghoon Choi on 2016. 9. 4..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import AVFoundation
import CoreAudio
import Accelerate

var path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/sample.mp4")

struct FileData {
    let handle: FileHandle
    let length: UInt64
}

typealias AVIOReadHandle = (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32
func read_function(_ user: UnsafeMutableRawPointer?, _ buf: UnsafeMutablePointer<UInt8>?, _ len: Int32) -> Int32 {
    guard let fd = user?.assumingMemoryBound(to: FileData.self) else {
        return -1
    }
    
    let reads = fd.pointee.handle
    let data = reads.readData(ofLength: Int(len))
    let readSize = min(len, Int32(data.count))
    data.copyBytes(to: buf!, count: Int(readSize))
    if Int(readSize) < data.count {
        reads.seek(toFileOffset: UInt64(reads.offsetInFile - UInt64(data.count) - UInt64(readSize)))
    }
    
    return Int32(readSize)
}

func seeking_function(_ user: UnsafeMutableRawPointer?, _ offset: Int64, _ whence: Int32) -> Int64 {
    guard let fd = user?.assumingMemoryBound(to: FileData.self) else {
        return -1
    }
    if whence == AVSEEK_SIZE {
        return Int64(fd.pointee.length)
    }
    let reads = fd.pointee.handle
    
    switch whence {
    case AVSEEK_SIZE, SEEK_END:
        return Int64(fd.pointee.length)
    case SEEK_SET:
        reads.seek(toFileOffset: UInt64(offset))
    case SEEK_CUR:
        reads.seek(toFileOffset: reads.offsetInFile + UInt64(offset))
    default:
        return -1
    }
    return 0
}

func outputAudioObjectID() -> AudioDeviceID {
    
    var id: AudioDeviceID = 0
    var size: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMaster)
    let ret = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    guard ret == kAudioHardwareNoError, 0 < id else {
        assertionFailure()
        return 0
    }
    
    var name = [UInt8](repeating:0, count:1024)
    size = UInt32(1024)
    addr.mSelector = kAudioDevicePropertyDeviceName
    guard kAudioHardwareNoError == AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) else {
        assertionFailure()
        return 0
    }
    
    let nameStr = String(cString: name)
    
    name.removeAll()
    addr.mSelector = kAudioDevicePropertyDeviceManufacturer
    guard kAudioHardwareNoError == AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) else {
        assertionFailure()
        return 0
    }
    let chNameStr = String(cString: name)
    print(id)
    print(nameStr)
    print(chNameStr)
    
    return id
}

func outputChannels(forId id: AudioDeviceID) -> Int32 {
    
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyPreferredChannelLayout, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMaster)
    
    var layout = AudioChannelLayout()
    var size = UInt32(MemoryLayout<AudioChannelLayout>.stride)
    let ret = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &layout)
    guard kAudioHardwareNoError == ret else {
        print(ret)
        assertionFailure()
        return 0
    }
    
    return Int32(layout.mNumberChannelDescriptions)
}

let videoThread = DispatchQueue(label: "com.video.queue")
let audioThread = DispatchQueue(label: "com.audio.queue")
let videoLock = DispatchSemaphore(value: 0)
let audioLock = DispatchSemaphore(value: 0)
func test() {
    av_register_all()
    avformat_network_init()
    defer {
        avformat_network_deinit()
        print("test closed")
    }
    
    videoThread.async {
        
        let reads = try! FileHandle(forReadingFrom: path)
        defer {
            reads.closeFile()
        }
        
        var videoFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        var videoIOCtx: UnsafeMutablePointer<AVIOContext>? = nil
        var videoFileData: FileData = FileData(handle: reads, length: {
            reads.seekToEndOfFile()
            let length = reads.offsetInFile
            reads.seek(toFileOffset: 0)
            return length
            }())
        
        var videoFileBuffer = av_mallocz(8192).assumingMemoryBound(to: UInt8.self)
        
        
        
        videoFormatCtx = avformat_alloc_context()
        
        if nil == videoFormatCtx {
            print("couldn't allocate video format context")
            return
        }
        
        videoIOCtx = avio_alloc_context(videoFileBuffer, 8192, 0, &videoFileData, read_function, nil, seeking_function)
        if nil == videoIOCtx {
            print("couldn't create video io context")
            return
        }
        videoFormatCtx?.pointee.pb = videoIOCtx
        
        guard 0 <= avformat_open_input(&videoFormatCtx, path.path, nil, nil) else {
            print("failed open file \(path.path)")
            return
        }
        defer {
            avformat_close_input(&videoFormatCtx)
        }
        
        guard 0 <= avformat_find_stream_info(videoFormatCtx, nil) else {
            print("couldn't find stream info for video")
            return
        }
        
        av_dump_format(videoFormatCtx, 0, path.path, 0)
        
        let videoStream = av_find_best_stream(videoFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        
        var pkt = AVPacket()
        while true {
            var ret = av_read_frame(videoFormatCtx, &pkt)
            if IS_AVERROR_EOF(ret) {
                break
            } else if 0 > ret {
                continue
            }
            defer {
                av_packet_unref(&pkt)
            }
            switch pkt.stream_index {
            case videoStream:
                break
            default:
                break
            }
        }
        videoLock.signal()
    }
    
    audioThread.async {
        
        let reads = try! FileHandle(forReadingFrom: path)
        defer {
            reads.closeFile()
        }
        
        var audioFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        var audioIOCtx: UnsafeMutablePointer<AVIOContext>? = nil
        var audioFileData: FileData = FileData(handle: reads, length: {
            reads.seekToEndOfFile()
            let length = reads.offsetInFile
            reads.seek(toFileOffset: 0)
            return length
            }())
        
        var audioFileBuffer = av_mallocz(8192).assumingMemoryBound(to: UInt8.self)
        
        
        
        audioFormatCtx = avformat_alloc_context()
        
        if nil == audioFormatCtx {
            print("couldn't allocate video format context")
            return
        }
        
        audioIOCtx = avio_alloc_context(audioFileBuffer, 8192, 0, &audioFileData, read_function, nil, seeking_function)
        if nil == audioIOCtx {
            print("couldn't create video io context")
            return
        }
        audioFormatCtx?.pointee.pb = audioIOCtx
        
        guard 0 <= avformat_open_input(&audioFormatCtx, path.path, nil, nil) else {
            print("failed open file \(path.path)")
            return
        }
        defer {
            avformat_close_input(&audioFormatCtx)
        }
        
        guard 0 <= avformat_find_stream_info(audioFormatCtx, nil) else {
            print("couldn't find stream info for video")
            return
        }
        
        let audioStream = av_find_best_stream(audioFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        let audioContext = audioFormatCtx?.pointee.streams?[Int(audioStream)]?.pointee.codec
        let codec = avcodec_find_decoder(audioContext?.pointee.codec_id ?? AV_CODEC_ID_NONE)
        
        guard 0 <= avcodec_open2(audioContext, codec, nil) else {
            print("couldn't open audio codec for \(String(cString: avcodec_get_name(codec?.pointee.id ?? AV_CODEC_ID_NONE)))")
            return
        }
        
        guard let stream = audioFormatCtx?.pointee.streams?[Int(audioStream)], let ctx = audioContext else {
            return
        }
        
        let id = outputAudioObjectID()
        let channels = outputChannels(forId: id)
        
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(44100), channels: AVAudioChannelCount(channels), interleaved: false)
        do {
            
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            
            engine.prepare()
            try engine.start()
        } catch {
            print(error.localizedDescription)
        }
        
        player.play()
        
        var nameBuf = [Int8](repeating:0, count:128)
        av_get_channel_layout_string(&nameBuf, 128, ctx.pointee.channels, ctx.pointee.channel_layout)
        let channel_layout_name: String = String(cString: nameBuf)
        var time_base = stream.pointee.time_base
        var resample = AVFilterHelper()
        guard resample.setup(audioFormatCtx!, audioStream: stream, abuffer: "time_base=\(time_base.num)/\(time_base.den):sample_rate=\(stream.pointee.codecpar.pointee.sample_rate):sample_fmt=\(String(cString: av_get_sample_fmt_name(ctx.pointee.sample_fmt))):channel_layout=\(channel_layout_name):channels=\(ctx.pointee.channels)", aformat: "sample_fmts=\(String(cString: av_get_sample_fmt_name(AV_SAMPLE_FMT_FLT))):sample_rates=\(44199):channel_layouts=stereo") else {
            return
        }
        var pkt = AVPacket()
        var frame = AVFrame()
        var ret: Int32 = 0
        let group = DispatchGroup()
        decode: while true {
            ret = av_read_frame(audioFormatCtx, &pkt)
            if IS_AVERROR_EOF(ret) {
                break
            } else if 0 > ret {
                continue
            }
            switch pkt.stream_index {
                
            case audioStream:
                ret = avcodec_send_packet(ctx, &pkt)
                if 0 > ret && ret != AVERROR_CONVERT(EAGAIN) && false == IS_AVERROR_EOF(ret) {
                    continue
                }
                ret = avcodec_receive_frame(ctx, &frame)
                if 0 > ret && ret != AVERROR_CONVERT(EAGAIN) && false == IS_AVERROR_EOF(ret) {
                    continue
                }
                
                resample.applyFilter(&frame)
                let result = resample.filterFrame!
                var pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(result.pointee.linesize.0 / result.pointee.channels / Int32(MemoryLayout<Float>.size)))
                pcm.frameLength = AVAudioFrameCount(result.pointee.nb_samples)
                guard let channels = pcm.floatChannelData else {
                    break
                }
                guard let audioData = result.pointee.data.0 else {
                    break
                }
                let floats: UnsafeMutablePointer<Float> = audioData.withMemoryRebound(to: Float.self, capacity: Int(pcm.frameLength)){$0}
                let left = floats
                let right = floats.advanced(by: 1)
                cblas_scopy(Int32(pcm.frameCapacity), left, 2, channels[0], 1)
                cblas_scopy(Int32(pcm.frameCapacity), right, 2, channels[1], 1)
                
                let pts = Double(result.pointee.pkt_pts) * av_q2d(time_base)
                let dur = Double(result.pointee.pkt_duration) * av_q2d(time_base)
                group.enter()
                player.scheduleBuffer(pcm, at: nil, options: [], completionHandler: {
                    group.leave()
                })
            default:
                break
            }
        }
        
        
        group.notify(queue: audioThread, execute: {
            print("playing finished")
            audioLock.signal()
        })
        
        defer {
            av_packet_unref(&pkt)
        }
        audioLock.wait()
        audioLock.signal()
    }
    
    videoLock.wait()
    audioLock.wait()
}

test()

//
//enum SyncType {
//    case audio, video, external
//}
//
//var path =  try! FileManager.default.url(for: .musicDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("sample.mp3")
//
//let SDL_AUDIO_BUFFER_SIZE = 1024
//let MAX_AUDIO_FRAME_SIZE = 192000
//
//let MAX_AUDIOQ_SIZE = (5 * 16 * 1024)
//let MAX_VIDEOQ_SIZE = (5 * 256 * 1024)
//
//let AV_SYNC_THRESHOLD = 0.01
//let AV_NOSYNC_THRESHOLD = 10.0
//
//let SAMPLE_CORRECTION_PERCENT_MAX = 10
//let AUDIO_DIFF_AVG_NB = 20
//
//let VIDEO_PICTURE_QUEUE_SIZE = 1
//
//let DEFAULT_AV_SYNC_TYPE: SyncType = .video
//
//struct PacketQueue {
//    var first_pkt: UnsafeMutablePointer<AVPacketList>? = nil
//    var last_pkt: UnsafeMutablePointer<AVPacketList>? = nil
//    var nb_packets: Int = 0
//    var size: Int = 0
//    var lock: DispatchSemaphore = DispatchSemaphore(value: 0)
//}
//
//struct VideoPicture {
//    var luma: Data? = nil
//    var chroma: [Data]? = nil
//    var width: Int = 0, height: Int = 0
//    var allocated: Bool = false
//    var pts: Double = 0
//}
//
//struct AudioBuffer {
//    var buffers: [Data] = []
//    var linesize: Int = 0
//    let bytesPerFrame = MemoryLayout<Float>.size
//    func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
//        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(linesize / bytesPerFrame))
//        buf.frameLength = buf.frameCapacity / 2
//        if Int(format.channelCount) < buffers.count {
//
//        }
//    }
//}
//
//class VideoState {
//    var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
//    var videoStream: Int32 = -1
//    var audioStream: Int32 = -1
//
//    var av_sync_type: SyncType = .external
//    var external_clock: Double = 0.0 /* external clock base */
//    var external_clock_time: Int = 0
//
//    var audio_clock: Double = 0.0
//    var audio_st: UnsafeMutablePointer<AVStream>? = nil
//    var audio_ctx: UnsafeMutablePointer<AVCodecContext>? = nil
//    var audioq: PacketQueue = PacketQueue()
//    uint8_t         audio_buf[(AVCODEC_MAX_AUDIO_FRAME_SIZE * 3) / 2];
//    unsigned int    audio_buf_size;
//    unsigned int    audio_buf_index;
//    AVFrame         audio_frame;
//    AVPacket        audio_pkt;
//    uint8_t         *audio_pkt_data;
//    int             audio_pkt_size;
//    int             audio_hw_buf_size;
//    double          audio_diff_cum; /* used for AV difference average computation */
//    double          audio_diff_avg_coef;
//    double          audio_diff_threshold;
//    int             audio_diff_avg_count;
//    double          frame_timer;
//    double          frame_last_pts;
//    double          frame_last_delay;
//    double          video_clock; ///<pts of last decoded frame / predicted pts of next decoded frame
//    double          video_current_pts; ///<current displayed pts (different from video_clock if frame fifos are used)
//    int64_t         video_current_pts_time;  ///<time (av_gettime) at which we updated video_current_pts - used to have running video pts
//    AVStream        *video_st;
//    AVCodecContext  *video_ctx;
//    PacketQueue     videoq;
//    struct SwsContext *sws_ctx;
//
//    VideoPicture    pictq[VIDEO_PICTURE_QUEUE_SIZE];
//    int             pictq_size, pictq_rindex, pictq_windex;
//    SDL_mutex       *pictq_mutex;
//    SDL_cond        *pictq_cond;
//
//    SDL_Thread      *parse_tid;
//    SDL_Thread      *video_tid;
//
//    char            filename[1024];
//    int             quit;
//}

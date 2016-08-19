//
//  tutorial1.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

import UIKit
import ffmpeg
import SDL
import AVFoundation

func cPrint(cString: UnsafePointer<UInt8>) {
    print(String(cString: cString))
}

func cPrint(cString: UnsafePointer<Int8>) {
    print(String(cString: cString))
}

enum TutorialIndex: Int {
    case tutorial1 = 1
    case tutorial2, tutorial3, tutorial4
    case tutorialNumber
    
    func runTutorial(_ paths:[String]) {
        var tutorial: Tutorial? = nil
        switch self {
        case .tutorial1:
            tutorial = Tutorial1(paths: paths)
        case .tutorial2:
            tutorial = Tutorial2(paths: paths)
        case .tutorial3:
            tutorial = Tutorial3(paths: paths)
        case .tutorial4:
            tutorial = Tutorial4(paths: paths)
        default:
            break
        }
        tutorial?.run()
    }
    
    static let all: [TutorialIndex] = (1..<TutorialIndex.tutorialNumber.rawValue).flatMap(){TutorialIndex(rawValue: $0)}
}

protocol Tutorial {
    var docPath: String { get }
    var paths: [String] { set get }
    var writePath: String { get }
    
    var screenSize: CGSize { get }
    mutating func run()
}

extension Tutorial {
    var docPath: String {
        return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    }
    var writePath: String {
        return docPath + "/exports/\(String(describing: type(of: self)))"
    }
    var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }
}

/**
 *  converted from tutorial1.c
 */
struct Tutorial1: Tutorial {
    var paths: [String]
    
    func Saveframe(_ pFrame: UnsafeMutablePointer<AVFrame>, width: Int32, height: Int32, iFrame: Int32) {
        let writePath = self.writePath + "/frame\(iFrame).ppm"
        
        do {
            
            
            if false == FileManager.default.fileExists(atPath: writePath) {
                try FileManager.default.createDirectory(atPath: self.writePath, withIntermediateDirectories: true, attributes: nil)
                FileManager.default.createFile(atPath: writePath, contents: nil, attributes: nil)
            }
            
            let writeHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: writePath))
            
            defer {
                writeHandle.synchronizeFile()
                writeHandle.closeFile()
            }
            guard let header = "P6\n\(width) \(height)\n255\n".data(using: String.Encoding.ascii) else {
                return
            }
            writeHandle.write(header)
            
            for y in 0..<height {
                let bytes = pFrame.pointee.data.0?.advanced(by: Int(y) * Int(pFrame.pointee.linesize.0))
                writeHandle.write(Data(bytes: UnsafePointer<UInt8>(bytes!), count: Int(pFrame.pointee.linesize.0)))
            }
            
        } catch let err as NSError {
            assertionFailure("\nwrite to -> \(writePath)\n" + err.localizedDescription)
        }
    }
    
    mutating func run() {
        var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = avformat_alloc_context()
        var i: Int32 = 0, videoStream: Int32 = 0
        var pCodecCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var pCodec: UnsafeMutablePointer<AVCodec>? = nil
        var pFrame: UnsafeMutablePointer<AVFrame>? = nil
        var pFrameRGB: UnsafeMutablePointer<AVFrame>? = nil
        var packet = AVPacket()
        var frameFinished: Int32 = 0
        var numBytes: Int32 = 0
        
        var optionsDict: UnsafeMutablePointer<OpaquePointer?>? = nil
        var buffer: UnsafeMutablePointer<UInt8>? = nil
        
        //        AVDictionaryEntry
        //        var optionsDict: UnsafeMutablePointer<AVDictionary> = nil
        var sws_ctx: OpaquePointer? = nil
        
        if isErr(avformat_open_input(&pFormatCtx, paths[0], nil, nil), nil) {
            return
        }
        defer {
            if nil != pFormatCtx {
                avformat_free_context(pFormatCtx)
                print("format closed")
            }
        }
        
        if isErr(avformat_find_stream_info(pFormatCtx, nil), nil) {
            return
        }
        
        av_dump_format(pFormatCtx, 0, paths[0], 0)
        
        videoStream = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, &pCodec, 0)
        
        if isErr(videoStream, "av_find_best_stream") {
            return
        }
        
        if nil == pCodec {
            print("Unsupported codec!")
            return
        }
        
        let params: UnsafePointer<AVCodecParameters> = pFormatCtx!.pointee.streams[Int(videoStream)]!.pointee.codecpar.cast()
        pCodecCtx = avcodec_alloc_context3(pCodec!)
        if isErr(avcodec_parameters_to_context(pCodecCtx, params), "avcodec_parameters_to_context") {
            return
        }
        
        defer {
            print("close codec context")
            avcodec_close(pCodecCtx)
            
        }
        
        if nil == pCodecCtx {
            return
        }
        
        if isErr(avcodec_open2(pCodecCtx, pCodec, optionsDict), "avcodec_open2") {
            return
        }
        
        defer {
            av_frame_free(&pFrameRGB)
            av_frame_free(&pFrame)
        }
        
        pFrame = av_frame_alloc()
        pFrameRGB = av_frame_alloc()
        let width: Int32 = params.pointee.width
        let height: Int32 = params.pointee.height
        let pix_fmt = AVPixelFormat(rawValue: params.pointee.format)
        let pix_fmt_name = av_get_pix_fmt_name(pix_fmt)!
        print(String.init(cString: pix_fmt_name))
        
        numBytes = av_image_get_buffer_size(AV_PIX_FMT_RGB24, width, height, 1)
        buffer = av_malloc(Int(numBytes) * MemoryLayout<UInt8>.stride).assumingMemoryBound(to: UInt8.self)
        
        sws_ctx = sws_getContext(width, height, pix_fmt, width, height, AV_PIX_FMT_RGB24, SWS_BILINEAR, nil, nil, nil)
        
        var data = pFrameRGB?.o.data
        let rgbDataPtr = withUnsafeMutablePointer(to: &data){$0}
        var linesize = pFrameRGB?.o.linesize
        let rgbLinesizePtr = withUnsafeMutablePointer(to: &linesize){$0}
        if isErr(av_image_fill_arrays(rgbDataPtr.cast(), rgbLinesizePtr.cast(), buffer, AV_PIX_FMT_RGB24, width, height, 1), "av_image_fill_arrays") {
            return
        }
        
        defer {
            
            av_packet_unref(&packet)
            
            if nil != pFrame {
                av_frame_free(&pFrame)
            }
            
            av_free(buffer)
            if nil != pFrameRGB {
                av_frame_free(&pFrameRGB)
            }
        }
        while 0 <= av_read_frame(pFormatCtx, &packet) {
            if packet.stream_index == videoStream {
                var result: Int32 = 0
                repeat {
                    result = avcodec_send_packet(pCodecCtx, &packet)
                } while result == AVERROR_CONVERT(EAGAIN)
                if isErr(result, "send packet") {
                    return
                }
                repeat {
                    result = avcodec_receive_frame(pCodecCtx, pFrame)
                } while result == AVERROR_CONVERT(EAGAIN)
                if isErr(result, "receive frame") {
                    return
                }
                var data = pFrame?.o.data
                var linesize = pFrame?.o.linesize
                let dataPtr = <<&data
                let linesizePtr = <<&linesize
                sws_scale(sws_ctx,
                          dataPtr?.cast(),
                          linesizePtr?.cast(),
                          0,
                          pCodecCtx!.pointee.height,
                          rgbDataPtr.cast(),
                          rgbLinesizePtr.cast())
                i += 1
                if i <= 5 {
                    Saveframe(pFrameRGB!, width: (pCodecCtx?.pointee.width)!, height: (pCodecCtx?.pointee.height)!, iFrame: i)
                }
            }
            av_packet_unref(&packet)
        }
    }
}

/**
 *  Tutorial2
 *  use SDL2
 */
struct Tutorial2: Tutorial {
    var paths: [String]
    
    init(paths: [String]) {
        self.paths = paths
    }
    
    mutating func run() {
        
        guard let helper = AVHelper(inputPath: paths[0]) else {
            return
        }
        
        guard helper.open() else {
            return
        }
        
        var pFormatCtx = helper.formatContext
        
        let screenSize = UIScreen.main.bounds.size
        
        guard  SDLHelper().sdl_init(UInt32(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) else {
            return
        }
        // SDL has multiple window no use SDL_SetVideoMode for SDL_Surface
        let window = SDL_CreateWindow(String(describing: type(of: self)), SDL_WINDOWPOS_UNDEFINED_MASK | 0, SDL_WINDOWPOS_UNDEFINED_MASK | 0, Int32(UIScreen.main.bounds.width), Int32(UIScreen.main.bounds.height), SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_OPENGL.rawValue | SDL_WINDOW_BORDERLESS.rawValue)
        guard nil != window else {
            print("SDL: couldn't create window")
            return
        }
        
        let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_TARGETTEXTURE.rawValue | SDL_RENDERER_ACCELERATED.rawValue)
        
        let texture = SDL_CreateTexture(renderer, UInt32(SDL_PIXELFORMAT_IYUV), Int32(SDL_TEXTUREACCESS_STREAMING.rawValue), helper.width, helper.height)
        defer {
            SDL_DestroyTexture(texture)
            SDL_DestroyRenderer(renderer)
            SDL_DestroyWindow(window)
        }
        
        let rect: SDL_Rect = SDL_Rect(x: 0, y: 0, w: helper.size.width.cast(), h: helper.size.height.cast())// CGRect(origin: CGPoint(), size: helper.size).rect
        let dst_rect = aspectFit(rect: rect, inside: UIScreen.main.bounds)
        
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE)
        var event = SDL_Event()
        1
        helper.decode(frameHandle: { (type, frame) -> AVHelper.HandleResult in
            guard let frame = frame, type == AVMEDIA_TYPE_VIDEO else {
                return .ignored
            }
            update(frame: frame.cast(), texture: texture, renderer: renderer, toRect: dst_rect)
            return .succeed
        }) { () -> Bool in
            SDL_PollEvent(&event)
            switch SDL_EventType(rawValue: event.type) {
            case SDL_QUIT, SDL_FINGERDOWN:
                return false
            default:
                return true
            }
        }
    }
}

struct  Tutorial3: Tutorial {
    var paths: [String]
    
    static let SDL_AUDIO_BUFFER_SIZE: Int32 = 1024
    static let MAX_AUDIO_FRAME_SIZE: Int32 = 192000
    
    struct PacketQueue {
        var first_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var last_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var nb_packet: Int32 = 0
        var size: Int32 = 0
        var mutex: OpaquePointer = SDL_CreateMutex()
        var cond: OpaquePointer = SDL_CreateCond()
    }
    
    static var audioq: PacketQueue = PacketQueue()
    static var quit: Int32 = 0
    
    static func packet_queue_put(q: UnsafeMutablePointer<PacketQueue>?, pkt: UnsafeMutablePointer<AVPacket>?) -> Int32 {
        var q = q
        if nil == pkt {
            if isErr(av_packet_ref(pkt, av_packet_alloc()), "packet queue put ref packet") {
                return -1
            }
        }
        
        let pkt1: UnsafeMutablePointer<AVPacketList> = av_malloc(MemoryLayout<AVPacketList>.stride).bindMemory(to: AVPacketList.self, capacity: MemoryLayout<AVPacketList>.stride)
   
        if let pkt = pkt {
            pkt1.pointee.pkt = pkt.pointee
        }
        pkt1.pointee.next = nil
        SDL_LockMutex(q?.pointee.mutex)
        
        if nil == q?.pointee.last_pkt {
            q?.pointee.first_pkt = pkt1
        } else {
            q?.pointee.last_pkt?.pointee.next = pkt1
        }
        
        q?.pointee.last_pkt = pkt1
        q?.pointee.nb_packet += 1
        q?.o.size += pkt1.o.pkt.size
        SDL_CondSignal(q?.o.cond)
        SDL_UnlockMutex(q?.o.mutex)
        return 0
    }
    
    static func packet_queue_get(q: UnsafeMutablePointer<PacketQueue>?, pkt: inout UnsafeMutablePointer<AVPacket>?, block: Int32) -> Int32 {
        guard let queue = q else {
            return 0
        }
        var q = queue
        var pkt1: UnsafeMutablePointer<AVPacketList>? = nil
        var ret: Int32 = 0
        SDL_LockMutex(q.o.mutex)
        while true {
            if 1 == quit {
                ret = -1
                break
            }
            
            pkt1 = q.o.first_pkt
            if let pkt1 = pkt1 {
                q.o.first_pkt = pkt1.o.next
                if nil == q.o.first_pkt {
                    q.o.last_pkt = nil
                }
                q.o.nb_packet -= 1
                q.o.size -= pkt1.o.pkt.size
                pkt?.o = pkt1.o.pkt
                av_free(pkt1.castRaw(from: AVPacketList.self))
                ret = 1
                break
            } else if 0 == block {
                ret = 0
                break
            } else {
                SDL_CondWait(q.o.cond, q.o.mutex)
            }
        }
        SDL_UnlockMutex(q.o.mutex)
        return ret
    }
    
    static var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
    static var frame: UnsafeMutablePointer<AVFrame> = av_frame_alloc()
    static var audio_pkt_data: UnsafeMutablePointer<UInt8>? = nil
    static var audio_pkt_size: Int32 = 0
    
    static func audio_decode_frame(aCodecCtx: UnsafeMutablePointer<AVCodecContext>?, audio_buf: UnsafeMutablePointer<UInt8>?, buf_size: Int32) -> Int32 {

        guard let aCodecCtx = aCodecCtx else {
            return 0
        }
        
        var len1: Int32 = 0
        var data_size: Int32 = 0
        
        while true {
            while 0 < audio_pkt_size {
                var ret: Int32 = 0
                repeat {
                    ret = avcodec_send_packet(aCodecCtx, pkt)
                } while ret == AVERROR_CONVERT(EAGAIN)
                if isErr(ret, "send audio packet") {
                    break
                }
                repeat {
                    ret = avcodec_receive_frame(aCodecCtx, frame)
                } while ret == AVERROR_CONVERT(EAGAIN)
                if isErr(ret, "receive audio frame") {
                    break
                }
                len1 = frame.o.pkt_size
                if 0 > len1 {
                    audio_pkt_size = 0
                    break
                }
                if let data = audio_pkt_data {
                    audio_pkt_data = data.advanced(by: Int(len1))
                }
                audio_pkt_size -= len1
                
                data_size = av_samples_get_buffer_size(nil, aCodecCtx.o.channels, frame.o.nb_samples, aCodecCtx.o.sample_fmt, 1)
                SDL_MixAudio(audio_buf, frame.o.data.0, Uint32(data_size), SDL_MIX_MAXVOLUME / 2)
                av_packet_unref(pkt)
                av_frame_unref(frame)
                if 0 >= data_size {
                    continue
                }
                return data_size
            }
            if let _ = pkt?.o.data {
                av_packet_unref(pkt)
            }
            if 1 == quit {
                return -1
            }
            
            if 0 > packet_queue_get(q: &audioq, pkt: &pkt, block: 1) {
                return -1
            }
            
            audio_pkt_data = pkt?.o.data
            audio_pkt_size = pkt?.o.size ?? 0
        }
    }
    
    static var audio_buf = [UInt8](repeating: 0, count: Int(MAX_AUDIO_FRAME_SIZE * 3 / 2))
    static var audio_buf_size: UInt32 = 0
    static var audio_buf_index: UInt32 = 0
    static var audio_callback:SDL_AudioCallback = { (userdata, stream, len) -> Void in
        let aCodecCtx: UnsafeMutablePointer<AVCodecContext>? = userdata?.cast(to: AVCodecContext.self)
        var len1: Int32 = 0
        var audio_size: Int32 = 0
        
        var len: Int32 = len
        var stream = stream
        while 0 < len {
            if audio_buf_index >= audio_buf_size {
                audio_size = audio_decode_frame(aCodecCtx: aCodecCtx, audio_buf: audio_buf.withUnsafeMutableBufferPointer(){$0}.baseAddress, buf_size: Int32(audio_buf_size))
                if 0 > audio_size {
                    audio_buf_size = 1024
                    memset(audio_buf.withUnsafeMutableBufferPointer(){$0}.baseAddress, 0, MemoryLayout<UInt8>.stride * Int(audio_buf_size))
                } else {
                    audio_buf_size = UInt32(audio_size)
                }
                audio_buf_index = 0
            }
            len1 = Int32(audio_buf_size - audio_buf_index)
            if len1 > len {
                len1 = len
            }
            SDL_MixAudio(stream, audio_buf.withUnsafeMutableBufferPointer(){$0}.baseAddress?.advanced(by: Int(audio_buf_index)), UInt32(len1), 32)
            len -= len1
            stream = stream?.advanced(by: Int(len1))
            audio_buf_index += UInt32(len1)
        }
    }
    
    func run() {
        guard let helper = AVHelper(inputPath: paths[0]) else {
            return
        }
        
        guard helper.open() else {
            return
        }
        
        var pFormatCtx = helper.formatContext
        
        let screenSize = UIScreen.main.bounds.size
        
        guard  SDLHelper().sdl_init(UInt32(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) else {
            return
        }
        // SDL has multiple window no use SDL_SetVideoMode for SDL_Surface
        let window = SDL_CreateWindow(String(describing: type(of: self)), SDL_WINDOWPOS_UNDEFINED_MASK | 0, SDL_WINDOWPOS_UNDEFINED_MASK | 0, Int32(UIScreen.main.bounds.width), Int32(UIScreen.main.bounds.height), SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_OPENGL.rawValue | SDL_WINDOW_BORDERLESS.rawValue)
        guard nil != window else {
            print("SDL: couldn't create window")
            return
        }
        
        let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_TARGETTEXTURE.rawValue | SDL_RENDERER_ACCELERATED.rawValue)
        
        let texture = SDL_CreateTexture(renderer, UInt32(SDL_PIXELFORMAT_IYUV), Int32(SDL_TEXTUREACCESS_STREAMING.rawValue), helper.width, helper.height)
        defer {
            SDL_DestroyTexture(texture)
            SDL_DestroyRenderer(renderer)
            SDL_DestroyWindow(window)
        }
        
        var rect: SDL_Rect = SDL_Rect(x: 0, y: 0, w: helper.size.width.cast(), h: helper.size.height.cast())
        var dst_rect = aspectFit(rect: rect, inside: UIScreen.main.bounds)
        
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE)
        
        // AUDIO
        
        let aparam = helper.params(type: AVMEDIA_TYPE_AUDIO)!
        var wanted_spec:SDL_AudioSpec = SDL_AudioSpec()
        wanted_spec.freq = aparam.o.sample_rate
        wanted_spec.channels = aparam.o.channels.cast()
        wanted_spec.format = AUDIO_S16SYS.cast()
        wanted_spec.silence = 0
        wanted_spec.samples = Tutorial3.SDL_AUDIO_BUFFER_SIZE.cast()
        wanted_spec.callback = Tutorial3.audio_callback
        wanted_spec.userdata = helper.codecCtx(at: helper.streamIndex(type: AVMEDIA_TYPE_AUDIO))?.castRaw(from: AVCodecContext.self)
        var spec: SDL_AudioSpec = SDL_AudioSpec()
        
        guard 0 == SDL_OpenAudio(&wanted_spec, &spec) else {
            cPrint(cString: SDL_GetError())
            return
        }
        
        SDL_PauseAudio(0)
        
        defer {
            SDL_PauseAudio(1)
            SDL_CloseAudio()
        }
        
        var event = SDL_Event()
        let audioIndex = helper.streamIndex(type: AVMEDIA_TYPE_AUDIO)
        let videoIndex = helper.streamIndex(type: AVMEDIA_TYPE_VIDEO)
        var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        var frm: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        
        read: while 0 <= av_read_frame(helper.formatContext, pkt) {
            guard let pkt = pkt else {
                break
            }
            let ctx = helper.codecCtx(at: pkt.o.stream_index)
            let st = helper.stream(at: pkt.o.stream_index)
            switch pkt.o.stream_index {
            case videoIndex:
                guard decode_codec(ctx, stream: st, packet: pkt, frame: frm) else {
                    break
                }
                update(frame: frm, texture: texture, renderer: renderer, toRect: dst_rect)
            case audioIndex:
                Tutorial3.packet_queue_put(q: &Tutorial3.audioq, pkt: pkt)
                continue
            default:
                continue
            }
            
            SDL_PollEvent(&event)
            let type = SDL_EventType(rawValue: event.type)
            switch type {
            case SDL_QUIT, SDL_FINGERDOWN:
                Tutorial3.quit = 1
                break read
            default:
                continue
            }
        }
      
    }
    
}

struct  Tutorial4: Tutorial {
    var paths: [String]
    
    static let SDL_AUDIO_BUFFER_SIZE: Int32 = 1024
    static let MAX_AUDIO_FRAME_SIZE: Int32 = 192000
    
    struct PacketQueue {
        var first_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var last_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var nb_packet: Int32 = 0
        var size: Int32 = 0
        var mutex: OpaquePointer = SDL_CreateMutex()
        var cond: OpaquePointer = SDL_CreateCond()
    }
    
    struct VideoPicture {
        /// SDL_Texture
        var texture: OpaquePointer? = nil
        var width: Int32 = 0, height: Int32 = 0
        var allocated: Int32 = 0
    }
    
    struct VideoState {
        var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        var videoStream: Int32 = 0
        var audioStream: Int32 = 0
        var audio_st: UnsafeMutablePointer<AVStream>? = nil
        var audio_ctx: UnsafeMutablePointer<AVCodecContext>? = nil
        var audioq: PacketQueue = PacketQueue()
        var audio_buf: [UInt8] = [UInt8](repeating: 0, count: (MAX_AUDIO_FRAME_SIZE.cast() * 3) / 2)
        var audio_buf_size: UInt32 = 0
        var audio_buf_index: UInt32 = 0
        var audio_pkt: AVPacket = AVPacket()
        var audio_pkt_data: UnsafeMutablePointer<UInt8>? = nil
        var audio_pkt_size: Int32 = 0
        var audio_frame: AVFrame = AVFrame()
        
        var video_st: UnsafeMutablePointer<AVStream>? = nil
        var video_ctx: UnsafeMutablePointer<AVCodecContext>? = nil
        var videoq: PacketQueue = PacketQueue()
        
        var pictq:[VideoPicture] = [VideoPicture](repeating: VideoPicture(), count: Tutorial4.VIDEO_PICTURE_QUEUE_SIZE)
        var pictq_size: Int32 = 0
        var pictq_rindex: Int32 = 0
        var pictq_windex: Int32 = 0
        
        var pictq_mutex: OpaquePointer = SDL_CreateMutex()
        var pictq_cond: OpaquePointer = SDL_CreateCond()
        
        var parse_tid: OpaquePointer? = nil
        var video_tid: OpaquePointer? = nil
        
        var filename: UnsafePointer<CChar>? = nil
        var quit: Int32 = 0
    }
    
    static var global_video_state: VideoState = VideoState()
    
    static func packet_queue_put(q: UnsafeMutablePointer<PacketQueue>?, pkt: UnsafeMutablePointer<AVPacket>?) -> Int32 {
        var q = q
        if nil == pkt {
            if isErr(av_packet_ref(pkt, av_packet_alloc()), "packet queue put ref packet") {
                return -1
            }
        }
        
        let pkt1: UnsafeMutablePointer<AVPacketList> = av_malloc(MemoryLayout<AVPacketList>.stride).bindMemory(to: AVPacketList.self, capacity: MemoryLayout<AVPacketList>.stride)
        
        if let pkt = pkt {
            pkt1.pointee.pkt = pkt.pointee
        }
        pkt1.pointee.next = nil
        SDL_LockMutex(q?.pointee.mutex)
        
        if nil == q?.pointee.last_pkt {
            q?.pointee.first_pkt = pkt1
        } else {
            q?.pointee.last_pkt?.pointee.next = pkt1
        }
        
        q?.pointee.last_pkt = pkt1
        q?.pointee.nb_packet += 1
        q?.o.size += pkt1.o.pkt.size
        SDL_CondSignal(q?.o.cond)
        SDL_UnlockMutex(q?.o.mutex)
        return 0
    }
    
    static func packet_queue_get(q: UnsafeMutablePointer<PacketQueue>?, pkt: inout UnsafeMutablePointer<AVPacket>?, block: Int32) -> Int32 {
        guard let queue = q else {
            return 0
        }
        var q = queue
        var pkt1: UnsafeMutablePointer<AVPacketList>? = nil
        var ret: Int32 = 0
        SDL_LockMutex(q.o.mutex)
        while true {
            if 1 == global_video_state.quit {
                ret = -1
                break
            }
            
            pkt1 = q.o.first_pkt
            if let pkt1 = pkt1 {
                q.o.first_pkt = pkt1.o.next
                if nil == q.o.first_pkt {
                    q.o.last_pkt = nil
                }
                q.o.nb_packet -= 1
                q.o.size -= pkt1.o.pkt.size
                pkt?.o = pkt1.o.pkt
                av_free(pkt1.castRaw(from: AVPacketList.self))
                ret = 1
                break
            } else if 0 == block {
                ret = 0
                break
            } else {
                SDL_CondWait(q.o.cond, q.o.mutex)
            }
        }
        SDL_UnlockMutex(q.o.mutex)
        return ret
    }
    
    static func audio_decode_frame(vs: UnsafeMutablePointer<VideoState>) -> Int32 {
        var vs = vs
        guard let aCodecCtx = vs.o.audio_ctx, let st = vs.o.audio_st else {
            return 0
        }
        
        var len1: Int32 = 0
        var data_size: Int32 = 0
        
        var pkt: UnsafeMutablePointer<AVPacket>? = <<&vs.o.audio_pkt
        var frm = <<&vs.o.audio_frame
        while true {
            while vs.o.audio_pkt_size > 0 {
                guard decode_codec(aCodecCtx, stream: vs.o.audio_st, packet: <<&vs.o.audio_pkt, frame: <<&vs.o.audio_frame) else {
                    break
                }
                
                len1 = vs.o.audio_pkt_size
                if 0 > len1 {
                    vs.o.audio_pkt_size = 0
                }
                
                data_size = av_samples_get_buffer_size(nil, st.o.codecpar.o.channels, frm.o.nb_samples, AVSampleFormat(rawValue: st.o.codecpar.o.format), 1)
                let pointer = vs.o.audio_buf.pointer
                SDL_MixAudio(pointer?.cast(), frm.o.data.0, data_size.cast(), 32)
                vs.o.audio_pkt_data = vs.o.audio_pkt_data?.advanced(by: Int(len1))
                vs.o.audio_pkt_size -= len1
                if 0 >= data_size {
                    continue
                }
                return data_size
            }
            if nil != pkt?.o.data {
                av_packet_unref(pkt)
            }
            if 1 == vs.o.quit {
                return -1
            }
            
            if 0 > Tutorial4.packet_queue_get(q: <<&vs.o.audioq, pkt: &pkt, block: 1) {
                return -1
            }
            vs.o.audio_pkt_data = pkt?.o.data
            vs.o.audio_pkt_size -= pkt?.o.size ?? 0
        }
        
        return 0
    }
    
    static let VIDEO_PICTURE_QUEUE_SIZE = 1
    
    func schedule_refresh(vs: UnsafeMutablePointer<VideoState>, refresh_rate: Int32) {
        
    }
    
    var decode_thread: SDL_ThreadFunction = { (user_ctx) -> Int32 in
        return 0
    }
    
    var video_thread: SDL_ThreadFunction = { (user_ctx) -> Int32 in
        return 0
    }
    
    static var audio_callback:SDL_AudioCallback = { (userdata, stream, len) -> Void in
        
    }
    
    func stream_component_open(vs: UnsafeMutablePointer<VideoState>, stream_index: Int32) -> Int32 {
        var vs: UnsafeMutablePointer<VideoState> = vs
        guard let pFormatCtx = vs.o.pFormatCtx else {
            return -1
        }
        var codec: UnsafeMutablePointer<AVCodec>? = nil
        var wanted_spec: SDL_AudioSpec = SDL_AudioSpec()
        var spec: SDL_AudioSpec = SDL_AudioSpec()
        
        if stream_index < 0 || stream_index >= pFormatCtx.o.nb_streams.cast() {
            return -1
        }
        
        guard let codecpar = pFormatCtx.o.streams[stream_index.cast()]?.o.codecpar else {
            return -1
        }
        
        codec = avcodec_find_encoder(codecpar.o.codec_id)
        if nil == codec {
            print("Unsupported codec \(String(cString: avcodec_get_name(codecpar.o.codec_id)))")
            return -1
        }
        
        guard let codecCtx: UnsafeMutablePointer<AVCodecContext> = avcodec_alloc_context3(codec) else {
            return -1
        }
        if isErr(avcodec_parameters_to_context(codecCtx, codecpar), "param to context") {
            return -1
        }
        
        
        
        if codecCtx.o.codec_type == AVMEDIA_TYPE_AUDIO {
            wanted_spec.freq = codecCtx.o.sample_rate
            wanted_spec.format = AUDIO_S16SYS.cast()
            wanted_spec.channels = codecCtx.o.channels.cast()
            wanted_spec.silence = 0
            wanted_spec.callback = Tutorial4.audio_callback
            wanted_spec.samples = Tutorial4.SDL_AUDIO_BUFFER_SIZE.cast()
            wanted_spec.userdata = vs.castRaw(from: VideoState.self)
            
            if 0 > SDL_OpenAudio(&wanted_spec, &spec) {
                cPrint(cString: SDL_GetError())
                return -1
            }
        }
        
        if isErr(avcodec_open2(codecCtx, codec, nil), "open codec") {
            print("Unsupported codec \(String(cString: avcodec_get_name(codecpar.o.codec_id)))")
            return -1
        }
        
        switch  codecpar.o.codec_type {
        case AVMEDIA_TYPE_AUDIO:
            vs.o.audioStream = stream_index
            vs.o.audio_st = pFormatCtx.o.streams[stream_index.cast()]
            vs.o.audio_ctx = codecCtx
            vs.o.audio_buf_size = 0
            vs.o.audio_buf_index = 0
            memset(&vs.o.audio_pkt, 0, MemoryLayout<AVPacket>.stride)
            SDL_PauseAudio(0)
        case AVMEDIA_TYPE_VIDEO:
            vs.o.videoStream = stream_index
            vs.o.video_st = pFormatCtx.o.streams[stream_index.cast()]
            vs.o.video_ctx = codecCtx
            
            vs.o.video_tid = SDL_CreateThread(video_thread, "video thread", vs.castRaw(from: VideoState.self))
        default:
            break
        }
        
        return 0
    }
    
    init(paths: [String]) {
        self.paths = paths
    }
    
    func run() {
        guard let helper = AVHelper(inputPath: paths[0]) else {
            return
        }
        
        guard helper.open() else {
            return
        }
        
        guard  SDLHelper().sdl_init(UInt32(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) else {
            return
        }
        
        var event: SDL_Event = SDL_Event()
        var vs: VideoState = VideoState()
        
        vs.filename = paths[0].cString(using: .utf8)?.withUnsafeBufferPointer(){$0}.baseAddress
        
        schedule_refresh(vs: &vs, refresh_rate: 40)
        
        guard let parse_tid = SDL_CreateThread(decode_thread, "video_thread", withUnsafeMutablePointer(to: &vs){$0}.castRaw(from: VideoState.self)) else {
            cPrint(cString: SDL_GetError())
            return
        }
        vs.parse_tid = parse_tid
        
    }
    
}

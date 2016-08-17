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

enum TutorialIndex: Int {
    case tutorial1 = 1
    case tutorial2, tutorial3
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
        
        pCodecCtx = pFormatCtx?.pointee.streams.advanced(by: Int(videoStream)).pointee?.pointee.codec
        
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
        
        numBytes = avpicture_get_size(AV_PIX_FMT_RGB24, (pCodecCtx?.pointee.width)!, (pCodecCtx?.pointee.height)!)
        buffer = av_malloc(Int(numBytes) * MemoryLayout<UInt8>.stride).assumingMemoryBound(to: UInt8.self)
        
        sws_ctx = sws_getContext((pCodecCtx?.pointee.width)!, (pCodecCtx?.pointee.height)!, (pCodecCtx?.pointee.pix_fmt)!, (pCodecCtx?.pointee.width)!, (pCodecCtx?.pointee.height)!, AV_PIX_FMT_RGB24, SWS_BILINEAR, nil, nil, nil)
        
        avpicture_fill(pFrameRGB?.withMemoryRebound(to: AVPicture.self, capacity: MemoryLayout<AVPicture>.stride){$0}, buffer, AV_PIX_FMT_RGB24, pCodecCtx?.pointee.width ?? 0, pCodecCtx?.pointee.height ?? 0)
        
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
                if isErr(avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet), "avcodec_decode_video2") {
                    return
                }
                if 0 < frameFinished {
                    sws_scale(sws_ctx,
                              pFrame?.pointee.dataPtr().cast(),
                              pFrame?.pointee.linesizePtr(),
                              0,
                              pCodecCtx!.pointee.height,
                              pFrameRGB?.pointee.dataPtr().cast(),
                              pFrameRGB?.pointee.linesizePtr())
                    frameFinished = 0
                }
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
        
        var rect: SDL_Rect = CGRect(origin: CGPoint(), size: helper.size).rect
        var dst_rect = UIScreen.main.bounds.aspectFit(aspectRatio: rect.rect.size).rect
        
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE)
        var event = SDL_Event()
        
        // half scale, yuv 420 pixel format, rotate
        var descriptor = AVFilterDescriptor()
        descriptor.add(pixelFormat: AV_PIX_FMT_YUV420P)
        // smartblur filter doesn't exist
        //        descriptor.set(smartblur:AVFilterDescriptor.AVSmartblur(lr: 5, lt: 30, cr: 5, ct: 30))
        guard helper.setupVideoFilter(filterDesc: descriptor.description) else {
            print("setup filter failed")
            return
        }
        
        helper.decode(frameHandle: { (type, frame) -> AVHelper.HandleResult in
            guard let frame = frame, type == AVMEDIA_TYPE_VIDEO else {
                return .ignored
            }
            if frame.pointee.linesize.2 > 0 {
                SDL_UpdateYUVTexture(texture, &rect, frame.pointee.data.0, frame.pointee.linesize.0, frame.pointee.data.1, frame.pointee.linesize.1, frame.pointee.data.2, frame.pointee.linesize.2)
            } else {
                SDL_UpdateTexture(texture, &rect, frame.pointee.data.0, frame.pointee.linesize.0)
            }
            SDL_RenderClear(renderer)
            SDL_RenderCopy(renderer, texture, &rect, &dst_rect)
            SDL_RenderPresent(renderer)
            return .succeed
        }) { () -> Bool in
            SDL_PollEvent(&event)
            if event.type == SDL_QUIT.rawValue {
                return false
            } else if event.type == SDL_FINGERDOWN.rawValue {
                return false
            }
            return true
        }
    }
}

struct  Tutorial3: Tutorial {
    var paths: [String]
    
    func run() {
        guard let helper = AVHelper(inputPath: paths[0]) else {
            return
        }
        guard helper.open() else {
            return
        }
        
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
        
        var rect: SDL_Rect = CGRect(origin: CGPoint(), size: helper.size).rect
        var dst_rect = UIScreen.main.bounds.aspectFit(aspectRatio: rect.rect.size).rect
        
        SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE)
        
        var audio_spec = helper.SDLAudioSpec(callback: { (userData, stream, length) in
            print("receive audio callback")
            
            let helper_ptr: UnsafeMutablePointer<AVHelper> = userData!.cast(to: AVHelper.self)
            let helper = helper_ptr.pointee
            
            var audio_buf: [UInt8] = [UInt8](repeating: 0, count: 192000 * 3 / 2)
            var audio_buf_size: UInt32 = 0
            var audio_buf_index: UInt32 = 0
            
            var aCodecCtx: UnsafeMutablePointer<AVCodecContext> = userData!.cast(to: AVCodecContext.self)
            var len1: Int32 = 0
            var audio_size: Int32 = 0
            
            var len = length
            while 0 < len {
                if audio_buf_index >= audio_buf_size {
                    audio_size = helper.audio_decode_frame(audioCodecContext: aCodecCtx, audio_buf: &audio_buf, buf_size: Int32(MemoryLayout<UInt8>.size * audio_buf.count))
                }
            }
        })
        
        if nil == audio_spec {
            return
        }
        
        var spec = SDL_AudioSpec()
        
        if SDL_OpenAudio(&audio_spec!, &spec).SDLError {
            return
        }
        
        defer {
            SDL_CloseAudio()
        }
        
        var queue = PacketQueue()
        var event = SDL_Event()
        
        helper.decode(
            frameHandle: { (type, frame) -> AVHelper.HandleResult in
                guard let frame = frame, type == AVMEDIA_TYPE_VIDEO else {
                    return .ignored
                }
                frame.pointee.update(texture: texture, renderer: renderer, toRect: dst_rect)
                return .succeed
            },
            packetHandle: { (type, packet) -> AVHelper.HandleResult in
                guard let pkt = packet, type == AVMEDIA_TYPE_AUDIO else {
                    return .ignored
                }
                queue.put(packet: pkt.cast()!)
                return .ignored
            },
            completion: { () -> Bool in
                SDL_PollEvent(&event)
                switch SDL_EventType(event.type) {
                case SDL_QUIT:
                    queue.quit = true
                    return false
                case SDL_FINGERDOWN:
                    return false
                default:
                    return true
                }
        })
    }
}

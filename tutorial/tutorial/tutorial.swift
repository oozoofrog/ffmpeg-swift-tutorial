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

enum TutorialIndex: Int {
    case tutorial1 = 1
    case tutorial2
    
    func runTutorial(paths:[String]) {
        switch self {
        case .tutorial1:
            Tutorial1(paths: paths).run()
        case .tutorial2:
            Tutorial2(paths: paths).run()
        }
    }
    
    static let all: [TutorialIndex] = (1...TutorialIndex.tutorial2.rawValue).flatMap(){TutorialIndex(rawValue: $0)}
}

protocol Tutorial {
    var docPath: String { get }
    var paths: [String] { get }
    var writePath: String { get }
    func run()
}

extension Tutorial {
    var docPath: String {
        return NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
    }
    var writePath: String {
        return docPath + "/exports/\(String(self.dynamicType))"
    }
}

/**
 *  converted from tutorial1.c
 */
struct Tutorial1: Tutorial {
    let paths: [String]
    
    func Saveframe(pFrame: UnsafeMutablePointer<AVFrame>, width: Int32, height: Int32, iFrame: Int32) {
        let writePath = self.writePath + "/frame\(iFrame).ppm"
        
        do {
            
            
            if false == NSFileManager.defaultManager().fileExistsAtPath(writePath) {
                try NSFileManager.defaultManager().createDirectoryAtPath(self.writePath, withIntermediateDirectories: true, attributes: nil)
                NSFileManager.defaultManager().createFileAtPath(writePath, contents: nil, attributes: nil)
            }
            
            let writeHandle = try NSFileHandle(forWritingToURL: NSURL(fileURLWithPath: writePath))
            
            defer {
                writeHandle.synchronizeFile()
                writeHandle.closeFile()
            }
            guard let header = "P6\n\(width) \(height)\n255\n".dataUsingEncoding(NSASCIIStringEncoding) else {
                return
            }
            writeHandle.writeData(header)
            
            for y in 0..<height {
                let bytes = pFrame.memory.data.0.advancedBy(Int(y) * Int(pFrame.memory.linesize.0))
                writeHandle.writeData(NSData(bytes: bytes, length: Int(pFrame.memory.linesize.0)))
            }
            
        } catch let err as NSError {
            assertionFailure("\nwrite to -> \(writePath)\n" + err.localizedDescription)
        }
    }
    
    func run() {
        var pFormatCtx: UnsafeMutablePointer<AVFormatContext> = avformat_alloc_context()
        var i: Int32 = 0, videoStream: Int32 = 0
        var pCodecCtx: UnsafeMutablePointer<AVCodecContext> = nil
        var pCodec: UnsafeMutablePointer<AVCodec> = nil
        var pFrame: UnsafeMutablePointer<AVFrame> = nil
        var pFrameRGB: UnsafeMutablePointer<AVFrame> = nil
        var packet = AVPacket()
        var frameFinished: Int32 = 0
        var numBytes: Int32 = 0
        
        var optionsDict: UnsafeMutablePointer<COpaquePointer> = nil
        var buffer: UnsafeMutablePointer<UInt8> = nil
        
        //        AVDictionaryEntry
        //        var optionsDict: UnsafeMutablePointer<AVDictionary> = nil
        var sws_ctx: COpaquePointer = nil
        
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
        
        pCodecCtx = pFormatCtx.memory.streams.advancedBy(Int(videoStream)).memory.memory.codec
        
        defer {
            print("close codec context")
            avcodec_close(pCodecCtx)
            
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
        
        numBytes = avpicture_get_size(AV_PIX_FMT_RGB24, pCodecCtx.memory.width, pCodecCtx.memory.height)
        buffer = UnsafeMutablePointer<UInt8>(av_malloc(Int(numBytes) * sizeof(UInt8)))
        
        sws_ctx = sws_getContext(pCodecCtx.memory.width, pCodecCtx.memory.height, pCodecCtx.memory.pix_fmt, pCodecCtx.memory.width, pCodecCtx.memory.height, AV_PIX_FMT_RGB24, SWS_BILINEAR, nil, nil, nil)
        
        avpicture_fill(pFrameRGB.cast(), buffer, AV_PIX_FMT_RGB24, pCodecCtx.memory.width, pCodecCtx.memory.height)
        
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
                              pFrame.memory.dataPtr().cast(),
                              pFrame.memory.linesizePtr(),
                              0,
                              pCodecCtx.memory.height,
                              pFrameRGB.memory.dataPtr(),
                              pFrameRGB.memory.linesizePtr())
                    frameFinished = 0
                }
                i += 1
                if i <= 5 {
                    Saveframe(pFrameRGB, width: pCodecCtx.memory.width, height: pCodecCtx.memory.height, iFrame: i)
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
    let paths: [String]
    
    func run() {
        var pFormatCtx: UnsafeMutablePointer<AVFormatContext> = avformat_alloc_context()
        var i: Int32 = 0, videoStream: Int32 = 0
        var pCodecCtx: UnsafeMutablePointer<AVCodecContext> = nil
        var pCodec: UnsafeMutablePointer<AVCodec> = nil
        var pFrame: UnsafeMutablePointer<AVFrame> = nil
        var pFrameRGB: UnsafeMutablePointer<AVFrame> = nil
        var packet = AVPacket()
        var frameFinished: Int32 = 0
        var numBytes: Int32 = 0
        
        var optionsDict: UnsafeMutablePointer<COpaquePointer> = nil
        var buffer: UnsafeMutablePointer<UInt8> = nil
        
        //        AVDictionaryEntry
        //        var optionsDict: UnsafeMutablePointer<AVDictionary> = nil
        var sws_ctx: COpaquePointer = nil
        
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
        
        pCodecCtx = pFormatCtx.memory.streams.advancedBy(Int(videoStream)).memory.memory.codec
        
        defer {
            print("close codec context")
            avcodec_close(pCodecCtx)
            
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
        
        numBytes = avpicture_get_size(AV_PIX_FMT_RGB24, pCodecCtx.memory.width, pCodecCtx.memory.height)
        buffer = UnsafeMutablePointer<UInt8>(av_malloc(Int(numBytes) * sizeof(UInt8)))
        
        sws_ctx = sws_getContext(pCodecCtx.memory.width, pCodecCtx.memory.height, pCodecCtx.memory.pix_fmt, pCodecCtx.memory.width, pCodecCtx.memory.height, AV_PIX_FMT_RGB24, SWS_BILINEAR, nil, nil, nil)
        
        avpicture_fill(pFrameRGB.cast(), buffer, AV_PIX_FMT_RGB24, pCodecCtx.memory.width, pCodecCtx.memory.height)
        
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
        
        guard  SDLHelper().SDL_init(UInt32(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) else {
            return
        }
        // SDL has multiple window no use SDL_SetVideoMode for SDL_Surface
        let window = SDL_CreateWindow(String(self.dynamicType), SDL_WINDOWPOS_UNDEFINED_MASK | 0, SDL_WINDOWPOS_UNDEFINED_MASK | 0, Int32(UIScreen.mainScreen().bounds.width), Int32(UIScreen.mainScreen().bounds.height), SDL_WINDOW_FULLSCREEN.rawValue | SDL_WINDOW_OPENGL.rawValue)
        guard nil != window else {
            print("SDL: couldn't create window")
            return
        }
        
        let renderer = SDL_CreateRenderer(window, -1, 0)
        
        let texture = SDL_CreateTexture(renderer, UInt32(SDL_PIXELFORMAT_IYUV), Int32(SDL_TEXTUREACCESS_STREAMING.rawValue), pCodecCtx.memory.width, pCodecCtx.memory.height)
        
        
        while 0 <= av_read_frame(pFormatCtx, &packet) {
            if packet.stream_index == videoStream {
                if isErr(avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet), "avcodec_decode_video2") {
                    return
                }
                if 0 < frameFinished {
                    
              
                }
            }
            av_packet_unref(&packet)
        }
    }
}

protocol AVData {
    var data: (UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt8>) {set get}
    
    var linesize: (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) {set get}
    
}

protocol AVByteable {
    mutating func dataPtr() -> UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>
    mutating func linesizePtr() -> UnsafeMutablePointer<Int32>
}

extension AVByteable where Self: AVData {
    mutating func dataPtr() -> UnsafeMutablePointer<UnsafeMutablePointer<UInt8>> {
        return withUnsafeMutablePointer(&data, { (ptr) -> UnsafeMutablePointer<UnsafeMutablePointer<UInt8>> in
            return UnsafeMutablePointer<UnsafeMutablePointer<UInt8>>(ptr)
        })
    }
    mutating func linesizePtr() -> UnsafeMutablePointer<Int32> {
        return withUnsafeMutablePointer(&linesize) {return UnsafeMutablePointer<Int32>($0)}
    }
}

extension AVFrame: AVData, AVByteable {}
extension AVPicture: AVData, AVByteable {}
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
    var path: String {
        return self.paths[0]
    }
    var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }
    var screen: SDL_Rect {
        return SDL_Rect(x: 0, y: 0, w: self.screenSize.width.cast(), h: self.screenSize.height.cast())
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
        
        var data = pFrameRGB?.p.data
        let rgbDataPtr = withUnsafeMutablePointer(to: &data){$0}
        var linesize = pFrameRGB?.p.linesize
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
                var data = pFrame?.p.data
                var linesize = pFrame?.p.linesize
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

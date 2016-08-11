//
//  AVFormatHelper.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 11..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import ffmpeg

/**
 *  
 */
protocol AVHelperProtocol {
    var inputPath: String {get}
    var outputPath: String? {set get}
    
    var formatContext: UnsafeMutablePointer<AVFormatContext>? { set get }
    func open() -> Bool
    func close()
}

extension AVHelperProtocol where Self: AVHelper {
    func open() -> Bool {
        if isErr(avformat_open_input(&formatContext, inputPath, nil, nil), "avformat_open_input") {
            return false
        }
        if isErr(avformat_find_stream_info(formatContext, nil), "find stream info") {
            return false
        }
        return true
    }
    
    func close() {
        avformat_close_input(&formatContext)
    }
}

protocol AVHelperCodecProtocol {
    var codecs: [Int32 : UnsafeMutablePointer<AVCodec>?] { set get }
    func codec(forMediaType type: AVMediaType) -> UnsafePointer<AVCodec>?
    func codecContext(forMediaType type: AVMediaType) -> UnsafeMutablePointer<AVCodecContext>?
    func streamIndex(forMediaType type: AVMediaType) -> Int32
    func stream(forMediaType type: AVMediaType) -> UnsafePointer<AVStream>?
}

extension AVHelperCodecProtocol where Self:AVHelper {
    func codec(forMediaType type: AVMediaType) -> UnsafePointer<AVCodec>? {
        let index = streamIndex(forMediaType: type)
        let stream = formatContext?.pointee.streams[Int(index)]
        guard let codec = self.codecs[type.rawValue] else {
            return nil
        }
        if 0 == avcodec_is_open(stream?.pointee.codec) {
            if isErr(avcodec_open2(stream?.pointee.codec, codec, nil), "codec open \(type)") {
                return nil
            }
        }
        return codec?.cast()
    }
    
    func openCodec(forMediaType type: AVMediaType) -> Bool {
        return nil != codec(forMediaType: type)
    }
    
    func codecContext(forMediaType type: AVMediaType) -> UnsafeMutablePointer<AVCodecContext>? {
        guard openCodec(forMediaType: type) else {
            return nil
        }
        return formatContext?.pointee.streams[Int(streamIndex(forMediaType: type))]?.pointee.codec
    }
    
    func stream(forMediaType type: AVMediaType) -> UnsafePointer<AVStream>? {
        return formatContext?.pointee.streams[Int(streamIndex(forMediaType: type))]?.cast()
    }
    
    func streamIndex(forMediaType type: AVMediaType) -> Int32 {
        var codec = self.codecs[type.rawValue] ?? nil
        let index = av_find_best_stream(formatContext, type, -1, -1, &codec, 0)
        self.codecs[type.rawValue] = codec
        return index
    }
}

//protocol AVFilterHelperProtocol {
//    var buffersrc: UnsafeMutablePointer<AVFilter>? {set get}
//    var buffersink: UnsafeMutablePointer<AVFilter>? {set get}
//    var inputs: UnsafeMutablePointer<AVFilterInOut>? {set get}
//    var outputs: UnsafeMutablePointer<AVFilterInOut>? {set get}
//    var buffersrc_ctx: UnsafeMutablePointer<AVFilterContext>? {set get}
//    var buffersink_ctx: UnsafeMutablePointer<AVFilterContext>? {set get}
//    
//    var filter_graph: UnsafeMutablePointer<AVFilterGraph>? {set get}
////
//    var filter_frame: UnsafeMutablePointer<AVFrame>? {set get}
//    
//    func setupFilter(_ filterDescription: String) -> Bool
//}
//
//extension AVFilterHelperProtocol where Self:AVHelper, Self: AVHelperProtocol, Self: AVHelperCodecProtocol {
//    func setupFilter(_ filterDescription: String) -> Bool {
//        buffersrc = avfilter_get_by_name("buffer")
//        buffersink = avfilter_get_by_name("buffersink")
//        
//        inputs = avfilter_inout_alloc()
//        outputs = avfilter_inout_alloc()
//        
//        filter_graph = avfilter_graph_alloc()
//        
//        defer {
//            avfilter_inout_free(&inputs)
//            avfilter_inout_free(&outputs)
//        }
//        
//        guard let time_base = self.time_base(forMediaType: AVMEDIA_TYPE_VIDEO) else {
//            return false
//        }
//        guard let pixel_aspect = self.pixel_aspect else {
//            return false
//        }
//        guard let pix_fmt = self.pix_fmt else {
//            return false
//        }
//        let args = "video_size=\(width)x\(height):pix_fmt=\(pix_fmt.rawValue):time_base=\(time_base.num)/\(time_base.den):pixel_aspect=\(pixel_aspect.num)/\(pixel_aspect.den)"
//        if isErr(avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in", args, nil, filter_graph), "create in filter") {
//            return false
//        }
//        
//        if isErr(avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out", nil, nil, filter_graph), "create out filter") {
//            return false
//        }
//        
//        outputs?.pointee.name = av_strdup("in")
//        outputs?.pointee.filter_ctx = buffersrc_ctx
//        outputs?.pointee.pad_idx = 0
//        outputs?.pointee.next = nil
//        
//        inputs?.pointee.name = av_strdup("out")
//        inputs?.pointee.filter_ctx = buffersink_ctx
//        inputs?.pointee.pad_idx = 0
//        inputs?.pointee.next = nil
//        
//        if isErr(avfilter_graph_parse_ptr(filter_graph, filterDescription, &inputs, &outputs, nil), "parse graph filter") {
//            return false
//        }
//        
//        if isErr(avfilter_graph_config(filter_graph, nil), "graph config") {
//            return false
//        }
//        
//        filter_frame = av_frame_alloc()
//        
//        return true
//    }
//}

class AVHelper: AVHelperProtocol, AVHelperCodecProtocol {
    let inputPath: String
    var outputPath: String?
    
    var formatContext: UnsafeMutablePointer<AVFormatContext>?
    var codecs: [Int32 : UnsafeMutablePointer<AVCodec>?] = [:]
    
    var filter: AVFilterHelper?
    
    var width: Int32 {
        return self.codecContext(forMediaType: AVMEDIA_TYPE_VIDEO)?.pointee.width ?? 0
    }
    var height: Int32 {
        return self.codecContext(forMediaType: AVMEDIA_TYPE_VIDEO)?.pointee.height ?? 0
    }
    var pix_fmt: AVPixelFormat? {
        return self.codecContext(forMediaType: AVMEDIA_TYPE_VIDEO)?.pointee.pix_fmt
    }
    
    var pixel_aspect: AVRational? {
        return self.codecContext(forMediaType: AVMEDIA_TYPE_VIDEO)?.pointee.sample_aspect_ratio
    }
    
    func time_base(forMediaType type: AVMediaType) -> AVRational? {
        return self.stream(forMediaType: type)?.pointee.time_base
    }
    
    init?(inputPath path: String) {
        self.inputPath = path
        self.outputPath = nil
        formatContext = avformat_alloc_context()
    }
    
    func setupFilter(filterDesc: String) -> Bool {
        self.filter = AVFilterHelper();
        return filter?.setup(formatContext, videoStream: stream(forMediaType: AVMEDIA_TYPE_VIDEO)?.mutable()!, filterDescription: filterDesc) ?? false
    }
    /**
     
     - parameter decodeHandle, completion: return false to stop decoding
     */
    func decode(_ decodeHandle:(type: AVMediaType, frame: UnsafePointer<AVFrame>) -> Bool, completion:() -> Bool) {
        var frame = av_frame_alloc()
        var packet = av_packet_alloc()
        defer {
            av_frame_free(&frame)
            av_packet_free(&packet)
        }
        
        let video_codec_ctx = codecContext(forMediaType: AVMEDIA_TYPE_VIDEO)
        let video_stream_index = streamIndex(forMediaType: AVMEDIA_TYPE_VIDEO)
        var read_frame_finished: Int32 = 0
        while 0 == av_read_frame(formatContext, packet) {
            if packet?.pointee.stream_index == video_stream_index {
                if isErr(avcodec_decode_video2(video_codec_ctx, frame, &read_frame_finished, packet!.cast()), "decode video") {
                    return
                }
                if 0 < read_frame_finished {
                    defer {
                        av_frame_unref(frame)
                    }
                    guard let filter = filter else {
                        guard decodeHandle(type: AVMEDIA_TYPE_VIDEO, frame: frame!) else {
                            break
                        }
                        continue
                    }
                    if filter.applyFilter(frame) {
                        defer {
                            av_frame_unref(filter.filterFrame)
                        }
                        guard decodeHandle(type: AVMEDIA_TYPE_VIDEO, frame: filter.filterFrame) else {
                            break
                        }
                    } else {
                        break
                    }
                }
            }
            guard completion() else {
                break
            }
            av_packet_unref(packet)
        }
    }
    
    deinit {
        close()
    }
}


protocol AVData {
    var data: (UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt8>?) {set get}
    
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

//
//  AVFormatHelper.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 11..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import ffmpeg
import CoreVideo

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


protocol AVSizeProtocol {
    var width: Int32 {
        get
    }
    var height: Int32 {
        get
    }
    var size: CGSize { get }
}

extension AVSizeProtocol {
    var size: CGSize {
        return CGSize(width: Int(width), height: Int(height))
    }
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

protocol AVCodecParametersGetter {
    func params(at: Int32, type: AVMediaType?) -> UnsafeMutablePointer<AVCodecParameters>?
    func params(type: AVMediaType) -> UnsafeMutablePointer<AVCodecParameters>?
}

extension AVCodecParametersGetter where Self: AVHelper {
    func params(type: AVMediaType) -> UnsafeMutablePointer<AVCodecParameters>? {
        let index = av_find_best_stream(formatContext, type, -1, -1, nil, 0)
        return params(at: index, type: type)
    }
    func params(at: Int32, type: AVMediaType? = nil) -> UnsafeMutablePointer<AVCodecParameters>? {
        
        let stream = formatContext?.pointee.streams[Int(at)]
        
        let param = stream?.pointee.codecpar
        guard let type = type else {
            return param
        }
        guard param?.pointee.codec_type == type else {
            return nil
        }
        return param
    }
}

protocol AVStreamGetter {
    func streamIndexes(type: AVMediaType) -> [Int32]
    func streamIndex(type: AVMediaType) -> Int32
    func stream(at: Int32) -> UnsafeMutablePointer<AVStream>?
    func stream(type: AVMediaType) -> UnsafeMutablePointer<AVStream>?
    func type(at: Int32) -> AVMediaType?
}

extension AVStreamGetter where Self: AVHelper, Self: AVCodecParametersGetter {
    func streamIndexes(type: AVMediaType) -> [Int32] {
        var indexes: [Int32] = []
        for i in 0..<(formatContext?.pointee.nb_streams ?? 0) {
            guard let _ = params(at: Int32(i), type: type) else {
                continue
            }
            indexes.append(Int32(i))
        }
        return indexes
    }
    func streamIndex(type: AVMediaType) -> Int32 {
        let index = av_find_best_stream(formatContext, type, -1, -1, nil, 0)
        return index
    }
    func stream(at: Int32) -> UnsafeMutablePointer<AVStream>? {
        return formatContext?.pointee.streams[Int(at)]
    }
    func stream(type: AVMediaType) -> UnsafeMutablePointer<AVStream>? {
        return self.stream(at: streamIndex(type: type))
    }
    func type(at: Int32) -> AVMediaType? {
        return self.params(at: at)?.pointee.codec_type
    }
}

class AVHelper: AVHelperProtocol, AVCodecParametersGetter, AVStreamGetter, AVSizeProtocol {
    let inputPath: String
    var outputPath: String?
    
    var formatContext: UnsafeMutablePointer<AVFormatContext>?
    
    var videoFilter: AVFilterHelper?
    
    var width: Int32 {
        return params(type: AVMEDIA_TYPE_VIDEO)?.pointee.width ?? 0
    }
    var height: Int32 {
        return params(type: AVMEDIA_TYPE_VIDEO)?.pointee.height ?? 0
    }
    var pix_fmt: AVPixelFormat? {
        guard let param: UnsafeMutablePointer<AVCodecParameters> = params(type: AVMEDIA_TYPE_VIDEO) else {
            return AV_PIX_FMT_NONE
        }
        return AVPixelFormat(rawValue: param.pointee.format)
    }
    
    var pixel_aspect: AVRational? {
        return params(type: AVMEDIA_TYPE_VIDEO)?.pointee.sample_aspect_ratio
    }
    
    func time_base(forMediaType type: AVMediaType) -> AVRational? {
        let index = streamIndex(type: type)
        let stream: UnsafeMutablePointer<AVStream>? = self.stream(at: index)
        return stream?.pointee.time_base
    }
    
    init?(inputPath path: String) {
        self.inputPath = path
        self.outputPath = nil
        formatContext = avformat_alloc_context()
    }
    
    func setupVideoFilter(filterDesc: String) -> Bool {
        self.videoFilter = AVFilterHelper();
        return videoFilter?.setup(formatContext, videoStream: stream(type: AVMEDIA_TYPE_VIDEO)?.mutable()!, filterDescription: filterDesc) ?? false
    }
    
    typealias FrameHandle = (type:AVMediaType, frame: UnsafePointer<AVFrame>?) -> HandleResult
    typealias PacketHandle = (type:AVMediaType, packet: UnsafePointer<AVPacket>?) -> HandleResult
    
    enum HandleResult {
        case succeed
        case ignored
        case cancelled(reason: Int32)
    }
    
    var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
    var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
    
    func decode(frameHandle: FrameHandle? = nil,
                packetHandle: PacketHandle? = nil,
                completion: () -> Bool) {
        defer {
            av_frame_free(&frame)
            av_packet_free(&packet)
        }
        
        guard let frame = frame else {
            return
        }
        guard let packet = packet else {
            return
        }
        
        var codecContexts: [Int32: UnsafeMutablePointer<AVCodecContext>] = [:]
        var codecs: [Int32: UnsafeMutablePointer<AVCodec>] = [:]
        
        for i in 0..<(formatContext?.pointee.nb_streams ?? 0) {
            let index = Int(i)
            guard let stream = formatContext?.pointee.streams[index] else {
                continue
            }
            guard let codecpar = stream.pointee.codecpar else {
                continue
            }
            guard let codec = avcodec_find_decoder(codecpar.pointee.codec_id) else {
                continue
            }
            let ctx = avcodec_alloc_context3(codec)
            if isErr(avcodec_parameters_to_context(ctx, codecpar), "param to contex") {
                var freed = ctx
                avcodec_free_context(&freed)
                continue
            }
            if 0 < avcodec_is_open(ctx) {
                codecContexts[Int32(i)] = ctx!
                codecs[Int32(i)] = codec
            } else {
                guard false == isErr(avcodec_open2(ctx, codec, nil), "failed \(avcodec_get_name(codec.pointee.id)) open") else {
                    continue
                }
                codecContexts[Int32(i)] = ctx!
                codecs[Int32(i)] = codec
            }
        }
        
        while 0 == av_read_frame(formatContext, packet) {
            defer {
                av_packet_unref(packet)
            }
            
            let type = self.type(at: packet.pointee.stream_index)!
            if let handle = packetHandle {
                switch handle(type: type, packet: packet) {
                case .succeed:
                    continue
                case .cancelled(let reason):
                    isErr(reason, "packet decoding cancelled")
                case .ignored:
                    break
                }
            }
            
            if let handle = frameHandle, let ctx = codecContexts[packet.pointee.stream_index] {
                let return_from_send_packet = avcodec_send_packet(ctx, packet)
                if AVERROR_CONVERT(EAGAIN) == return_from_send_packet {
                    continue
                } else if isErr(return_from_send_packet, "avcodec_send_packet for video") {
                    break
                }
                
                defer {
                    av_frame_unref(frame)
                }
                let return_from_recieve_frame = avcodec_receive_frame(ctx, frame)
                if AVERROR_CONVERT(EAGAIN) == return_from_recieve_frame {
                    continue
                } else if isErr(return_from_recieve_frame, "avcodec_receive_frame for video") {
                    break
                }
                
                var result: HandleResult = .ignored
                switch videoFilter {
                case let filter?:
                    if filter.applyFilter(frame) {
                        defer {
                            av_frame_unref(filter.filterFrame)
                        }
                        result = handle(type: type, frame: filter.filterFrame)
                    }
                default:
                    result = handle(type: type, frame: frame)
                }
                
                switch result {
                case .cancelled(let reason):
                    isErr(reason, "frame decoding cancelled")
                default:
                    break
                }
            }
            guard completion() else {
                break
            }
        }
    }
    
    func audio_decode_frame(audioCodecContext: UnsafeMutablePointer<AVCodecContext>, audio_buf: UnsafeMutablePointer<UInt8>, buf_size: Int32) -> Int32 {
        
        return 0
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

extension AVFrame: AVData, AVByteable, AVSizeProtocol {}
extension AVPicture: AVData, AVByteable {}


extension AVCodecContext: AVSizeProtocol {
    var size: CGSize {
        var size = CGSize()
        size.width = self.width.cast()
        size.height = self.height.cast()
        return size
    }
}

extension AVPixelFormat {
    var name: String {
        let name = av_get_pix_fmt_name(self) ?? av_get_pix_fmt_name(AV_PIX_FMT_NONE)!
        return String(cString: name, encoding: String.Encoding.ascii)!
    }
}

struct ValueLimiter<Number: Comparable where Number: Hashable> {
    let min: Number
    let max: Number
    
    private var rawValue: Number
    var value: Number {
        set {
            if min > newValue || max < newValue {
                assertionFailure("must be a in the range \(min) ~ \(max)")
            } else {
                rawValue = newValue
            }
        }
        get {
            return rawValue
        }
    }
    init(min: Number, max: Number, value: Number) {
        self.min = min
        self.max = max
        self.rawValue = value
    }
}

protocol AVFilterDescription {
    var description: String { get }
}

/*
 http://ffmpeg.org/ffmpeg-filters.html
 */
struct AVFilterDescriptor: AVFilterDescription {
    
    private var pix_fmts: [AVPixelFormat] = []
    private var smartblur: AVSmartblur? = nil
    
    mutating func add(pixelFormat: AVPixelFormat) {
        pix_fmts = pix_fmts + [pixelFormat]
    }
    
    mutating func set(smartblur: AVSmartblur) {
        print(String(cString: avfilter_configuration()))
        self.smartblur = smartblur
    }
    
    var description: String {
        var descriptions = [String]()
        if 0 < pix_fmts.count {
            let pix_fmts_str = self.pix_fmts.flatMap(){return $0.name}.joined(separator: "|")
            descriptions.append("format=pix_fmts=\(pix_fmts_str)")
        }
        if let smartblur = self.smartblur {
            descriptions.append(smartblur.description)
        }
        return descriptions.joined(separator: ",")
    }
    
    struct AVSmartblur: AVFilterDescription {
        
        private var luma_radius = ValueLimiter<Float>(min: 0.1, max: 5.0, value: 1.0)
        private var luma_strength = ValueLimiter<Float>(min: -1.0, max: 1.0, value: 1.0)
        private var luma_threshold = ValueLimiter<Int>(min: -30, max: 30, value: 0)
        
        private var chroma_radius = ValueLimiter<Float>(min: 0.1, max: 5.0, value: 1.0)
        private var chroma_strength = ValueLimiter<Float>(min: -1.0, max: 1.0, value: 1.0)
        private var chroma_threshold = ValueLimiter<Int>(min: -30, max: 30, value: 0)
        
        /// luma radius
        var lr: Float {
            set {
                luma_radius.value = newValue
            }
            get {
                return luma_radius.value
            }
        }
        /// luma strength
        var ls: Float {
            set {
                luma_strength.value = newValue
            }
            get {
                return luma_strength.value
            }
        }
        /// luma threshold
        var lt: Int {
            set {
                luma_threshold.value = newValue
            }
            get {
                return luma_threshold.value
            }
        }
        
        /// chroma radius
        var cr: Float {
            set {
                chroma_radius.value = newValue
            }
            get {
                return chroma_radius.value
            }
        }
        /// chroma strength
        var cs: Float {
            set {
                chroma_strength.value = newValue
            }
            get {
                return chroma_strength.value
            }
        }
        /// chroma threshold
        var ct: Int {
            set {
                chroma_threshold.value = newValue
            }
            get {
                return chroma_threshold.value
            }
        }
        
        init(lr: Float = 1.0, ls: Float = 1.0, lt: Int = 0, cr: Float = 1.0, cs: Float = 1.0, ct: Int = 0) {
            self.lr = lr
            self.ls = ls
            self.lt = lt
            self.cr = cr
            self.cs = cs
            self.ct = ct
        }
        
        var description: String {
            return "smartblur=lr=\(lr):ls=\(ls):lt=\(lt):cr=\(cr):cs=\(cs):ct=\(ct)"
        }
    }
}

extension UnsafePointerProtocol where Self.Pointee: AVSizeProtocol {
    var width: Int32 {
        return pointee.width
    }
    var height: Int32 {
        return pointee.height
    }
}

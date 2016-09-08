//
//  FFmpegHelper.swift
//  tutorial
//
//  Created by jayios on 2016. 9. 7..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation

extension AVFrame {
    mutating func videoData(time_base: AVRational) -> VideoData? {
        
        if 0 < self.width && 0 < self.height {
            
            guard let ybuf = self.data.0 else {
                return nil
            }
            
            let lumaSize = Int(self.linesize.0 * self.height)
            let chromaSize = Int(self.linesize.1 * self.height / 2)
            let y = Data(bytes: ybuf, count: lumaSize)
            guard let ubuf = self.data.1 else {
                return nil
            }
            let u = Data(bytes: ubuf, count: chromaSize)
            guard let vbuf = self.data.2 else {
                return nil
            }
            let v = Data(bytes: vbuf, count: chromaSize)
            let pts = av_frame_get_best_effort_timestamp(&self)
            return VideoData(y: y, u: u, v: v, lumaLength: self.linesize.0, chromaLength: self.linesize.1, w: self.width, h: self.height, pts: pts, dur: self.pkt_duration, time_base: time_base)
        }
        
        return nil
    }
}

extension AVFormatContext {
    mutating func streamArray(type: AVMediaType) -> [SweetStream] {
        var streams: [SweetStream] = []
        for i in 0..<Int32(self.nb_streams) {
            guard let s = SweetStream(format: &self, type: type, index: i) else {
                continue
            }
            streams.append(s)
        }
        return streams
    }
}

class SweetStream {
    let format: UnsafeMutablePointer<AVFormatContext>
    let index: Int32
    let stream: UnsafeMutablePointer<AVStream>
    let codec: UnsafeMutablePointer<AVCodecContext>
    let type: AVMediaType
    var w: Int32 {
        return codec.pointee.width
    }
    var h: Int32 {
        return codec.pointee.height
    }
    
    var fps: Double {
        return 1.0 / av_q2d(self.stream.pointee.avg_frame_rate)
    }
    
    var time_base: AVRational {
        switch self.type {
        case AVMEDIA_TYPE_AUDIO, AVMEDIA_TYPE_VIDEO:
            return self.stream.pointee.time_base
        default:
            return AVRational()
        }
    }
    
    init?(format: UnsafeMutablePointer<AVFormatContext>?, type: AVMediaType = AVMEDIA_TYPE_UNKNOWN, index: Int32 = -1) {
        guard let f = format else {
            return nil
        }
        self.format = f
        self.type = type
        
        guard type != AVMEDIA_TYPE_UNKNOWN || 0 <= index else {
            assertionFailure("must have type or positive index.")
            return nil
        }
        if 0 <= index {
            if index >= Int32(self.format.pointee.nb_streams) {
                return nil
            }
            self.index = index
        } else {
            self.index = av_find_best_stream(format, type, -1, -1, nil, 0)
            if 0 > self.index {
                return nil
            }
        }
        guard let s = self.format.pointee.streams[Int(self.index)], s.pointee.codecpar.pointee.codec_type == type else {
            return nil
        }
        self.stream = s
        
        self.codec = self.stream.pointee.codec
        self.codec.pointee.thread_count = 2
        self.codec.pointee.thread_type = FF_THREAD_FRAME
    }
    
    func open() -> Bool {
        guard let decoder = avcodec_find_decoder(self.codec.pointee.codec_id) else {
            return false
        }
        guard 0 <= avcodec_open2(self.codec, decoder, nil) else {
            return false
        }
        return true
    }
}

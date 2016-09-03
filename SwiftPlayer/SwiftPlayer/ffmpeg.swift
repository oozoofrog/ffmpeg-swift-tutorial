//
//  ffmpeg.swift
//  SwiftPlayer
//
//  Created by jayios on 2016. 8. 30..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

import Foundation
import ffmpeg

let AV_NOPTS_VALUE = Int64.min

func print_averr(function: String = #function, line: Int = #line, desc: String = "", err: Int32) {
    print("<\(function):\(line):\(desc)>")
    print_err(err)
}

extension AVFrame {
    mutating func time(time_base: AVRational) -> CFTimeInterval {
        var pts = 0.0
        let opaque = nil != self.opaque ? self.opaque.assumingMemoryBound(to: Int64.self).pointee : 0
        if AV_NOPTS_VALUE == self.pkt_pts && AV_NOPTS_VALUE != opaque {
            pts = Double(opaque)
        } else if self.pkt_pts != AV_NOPTS_VALUE {
            pts = Double(self.pkt_pts)
        } else {
            pts = 0
        }
        pts *= av_q2d(time_base)
        
        return pts
    }
    var datas: [UnsafeMutablePointer<UInt8>?] {
        let buffer_ptr : UnsafeBufferPointer<UnsafeMutablePointer<UInt8>?> = UnsafeBufferPointer.init(start: self.extended_data, count: 8)
        let arr = Array(buffer_ptr)
        return arr
    }
    var lines: UnsafeMutablePointer<Int32> {
        var tuple = self.linesize
        let tuple_ptr = withUnsafeMutablePointer(to: &tuple){$0}
        let line_ptr = tuple_ptr.withMemoryRebound(to: Int32.self, capacity: 8){$0}
        return line_ptr
    }
}

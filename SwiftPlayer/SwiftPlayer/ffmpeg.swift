//
//  ffmpeg.swift
//  SwiftPlayer
//
//  Created by jayios on 2016. 8. 30..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

import Foundation
import ffmpeg

func print_averr(desc: String? = nil, err: Int32) {
    if let desc = desc {
        print("<\(desc)>")
    }
    print_err(err)
}

extension AVFrame {
    mutating func time(rational: AVRational) -> CFTimeInterval {
        let stamp = Double(av_frame_get_best_effort_timestamp(&self))
        return stamp / 1000.0 * av_q2d(rational)
    }
}

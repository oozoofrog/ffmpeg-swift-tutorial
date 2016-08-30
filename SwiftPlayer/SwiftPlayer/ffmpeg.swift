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

func print_averr(desc: String? = nil, err: Int32) {
    if let desc = desc {
        print("<\(desc)>")
    }
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
}


struct AVFrameQueue {
    var frameQueue: UnsafeMutablePointer<UnsafeMutablePointer<AVFrame>?>!
    let frameQueueCount = 100
    var frameQueueCacheCountThreshold: Int {
        return max(1, frameQueueCount / 5)
    }
    var queue = DispatchQueue(label: "frame_queue")
    var queue_lock: DispatchSemaphore = DispatchSemaphore(value: 0)
    private var windex = 0
    private var rindex = 0
    
    var time_base: AVRational
    
    init(time_base: AVRational) {
        self.time_base = time_base
        self.frameQueue = av_mallocz(MemoryLayout<UnsafeMutablePointer<AVFrame>>.stride * frameQueueCount).assumingMemoryBound(to: Optional<UnsafeMutablePointer<AVFrame>>.self)
    }
    
    func lock() {
        queue_lock.wait()
    }
    
    func ingore() -> Bool {
        return queue_lock.wait(timeout: .now()) == .timedOut
    }
    
    func unlock() {
        queue_lock.signal()
    }
    
    var fulled: Bool {
        let threshold = self.frameQueueCacheCountThreshold
        return windex != rindex && (windex > rindex + threshold || windex > rindex - threshold)
    }
    
    mutating func write(frame: UnsafeMutablePointer<AVFrame>, completion: () -> Void) {
        queue.sync {
            if nil != self.frameQueue[windex] {
                av_frame_free(&self.frameQueue[windex])
            }
            let cloned = av_frame_clone(frame)
            self.frameQueue[windex] = cloned
            self.windex += 1
            if windex >= frameQueueCount {
                self.windex = 0
            }
            completion()
        }
    }
    
    mutating func read(time: Double = -1, handle: (_ frame: UnsafeMutablePointer<AVFrame>) -> Void) {
        queue.sync(flags: .barrier) { () -> Void in
            guard let frame = self.frameQueue[rindex] else {
                return
            }
            handle(frame)
            if time > frame.pointee.time(time_base: time_base) {
                av_frame_free(&self.frameQueue[rindex])
                self.rindex += 1
                if rindex >= frameQueueCount {
                    self.rindex = 0
                }
            }
        }
    }
}

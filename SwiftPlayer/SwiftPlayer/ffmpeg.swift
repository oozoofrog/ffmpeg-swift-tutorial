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
}

struct AVFrameQueue {
    
    var time_base: AVRational
    
    var containerQueue: UnsafeMutablePointer<UnsafeMutablePointer<AVFrame>?>
    let containerQueueCount: Int = 1024
    var containerQueueCacheCountThreshold: Int { return max(1, self.containerQueueCount / 5) }

    var queue: DispatchQueue
    var queue_lock: DispatchSemaphore
    var windex = 0
    var rindex = 0
    
    
    init(time_base: AVRational) {
        self.queue = DispatchQueue(label: "queue", qos: .utility)
        self.queue_lock = DispatchSemaphore(value: 0)
        self.time_base = time_base
        self.containerQueue = av_mallocz(MemoryLayout<UnsafeMutablePointer<AVFrame>>.stride * containerQueueCount).assumingMemoryBound(to: Optional<UnsafeMutablePointer<AVFrame>>.self)
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
        let threshold = self.containerQueueCacheCountThreshold
        return windex != rindex && (windex > rindex + threshold || windex > rindex - threshold)
    }
    
    mutating func write(frame: UnsafeMutablePointer<AVFrame>, completion: () -> Void) {
        queue.sync {
            if nil != self.containerQueue[windex] {
                av_frame_free(&containerQueue[windex])
            }
            let cloned = av_frame_clone(frame)
            containerQueue[windex] = cloned
            self.windex += 1
            if windex >= containerQueueCount {
                self.windex = 0
            }
            completion()
        }
    }
    
    mutating func read(time: Double = -1, handle: (_ container: UnsafeMutablePointer<AVFrame>) -> Void) {
        queue.sync(flags: .barrier) { () -> Void in
            guard let frame = containerQueue[rindex] else {
                return
            }
            handle(frame)
            if -1 == time || time > frame.pointee.time(time_base: time_base) {
                av_frame_free(&containerQueue[rindex])
                self.rindex += 1
                if rindex >= containerQueueCount {
                    self.rindex = 0
                }
            }
        }
    }
}

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

class AVFrameQueue {
    
    private var quit: Bool = false
    
    var time_base: AVRational
    
    var containerQueue: [UnsafeMutablePointer<AVFrame>?] = []
    var containerQueueCount: Int {
        return containerQueue.count
    }
    var containerQueueCacheCountThreshold: Int { return max(1, self.containerQueue.count / 5) }
    
    let queue: DispatchQueue = DispatchQueue(label: "queue", qos: .utility)
    let queue_lock: DispatchSemaphore = DispatchSemaphore(value: 1)
    var windex = -1
    var rindex = 0
    
    let type: AVMediaType
    init(type: AVMediaType, queueCount: Int = 2048, time_base: AVRational) {
        self.type = type
        self.time_base = time_base
        self.containerQueue = [UnsafeMutablePointer<AVFrame>?](repeating: nil, count: queueCount)
    }
    
    func stop() {
        lock()
        defer {
            unlock()
        }
        queue.suspend()
        self.containerQueue.filter { (ptr) -> Bool in
            return nil != ptr
            }.forEach { (ptr) in
                var ptr = ptr
                av_frame_free(&ptr)
        }
        quit = true
    }
    
    func stopped() -> Bool {
        lock()
        defer {
            unlock()
        }
        return quit
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
        lock()
        defer {
            unlock()
        }
        if -1 == windex {
            return false
        }
        return windex < rindex
    }
    
    var readTimeStamp: Double = 0
    
    func write(frame: UnsafeMutablePointer<AVFrame>, completion: @escaping () -> Void) {
        lock()
        defer {
            unlock()
        }
        if -1 == windex {
            windex = 0
        }
        if let writeFrame = self.containerQueue[windex] {
//            av_frame_copy(writeFrame, frame)
            av_frame_move_ref(writeFrame, frame)
        } else {
            containerQueue[windex] = av_frame_clone(frame)
        }
        self.windex += 1
        if windex >= containerQueueCount {
            self.windex = 0
        }
        completion()
    }
    
    func read(time: Double = -1, handle: @escaping (_ container: UnsafeMutablePointer<AVFrame>) -> Void) {
        lock()
        defer {
            unlock()
        }
        guard let frame = containerQueue[rindex], 0 <= windex else {
            return
        }
        readTimeStamp = frame.pointee.time(time_base: self.time_base)
        handle(frame)
        if -1 == time || time > frame.pointee.time(time_base: time_base) {
            av_frame_unref(frame)
            self.rindex += 1
            if rindex >= containerQueueCount {
                self.rindex = 0
            }
        }
    }
}

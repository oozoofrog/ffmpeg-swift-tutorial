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

public protocol AVQueueableContainer {}
public protocol AVFrameQueueContainer: AVQueueableContainer {}
public protocol AVPacketQueueContainer: AVQueueableContainer {}

extension AVFrame : AVFrameQueueContainer {}
extension AVPacket : AVPacketQueueContainer {}

struct AVQueue<Type> where Type: AVQueueableContainer {
    
    var time_base: AVRational
    
    var containerQueue: UnsafeMutablePointer<UnsafeMutablePointer<Type>?>
    let containerQueueCount: Int = 100
    var containerQueueCacheCountThreshold: Int { return max(1, self.containerQueueCount / 5) }

    var queue = DispatchQueue(label: "frame_queue")
    var queue_lock: DispatchSemaphore = DispatchSemaphore(value: 0)
    var windex = 0
    var rindex = 0
    
    
    init(time_base: AVRational) {
        self.time_base = time_base
        self.containerQueue = av_mallocz(MemoryLayout<UnsafeMutablePointer<Type>>.stride * containerQueueCount).assumingMemoryBound(to: Optional<UnsafeMutablePointer<Type>>.self)
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
}

extension AVQueue where Type: AVFrameQueueContainer {
    mutating func write(container: UnsafeMutablePointer<Type>, completion: () -> Void) {
        let frame = container.withMemoryRebound(to: AVFrame.self, capacity: MemoryLayout<AVFrame>.stride){$0}
        let containerQueue: UnsafeMutablePointer<UnsafeMutablePointer<AVFrame>?> = self.containerQueue.withMemoryRebound(to: Optional<UnsafeMutablePointer<AVFrame>>.self, capacity: MemoryLayout<Optional<UnsafeMutablePointer<AVFrame>>>.size){$0}
        queue.sync {
            if nil != containerQueue[windex] {
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
    
    mutating func read(time: Double = -1, handle: (_ container: UnsafeMutablePointer<Type>) -> Void) {
        queue.sync(flags: .barrier) { () -> Void in
            let containerQueue: UnsafeMutablePointer<UnsafeMutablePointer<AVFrame>?> = self.containerQueue.withMemoryRebound(to: Optional<UnsafeMutablePointer<AVFrame>>.self, capacity: MemoryLayout<Optional<UnsafeMutablePointer<AVFrame>>>.size){$0}
            
            guard let frame = containerQueue[rindex] else {
                return
            }
            handle(frame.withMemoryRebound(to: Type.self, capacity: MemoryLayout<Type>.stride){$0})
            if time > frame.pointee.time(time_base: time_base) {
                av_frame_free(&containerQueue[rindex])
                self.rindex += 1
                if rindex >= containerQueueCount {
                    self.rindex = 0
                }
            }
        }
    }
}

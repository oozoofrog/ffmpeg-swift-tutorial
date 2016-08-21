//
//  tutorial4.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 23..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation

@objc public class tutorial4: NSObject {
    
    static public func video_thread(arg: UnsafeMutableRawPointer) -> Int32 {
        
        let vs: UnsafeMutablePointer<VideoState> = arg.assumingMemoryBound(to: VideoState.self)
        var pkt1: AVPacket = AVPacket()
        let packet: UnsafeMutablePointer<AVPacket> = withUnsafeMutablePointer(to: &pkt1){$0}
        
        var pFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        
        while true {
            if 0 > queue_get(&vs.pointee.videoq, packet, 1) {
                break
            }
            guard 0 <= decode_frame(vs.pointee.video_ctx, packet, pFrame) else {
                break
            }
            
            if 0 > queue_picture(vs:vs, pFrame: pFrame!) {
                break
            }
            av_packet_unref(packet)
        }
        
        av_frame_free(&pFrame)
        
        return 0
    }
    
    static public func queue_picture(vs: UnsafeMutablePointer<VideoState>, pFrame: UnsafeMutablePointer<AVFrame>) -> Int32 {
        SDL_LockMutex(vs.pointee.pictq_mutex)
        while vs.pointee.pictq_size >= VIDEO_PICTURE_QUEUE_SIZE && 0 == vs.pointee.quit {
            SDL_CondWait(vs.pointee.pictq_cond, vs.pointee.pictq_mutex)
        }
        SDL_UnlockMutex(vs.pointee.pictq_mutex)
        
        if 1 == vs.pointee.quit {
            return -1
        }
        
        let pictq = withUnsafeMutablePointer(to: &vs.pointee.pictq){$0}.withMemoryRebound(to: VideoPicture.self, capacity: Int(VIDEO_PICTURE_QUEUE_SIZE) * MemoryLayout<VideoPicture>.stride){$0}
        let vp: UnsafeMutablePointer<VideoPicture> = pictq.advanced(by: Int(vs.pointee.pictq_windex))
        
        if nil == vp.pointee.texture || vp.pointee.width != vs.pointee.video_ctx.pointee.width || vp.pointee.height != vs.pointee.video_ctx.pointee.height {
            
            vp.pointee.allocated = 0
            alloc_picture(UnsafeMutableRawPointer(vs))
            if 1 == vs.pointee.quit {
                return -1
            }
        }
        
        if let _ = vp.pointee.texture {
            vp.pointee.yPlane = pFrame.pointee.data.0
            vp.pointee.uPlane = pFrame.pointee.data.1
            vp.pointee.vPlane = pFrame.pointee.data.2
            vp.pointee.width = pFrame.pointee.linesize.0
            vp.pointee.uvPitch = pFrame.pointee.linesize.1
            
            vs.pointee.pictq_windex += 1
            if vs.pointee.pictq_windex >= VIDEO_PICTURE_QUEUE_SIZE {
                vs.pointee.pictq_windex = 0
            }
            SDL_LockMutex(vs.pointee.pictq_mutex)
            vs.pointee.pictq_size += 1
            SDL_UnlockMutex(vs.pointee.pictq_mutex)
        }
        return 0
    }
}

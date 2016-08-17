//
//  SDL&FFmpeg.swift
//  tutorial
//
//  Created by Kwanghoon Choi on 2016. 8. 12..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import UIKit
import SDL
import ffmpeg

protocol PacketQueuePutter {
    mutating func put(packet: UnsafeMutablePointer<AVPacket>) -> Bool
    mutating func get(pkt: inout AVPacket, block: Bool) -> Int
}

extension PacketQueue: PacketQueuePutter {}

extension PacketQueuePutter where Self: PacketQueueProtocol {
    mutating func put(packet: UnsafeMutablePointer<AVPacket>) -> Bool {
        
        if 0 == packet.pointee.size && isErr(av_packet_ref(packet, av_packet_alloc()), "av_packet_ref") {
            return false
        }
        
        guard let packetListPtr: UnsafeMutableRawPointer = av_malloc(MemoryLayout<AVPacketList>.stride) else {
            return false
        }
        let packetList: UnsafeMutablePointer<AVPacketList> = packetListPtr.assumingMemoryBound(to: AVPacketList.self)
        
        packetList.pointee.pkt = packet.pointee
        packetList.pointee.next = nil
        
        SDL_LockMutex(mutex)
        
        if let lastPacket: UnsafeMutablePointer<AVPacketList> = lastPacket {
            lastPacket.pointee.next = packetList
        } else {
            firstPacket = packetList
        }
        lastPacket = packetList
        nb_packet += 1
        size += packetList.pointee.pkt.size
        SDL_CondSignal(cond)
        
        SDL_UnlockMutex(mutex)
        
        return true
    }
    
    mutating func get(pkt: inout AVPacket, block: Bool) -> Int {
        
        SDL_LockMutex(mutex)
        
        defer {
            SDL_UnlockMutex(mutex)
        }
        
        var pktl: UnsafeMutablePointer<AVPacketList>? = nil
        
        while true {
            
            if quit {
                return -1
            }
            pktl = firstPacket
            
            if let packetList = pktl {
                firstPacket = packetList.pointee.next.cast()
                if nil == firstPacket {
                    lastPacket = nil
                }
                nb_packet -= 1
                size -= packetList.pointee.pkt.size
                
                pkt = packetList.pointee.pkt
                av_free(packetList)
                return 1
            } else if !block {
                return 0
            } else {
                SDL_CondWait(cond, mutex)
            }
        }
    }
}

protocol AVFrameSDLTextureRenderable {
    func update(texture: OpaquePointer?, renderer: OpaquePointer?, toRect: SDL_Rect)
}

extension SDLRectCastable where Self: AVSizeProtocol {
    var SDL: SDL_Rect {
        return SDL_Rect(x: 0, y: 0, w: width, h: height)
    }
    var rect: CGRect {
        return CGRect(x: 0, y: 0, width: Int(width), height: Int(height))
    }
}

extension AVFrame: AVFrameSDLTextureRenderable, SDLRectCastable {
    func update(texture: OpaquePointer?, renderer: OpaquePointer?, toRect: SDL_Rect) {
        var rect = self.SDL
        var toRect = toRect
        if linesize.2 > 0 {
            SDL_UpdateYUVTexture(texture, &rect, data.0, linesize.0, data.1, linesize.1, data.2, linesize.2)
        } else {
            SDL_UpdateTexture(texture, &rect, data.0, linesize.0)
        }
        SDL_RenderClear(renderer)
        SDL_RenderCopy(renderer, texture, &rect, &toRect)
        SDL_RenderPresent(renderer)
    }
}

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

extension UnsafeMutablePointer where Pointee: AVSizeProtocol {
    
    func SDLAudioSpec(audio_format: SDL_AudioFormat = AUDIO_S16SYS.cast(), bufferSize: Int = 1024, callback: SDL_AudioCallback) -> SDL_AudioSpec? {
        
        guard let ptr: UnsafeMutablePointer<AVCodecContext> = self.cast() else {
            return nil
        }
        
        var audio_spec = SDL_AudioSpec()
        audio_spec.freq = ptr.pointee.sample_rate.cast()
        audio_spec.channels = ptr.pointee.channels.cast()
        audio_spec.format = audio_format
        audio_spec.silence = 0
        audio_spec.callback = callback
        audio_spec.samples = bufferSize.cast()
        audio_spec.userdata = ptr.cast()
        return audio_spec
    }

}

extension UnsafePointer where Pointee: AVSizeProtocol {
    func SDLAudioSpec(audio_format: SDL_AudioFormat = AUDIO_S16SYS.cast(), bufferSize: Int = 1024, callback: SDL_AudioCallback) -> SDL_AudioSpec? {
        let pointer: UnsafeMutablePointer<Pointee>? = self.mutable()
        return pointer?.SDLAudioSpec(audio_format: audio_format, bufferSize: bufferSize, callback: callback)
    }
}

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
        
        guard let packetList: UnsafeMutablePointer<AVPacketList> = av_malloc(strideof(AVPacketList.self))?.cast() else {
            return false
        }
        
        packetList.pointee.pkt = packet.pointee
        packetList.pointee.next = nil
        
        SDL_LockMutex(mutex)
        
        if let lastPacket: UnsafeMutablePointer<AVPacketList> = lastPacket?.mutable() {
            lastPacket.pointee.next = packetList
        } else {
            firstPacket = packetList.cast()
        }
        lastPacket = packetList.cast()
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
            pktl = firstPacket?.mutable()
            
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

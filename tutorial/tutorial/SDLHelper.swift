//
//  SDLHelper.swift
//  tutorial
//
//  Created by Kwanghoon Choi on 2016. 8. 12..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import CoreGraphics
import SDL
import AVFoundation

protocol PacketQueueProtocol {
    var firstPacket: UnsafeMutablePointer<AVPacketList>? { set get }
    var lastPacket: UnsafeMutablePointer<AVPacketList>? { set get }
    var nb_packet: Int32 { set get }
    var size: Int32 { set get }
    var mutex: OpaquePointer { set get }
    var cond: OpaquePointer { set get }
}

var PacketQueueQuit: Bool = false

struct PacketQueue: PacketQueueProtocol {
    var firstPacket: UnsafeMutablePointer<AVPacketList>? = nil
    var lastPacket: UnsafeMutablePointer<AVPacketList>? = nil
    var nb_packet: Int32 = 0
    var size: Int32 = 0
    var mutex: OpaquePointer = SDL_CreateMutex()
    var cond: OpaquePointer = SDL_CreateCond()
}


let SDL_AUDIO_BUFFER_SIZE = 1024
let MAX_AUDIO_FRAME_SIZE = 192000

extension AVHelper {
    
    static var audio_buf: [UInt8] = [UInt8].init(repeating: 0, count: MAX_AUDIO_FRAME_SIZE * 3 / 2)
    static var audio_buf_size: UInt32 = 0;
    static var audio_buf_index: UInt32 = 0;
    
    func SDLAudioSpec(audio_format: SDL_AudioFormat = AUDIO_S16SYS.cast(), bufferSize: Int = 1024) -> SDL_AudioSpec? {
        let ptr = UnsafeMutableRawPointer.allocate(bytes: MemoryLayout<AVHelper>.stride, alignedTo: 0)
        return SDLHelper.sdlAudioSpec(ptr, codecpar: self.stream(type: AVMEDIA_TYPE_AUDIO)?.pointee.codecpar, format: audio_format, bufferSize: bufferSize)
    }
}

func aspectFit(rect: SDL_Rect, inside: CGRect) -> SDL_Rect {
    var dst = SDL_Rect()
    let size = CGSize(width: Int(rect.w), height: Int(rect.h))
    let dstRect = AVMakeRect(aspectRatio: size, insideRect: inside)
    
    dst.x = dstRect.origin.x.cast()
    dst.y = dstRect.origin.y.cast()
    dst.w = dstRect.width.cast()
    dst.h = dstRect.height.cast()
    
    return dst
}

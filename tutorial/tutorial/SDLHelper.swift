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

protocol SDLRectCastable {}

extension SDLRectCastable where Self:SDLStructure {
    var rect: CGRect {
        return CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
    }
}

extension SDLRectCastable where Self: CGSizeable {
    var rect: SDL_Rect {
        return SDL_Rect(x: 0, y: 0, w: Int32(width), h: Int32(height))
    }
}

extension SDLRectCastable where Self: CGPointable, Self: CGSizeable {
    var rect: SDL_Rect {
        return SDL_Rect(x: Int32(origin.x), y: Int32(origin.y), w: Int32(width), h: Int32(height))
    }
}

protocol SDLStructure {
    var x: Int32 { get }
    var y: Int32 { get }
    var w: Int32 { get }
    var h: Int32 { get }
}

extension CGSize: CGSizeable, SDLRectCastable{}
extension CGRect: CGSizeable, CGPointable, SDLRectCastable{}
extension SDL_Rect: SDLStructure, SDLRectCastable{}

protocol SDLError {
    var SDLError: Bool { get }
}

extension Int32: SDLError {
    var SDLError: Bool {
        if 0 > self {
            print(String(cString: SDL_GetError()))
            return true
        }
        return false
    }
}

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

extension SDL_AudioSpec {
    mutating func setAudioCallback(_ callback: SDL_AudioCallback) {
        self.callback = callback
    }
}

//func audio_callback(userData: UnsafeMutableRawPointer?, stream: UnsafeMutablePointer<UInt8>?, length: Int32) -> Void {
//    print("receive audio callback")
//    
//    var stream = stream
//    
//    let helper_ptr: UnsafeMutablePointer<AVHelper> = userData!.cast(to: AVHelper.self)
//    let helper = helper_ptr.pointee
//    
//    var audio_buf: [UInt8] = [UInt8](repeating: 0, count: 192000 * 3 / 2)
//    var audio_buf_size: UInt32 = 0
//    var audio_buf_index: UInt32 = 0
//    
//    let aCodecCtx: UnsafeMutablePointer<AVCodecContext> = userData!.cast(to: AVCodecContext.self)
//    var len1: Int32 = 0
//    var audio_size: Int32 = 0
//    
//    var len = length
//    while 0 < len {
//        if audio_buf_index >= audio_buf_size {
//            audio_size = helper.audio_decode_frame(audioCodecContext: aCodecCtx, audio_buf: &audio_buf, buf_size: Int32(MemoryLayout<UInt8>.size * audio_buf.count))
//            if 0 > audio_size {
//                audio_buf_size = 1024
//                memset(&audio_buf, 0, Int(audio_buf_size))
//            } else {
//                audio_buf_size = UInt32(audio_size)
//            }
//            len1 = Int32(audio_buf_size) - Int32(audio_buf_index)
//            if len1 > len {
//                len1 = len
//            }
//            let buffer = audio_buf.withUnsafeBufferPointer(){$0}.baseAddress?.advanced(by: Int(audio_buf_index))
//            memcpy(stream, buffer, Int(len1))
//            len -= len1
//            stream = stream?.advanced(by: Int(len1))
//            audio_buf_index += UInt32(len1)
//        }
//    }
//}

extension AVHelper {
    
    static var audio_buf: [UInt8] = [UInt8].init(repeating: 0, count: MAX_AUDIO_FRAME_SIZE * 3 / 2)
    static var audio_buf_size: UInt32 = 0;
    static var audio_buf_index: UInt32 = 0;
    
    func SDLAudioSpec(audio_format: SDL_AudioFormat = AUDIO_S16SYS.cast(), bufferSize: Int = 1024) -> SDL_AudioSpec? {
        let ptr = UnsafeMutableRawPointer.allocate(bytes: MemoryLayout<AVHelper>.stride, alignedTo: 0)
        return SDLHelper.sdlAudioSpec(ptr, codecpar: self.stream(type: AVMEDIA_TYPE_AUDIO)?.pointee.codecpar, format: audio_format, bufferSize: bufferSize)
    }
}

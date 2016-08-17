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
    
    var quit: Bool { set get }
}
struct PacketQueue: PacketQueueProtocol {
    var firstPacket: UnsafeMutablePointer<AVPacketList>? = nil
    var lastPacket: UnsafeMutablePointer<AVPacketList>? = nil
    var nb_packet: Int32 = 0
    var size: Int32 = 0
    var mutex: OpaquePointer = SDL_CreateMutex()
    var cond: OpaquePointer = SDL_CreateCond()
    
    var quit: Bool = false
}


let SDL_AUDIO_BUFFER_SIZE = 1024
let MAX_AUDIO_FRAME_SIZE = 192000

extension AVHelper {
    
    static var audio_buf: [UInt8] = [UInt8].init(repeating: 0, count: MAX_AUDIO_FRAME_SIZE * 3 / 2)
    static var audio_buf_size: UInt32 = 0;
    static var audio_buf_index: UInt32 = 0;
    
    func SDLAudioSpec(audio_format: SDL_AudioFormat = AUDIO_S16SYS.cast(), bufferSize: Int = 1024, callback: SDL_AudioCallback) -> SDL_AudioSpec? {
        
        let audioParams = self.stream(type: AVMEDIA_TYPE_AUDIO)!.pointee.codecpar!
        
        var audio_spec = SDL_AudioSpec()
        audio_spec.freq = audioParams.pointee.sample_rate
        audio_spec.channels = UInt8(audioParams.pointee.channels)
        audio_spec.format = audio_format
        audio_spec.silence = 0
        audio_spec.callback = callback
        audio_spec.samples = bufferSize.cast()
        var helper: AVHelper = self
        audio_spec.userdata = withUnsafePointer(to: &helper){UnsafeMutableRawPointer(mutating: $0)}
        return audio_spec
    }
}

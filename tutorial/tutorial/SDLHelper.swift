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

protocol SDLCastable {
    var SDL: SDL_Rect { get }
    var rect: CGRect { get }
}

protocol SDLStructure {
    var x: Int32 { get }
    var y: Int32 { get }
    var w: Int32 { get }
    var h: Int32 { get }
}

extension CGSize: SDLCastable{}
extension CGRect: SDLCastable{}
extension SDL_Rect: SDLStructure, SDLCastable{}

extension SDLCastable where Self: SDLStructure {
    var SDL: SDL_Rect {
        return self as! SDL_Rect
    }
    var rect: CGRect {
        return CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
    }
}

extension SDLCastable where Self: CGSizeStructure {
    var SDL: SDL_Rect {
        return SDL_Rect(x: 0, y: 0, w: width.cast(), h: height.cast())
    }
    var rect: CGRect {
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
}

extension SDLCastable where Self: CGPointStructure, Self: CGSizeStructure {
    var SDL: SDL_Rect {
        return SDL_Rect(x: x.cast(), y: y.cast(), w: width.cast(), h: height.cast())
    }
    var rect: CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

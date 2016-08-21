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

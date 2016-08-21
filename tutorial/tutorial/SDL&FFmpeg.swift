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

protocol AVFrameSDLTextureRenderable {
    func update(texture: OpaquePointer?, renderer: OpaquePointer?, toRect: SDL_Rect)
}

func update(frame:UnsafeMutablePointer<AVFrame>?, texture: OpaquePointer?, renderer: OpaquePointer?, toRect: SDL_Rect) {
    guard let frame = frame else {
        return
    }
    var rect: SDL_Rect = SDL_Rect()
    rect.w = frame.p.width
    rect.h = frame.p.height
    var toRect = toRect
    if frame.p.linesize.2 > 0 {
        SDL_UpdateYUVTexture(texture, &rect, frame.p.data.0, frame.p.linesize.0, frame.p.data.1, frame.p.linesize.1, frame.p.data.2, frame.p.linesize.2)
    } else {
        SDL_UpdateTexture(texture, &rect, frame.p.data.0, frame.p.linesize.0)
    }
    SDL_RenderClear(renderer)
    SDL_RenderCopy(renderer, texture, &rect, &toRect)
    SDL_RenderPresent(renderer)
}

func sdl_rect(from: UnsafeMutablePointer<AVFrame>?) -> SDL_Rect {
    var rect: SDL_Rect = SDL_Rect()
    rect.w = from?.p.width ?? 0
    rect.h = from?.p.height ?? 0
    return rect
}

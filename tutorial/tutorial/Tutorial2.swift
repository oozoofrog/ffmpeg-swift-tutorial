//
//  Tutorial2.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 22..
//  Copyright © 2016년 gretech. All rights reserved.
//

import UIKit
import ffmpeg
import SDL
import AVFoundation

/**
 *  Tutorial2
 *  use SDL2
 */
struct Tutorial2: Tutorial {
    var paths: [String]
    
    init(paths: [String]) {
        self.paths = paths
    }
    
    var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
    var pCodecCtx: UnsafeMutablePointer<AVCodecContext>? = nil
    var pCodec: UnsafeMutablePointer<AVCodec>? = nil
    
    var videoStream: Int32 = 0
    
    var window: OpaquePointer? = nil
    var renderer: OpaquePointer? = nil
    var texture: OpaquePointer? = nil
    
    mutating func run() {
        
        guard av_success(avformat_open_input(&pFormatCtx, self.paths[0].cString(using: .utf8), nil, nil)) else {
            return
        }
        
        guard av_success(avformat_find_stream_info(pFormatCtx, nil)) else {
            return
        }
        
        videoStream = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        
        av_dump_format(pFormatCtx, videoStream, self.paths[0].cString(using: .utf8), 0)
        
        guard let codecpar = pFormatCtx?.p.streams[Int(videoStream)]?.p.codecpar else {
            return
        }
        pCodec = avcodec_find_decoder(codecpar.pointee.codec_id)
        guard let codec = pCodec else {
            return
        }
        
        guard let ctx = avcodec_alloc_context3(codec) else {
            return
        }
        pCodecCtx = ctx
        guard av_success(avcodec_parameters_to_context(pCodecCtx, codecpar)) else {
            return
        }
        
        guard av_success(avcodec_open2(pCodecCtx, pCodec, nil)) else {
            return
        }
        
        print("😉 \(String(cString: codec.p.name)) opened")
        
        SDL_SetMainReady()
        
        guard 0 <= SDL_Init(SDL_INIT_VIDEO.cast() | SDL_INIT_TIMER.cast()) else {
            cPrint(cString: SDL_GetError())
            return
        }
        
        window = SDL_CreateWindow("tutorial2", 0, 0, self.screen.w, self.screen.h, SDL_WINDOW_OPENGL.rawValue | SDL_WINDOW_BORDERLESS.rawValue | SDL_WINDOW_SHOWN.rawValue)
        if nil == window {
            cPrint(cString: SDL_GetError())
            return
        }
        
        defer {
            SDL_DestroyWindow(window)
        }
        
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_TARGETTEXTURE.rawValue)
        if nil == renderer {
            cPrint(cString: SDL_GetError())
            return
        }
        
        defer {
            SDL_DestroyRenderer(renderer)
        }
        
        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_IYUV.cast(), SDL_TEXTUREACCESS_STREAMING.rawValue.cast(), ctx.p.width, ctx.p.height)
        
        if nil == texture {
            cPrint(cString: SDL_GetError())
            return
        }
        
        defer {
            SDL_DestroyTexture(texture)
        }
        
        var packet = av_packet_alloc()
        var frame = av_frame_alloc()
        defer {
            av_frame_free(&frame)
            av_packet_free(&packet)
        }
        
        let dst_rect_cg = AVMakeRect(aspectRatio: CGSize(width: Int(ctx.p.width), height: Int(ctx.p.height)), insideRect: UIScreen.main.bounds)
        var dst_rect = SDL_Rect(x: dst_rect_cg.origin.x.cast(), y: dst_rect_cg.origin.y.cast(), w: dst_rect_cg.width.cast(), h: dst_rect_cg.height.cast())
        var event: SDL_Event = SDL_Event()
        decode: while 0 <= av_read_frame(pFormatCtx, packet) {
            if videoStream == packet?.p.stream_index {
                let result = decode_codec(pCodecCtx, stream: pFormatCtx?.p.streams?[Int(videoStream)], packet: packet, frame: frame)
                guard result.decoded else {
                    break
                }
                guard let frame = frame else {
                    break
                }
                var src_rect = sdl_rect(from: frame)
                SDL_UpdateYUVTexture(texture, &src_rect, frame.p.data.0, frame.p.linesize.0, frame.p.data.1, frame.p.linesize.1, frame.p.data.2, frame.p.linesize.2)
                SDL_RenderClear(renderer)
                SDL_RenderCopy(renderer, texture, &src_rect, &dst_rect)
                SDL_RenderPresent(renderer)
                
                SDL_PollEvent(&event)
                switch SDL_EventType(rawValue: event.type) {
                case SDL_QUIT, SDL_FINGERDOWN:
                    break decode
                default:
                    continue
                }
            }
        }
    }
}

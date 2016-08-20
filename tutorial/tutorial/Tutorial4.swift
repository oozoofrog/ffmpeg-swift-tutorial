//
//  Tutorial4.swift
//  tutorial
//
//  Created by Kwanghoon Choi on 2016. 8. 19..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import SDL
import ffmpeg
import AVFoundation
import UIKit

struct  Tutorial4: Tutorial {
    var paths: [String]
    
    static let SDL_AUDIO_BUFFER_SIZE: Int32 = 1024
    static let MAX_AUDIO_FRAME_SIZE: Int32 = 192000
    
    static let MAX_AUDIOQ_SIZE = (5 * 16 * 1024)
    static let MAX_VIDEOQ_SIZE = (5 * 256 * 1024)
    
    static let FF_ALLOC_EVENT  = SDL_USEREVENT
    static let FF_REFRESH_EVENT: SDL_EventType = SDL_EventType(rawValue: SDL_USEREVENT.rawValue + 1)
    static let FF_QUIT_EVENT: SDL_EventType = SDL_EventType(rawValue: SDL_USEREVENT.rawValue + 2)
    
    static let VIDEO_PICTURE_QUEUE_SIZE = 1
    
    struct PacketQueue {
        var first_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var last_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var nb_packet: Int32 = 0
        var size: Int32 = 0
        var mutex: OpaquePointer = SDL_CreateMutex()
        var cond: OpaquePointer = SDL_CreateCond()
    }
    
    struct VideoPicture {
        /// SDL_Texture
        var frame: UnsafeMutablePointer<AVFrame>? = nil
        var width: Int32 {
            return frame?.p.width ?? 0
        }
        var height: Int32 {
            return frame?.p.height ?? 0
        }
        var allocated: Bool {
            return nil != frame
        }
    }
    
    struct VideoState {
        var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        var videoStream: Int32 = 0
        var audioStream: Int32 = 0
        var audio_st: UnsafeMutablePointer<AVStream>? = nil
        var audio_ctx: UnsafeMutablePointer<AVCodecContext>? = nil
        var audioq: PacketQueue = PacketQueue()
        var audio_buf: [UInt8] = [UInt8](repeating: 0, count: (MAX_AUDIO_FRAME_SIZE.cast() * 3) / 2)
        var audio_buf_size: UInt32 = 0
        var audio_buf_index: UInt32 = 0
        var audio_pkt: AVPacket = AVPacket()
        var audio_pkt_data: UnsafeMutablePointer<UInt8>? = nil
        var audio_pkt_size: Int32 = 0
        var audio_frame: AVFrame = AVFrame()
        
        var video_st: UnsafeMutablePointer<AVStream>? = nil
        var video_ctx: UnsafeMutablePointer<AVCodecContext>? = nil
        var w: Int32 {
            return video_ctx?.p.width ?? 0
        }
        var h: Int32 {
            return video_ctx?.p.height ?? 0
        }
        var videoq: PacketQueue = PacketQueue()
        var window: OpaquePointer? = nil
        var renderer: OpaquePointer? = nil
        var texture: OpaquePointer? = nil
        
        var pictq:[VideoPicture] = [VideoPicture](repeating: VideoPicture(), count: Tutorial4.VIDEO_PICTURE_QUEUE_SIZE)
        var pictq_size: Int32 = 0
        var pictq_rindex: Int32 = 0
        var pictq_windex: Int32 = 0
        
        var pictq_mutex: OpaquePointer = SDL_CreateMutex()
        var pictq_cond: OpaquePointer = SDL_CreateCond()
        
        var parse_tid: OpaquePointer? = nil
        var video_tid: OpaquePointer? = nil
        
        var filename: UnsafePointer<CChar>? = nil
        var quit: Int32 = 0
    }
    
    static var global_video_state: VideoState = VideoState()
    
    static func packet_queue_put(q: UnsafeMutablePointer<PacketQueue>?, pkt: UnsafeMutablePointer<AVPacket>?) -> Int32 {
        var q = q
        if nil == pkt {
            if isErr(av_packet_ref(pkt, av_packet_alloc()), "packet queue put ref packet") {
                return -1
            }
        }
        
        let pkt1: UnsafeMutablePointer<AVPacketList> = av_malloc(MemoryLayout<AVPacketList>.stride).bindMemory(to: AVPacketList.self, capacity: MemoryLayout<AVPacketList>.stride)
        
        if let pkt = pkt {
            pkt1.pointee.pkt = pkt.pointee
        }
        pkt1.pointee.next = nil
        SDL_LockMutex(q?.pointee.mutex)
        
        if nil == q?.pointee.last_pkt {
            q?.pointee.first_pkt = pkt1
        } else {
            q?.pointee.last_pkt?.pointee.next = pkt1
        }
        
        q?.pointee.last_pkt = pkt1
        q?.pointee.nb_packet += 1
        q?.p.size += pkt1.p.pkt.size
        SDL_CondSignal(q?.p.cond)
        SDL_UnlockMutex(q?.p.mutex)
        return 0
    }
    
    static func packet_queue_get(q: UnsafeMutablePointer<PacketQueue>?, pkt: inout UnsafeMutablePointer<AVPacket>?, block: Int32) -> Int32 {
        guard let queue = q else {
            return 0
        }
        var q = queue
        var pkt1: UnsafeMutablePointer<AVPacketList>? = nil
        var ret: Int32 = 0
        SDL_LockMutex(q.p.mutex)
        while true {
            if 1 == global_video_state.quit {
                ret = -1
                break
            }
            
            pkt1 = q.p.first_pkt
            if let pkt1 = pkt1 {
                q.p.first_pkt = pkt1.p.next
                if nil == q.p.first_pkt {
                    q.p.last_pkt = nil
                }
                q.p.nb_packet -= 1
                q.p.size -= pkt1.p.pkt.size
                pkt?.p = pkt1.p.pkt
                av_free(pkt1.castRaw(from: AVPacketList.self))
                ret = 1
                break
            } else if 0 == block {
                ret = 0
                break
            } else {
                SDL_CondWait(q.p.cond, q.p.mutex)
            }
        }
        SDL_UnlockMutex(q.p.mutex)
        return ret
    }
    
    static func audio_decode_frame(vs: UnsafeMutablePointer<VideoState>) -> Int32 {
        var vs = vs
        guard let aCodecCtx = vs.p.audio_ctx, let st = vs.p.audio_st else {
            return 0
        }
        
        var len1: Int32 = 0
        var data_size: Int32 = 0
        
        var pkt: UnsafeMutablePointer<AVPacket>? = <<&vs.p.audio_pkt
        var frm = <<&vs.p.audio_frame
        while true {
            while vs.p.audio_pkt_size > 0 {
                guard decode_codec(aCodecCtx, stream: vs.p.audio_st, packet: <<&vs.p.audio_pkt, frame: <<&vs.p.audio_frame) else {
                    break
                }
                
                len1 = vs.p.audio_pkt_size
                if 0 > len1 {
                    vs.p.audio_pkt_size = 0
                }
                
                data_size = av_samples_get_buffer_size(nil, st.p.codecpar.p.channels, frm.p.nb_samples, AVSampleFormat(rawValue: st.p.codecpar.p.format), 1)
                let pointer: UnsafePointer<UInt8>? = vs.p.audio_buf.ptr
                SDL_MixAudio(pointer?.cast(), frm.p.data.0, data_size.cast(), 32)
                vs.p.audio_pkt_data = vs.p.audio_pkt_data?.advanced(by: Int(len1))
                vs.p.audio_pkt_size -= len1
                if 0 >= data_size {
                    continue
                }
                return data_size
            }
            if nil != pkt?.p.data {
                av_packet_unref(pkt)
            }
            if 1 == vs.p.quit {
                return -1
            }
            
            if 0 > Tutorial4.packet_queue_get(q: <<&vs.p.audioq, pkt: &pkt, block: 1) {
                return -1
            }
            vs.p.audio_pkt_data = pkt?.p.data
            vs.p.audio_pkt_size -= pkt?.p.size ?? 0
        }
        
        return 0
    }
    
    static var audio_callback:SDL_AudioCallback = { (userdata, stream, len) -> Void in
        guard let vs: UnsafeMutablePointer<VideoState> = userdata?.cast(to: VideoState.self) else {
            return
        }
        var len1: Int32 = 0, audio_size: Int32 = 0, len = len
        var stream: UnsafeMutablePointer<UInt8>? = stream
        while 0 < len {
            var vs = vs
            if vs.p.audio_buf_index >= vs.p.audio_buf_size {
                audio_size = audio_decode_frame(vs: vs)
                if 0 > audio_size {
                    vs.p.audio_buf_size = 1024
                    var ptr: UnsafeMutableRawPointer? = vs.p.audio_buf.ptr?.castRaw(from: UInt8.self)
                    memset(ptr, 0, Int(vs.p.audio_buf_size))
                } else {
                    vs.p.audio_buf_size = audio_size.cast()
                }
                vs.p.audio_buf_index = 0
            }
            len1 = Int32(vs.p.audio_buf_size - vs.p.audio_buf_index)
            if len1 > len {
                len1 = len
            }
            let ptr: UnsafeMutablePointer<UInt8>? = vs.p.audio_buf.ptr?.advanced(by: Int(vs.p.audio_buf_index)).cast()
            SDL_MixAudio(stream, ptr, Uint32(len1), 32)
            len -= len1
            stream = stream?.advanced(by: Int(len1))
            vs.p.audio_buf_index += len1.cast()
        }
    }
    
    static var sdl_refresh_timer_cb: SDL_TimerCallback = { (interval, opaque) in
        var event: SDL_Event = SDL_Event()
        event.type = Tutorial4.FF_REFRESH_EVENT.rawValue
        event.user.data1 = opaque
        SDL_PushEvent(&event)
        
        return 0
    }
    
    static func schedule_refresh(vs: UnsafeMutablePointer<VideoState>?, delay: Int32) {
        SDL_AddTimer(delay.cast(), sdl_refresh_timer_cb, vs?.castRaw(from: VideoState.self))
    }
    
    func video_display(vs: UnsafeMutablePointer<VideoState>) {
        var rect: SDL_Rect = SDL_Rect()
        var vp: UnsafeMutablePointer<VideoPicture>? = nil
        var aspect_ratio: Double = 0
        var p: SDL_Rect = SDL_Rect()
        
        vp = vs.p.pictq.ptr?.cast()
        
        if let frame = vp?.p.frame {
            let width: Double = frame.p.width.cast()
            let height: Double = frame.p.height.cast()
            if 0 == vs.p.video_st?.p.codecpar.p.sample_aspect_ratio.num {
                aspect_ratio = 0
            } else {
                aspect_ratio = av_q2d(vs.p.video_st?.p.codecpar.p.sample_aspect_ratio ?? AVRational()).cast() * width / height
            }
            if 0.0 >= aspect_ratio {
                aspect_ratio = width / height
            }
            
            p.h = UIScreen.main.bounds.height.cast()
            p.w = Int32(rint(p.h.cast() * aspect_ratio)) & -3
            if p.w > UIScreen.main.bounds.width.cast() {
                p.w = UIScreen.main.bounds.width.cast()
                p.h = Int32(rint(p.w.cast() / aspect_ratio)) & -3
            }
            p.x = (UIScreen.main.bounds.width - p.w.cast()).cast() / 2
            p.y = (UIScreen.main.bounds.height - p.h.cast()).cast() / 2
            
            rect = p
            
            var src_rect: SDL_Rect = SDL_Rect(x: 0, y: 0, w: frame.p.width, h: frame.p.height)
            SDL_UpdateYUVTexture(vs.p.texture, &src_rect, frame.p.data.0, frame.p.linesize.0, frame.p.data.1, frame.p.linesize.1, frame.p.data.2, frame.p.linesize.2)
            SDL_RenderClear(vs.p.renderer)
            SDL_RenderCopy(vs.p.renderer, vs.p.texture, &src_rect, &rect)
            SDL_RenderPresent(vs.p.renderer)
        }
    }
    
    var decode_thread: SDL_ThreadFunction = { (user_ctx) -> Int32 in
        return 0
    }
    
    var video_thread: SDL_ThreadFunction = { (user_ctx) -> Int32 in
        return 0
    }
    
    func stream_component_open(vs: UnsafeMutablePointer<VideoState>, stream_index: Int32) -> Int32 {
        var vs: UnsafeMutablePointer<VideoState> = vs
        guard let pFormatCtx = vs.p.pFormatCtx else {
            return -1
        }
        var codec: UnsafeMutablePointer<AVCodec>? = nil
        var wanted_spec: SDL_AudioSpec = SDL_AudioSpec()
        var spec: SDL_AudioSpec = SDL_AudioSpec()
        
        if stream_index < 0 || stream_index >= pFormatCtx.p.nb_streams.cast() {
            return -1
        }
        
        guard let codecpar = pFormatCtx.p.streams[stream_index.cast()]?.p.codecpar else {
            return -1
        }
        
        codec = avcodec_find_encoder(codecpar.p.codec_id)
        if nil == codec {
            print("Unsupported codec \(String(cString: avcodec_get_name(codecpar.p.codec_id)))")
            return -1
        }
        
        guard let codecCtx: UnsafeMutablePointer<AVCodecContext> = avcodec_alloc_context3(codec) else {
            return -1
        }
        if isErr(avcodec_parameters_to_context(codecCtx, codecpar), "param to context") {
            return -1
        }
        
        
        
        if codecCtx.p.codec_type == AVMEDIA_TYPE_AUDIO {
            wanted_spec.freq = codecCtx.p.sample_rate
            wanted_spec.format = AUDIO_S16SYS.cast()
            wanted_spec.channels = codecCtx.p.channels.cast()
            wanted_spec.silence = 0
            wanted_spec.callback = Tutorial4.audio_callback
            wanted_spec.samples = Tutorial4.SDL_AUDIO_BUFFER_SIZE.cast()
            wanted_spec.userdata = vs.castRaw(from: VideoState.self)
            
            if 0 > SDL_OpenAudio(&wanted_spec, &spec) {
                cPrint(cString: SDL_GetError())
                return -1
            }
        }
        
        if isErr(avcodec_open2(codecCtx, codec, nil), "open codec") {
            print("Unsupported codec \(String(cString: avcodec_get_name(codecpar.p.codec_id)))")
            return -1
        }
        
        switch  codecpar.p.codec_type {
        case AVMEDIA_TYPE_AUDIO:
            vs.p.audioStream = stream_index
            vs.p.audio_st = pFormatCtx.p.streams[stream_index.cast()]
            vs.p.audio_ctx = codecCtx
            vs.p.audio_buf_size = 0
            vs.p.audio_buf_index = 0
            memset(&vs.p.audio_pkt, 0, MemoryLayout<AVPacket>.stride)
            SDL_PauseAudio(0)
        case AVMEDIA_TYPE_VIDEO:
            vs.p.videoStream = stream_index
            vs.p.video_st = pFormatCtx.p.streams[stream_index.cast()]
            vs.p.video_ctx = codecCtx
            
            vs.p.video_tid = SDL_CreateThread(video_thread, "video thread", vs.castRaw(from: VideoState.self))
        default:
            break
        }
        
        return 0
    }
    
    func video_refresh_timer(userdata: UnsafeMutableRawPointer) {
        var vs: UnsafeMutablePointer<VideoState> = userdata.cast(to: VideoState.self)
        if let st = vs.p.video_st {
            if vs.p.pictq_size == 0 {
                Tutorial4.schedule_refresh(vs: vs, delay: 1)
            } else {
                Tutorial4.schedule_refresh(vs: vs, delay: 80)
                video_display(vs: vs)
                vs.p.pictq_rindex += 1
                if vs.p.pictq_rindex == Tutorial4.VIDEO_PICTURE_QUEUE_SIZE.cast() {
                    vs.p.pictq_rindex = 0
                }
                SDL_LockMutex(vs.p.pictq_mutex)
                vs.p.pictq_size -= 1
                SDL_CondSignal(vs.p.pictq_cond)
                SDL_UnlockMutex(vs.p.pictq_mutex)
            }
        } else {
            Tutorial4.schedule_refresh(vs: vs, delay: 100)
        }
    }
    
    func alloc_picture(userdata: UnsafeMutableRawPointer) {
        var vs:UnsafeMutablePointer<VideoState> = userdata.cast(to: VideoState.self)
        var vp: UnsafeMutablePointer<VideoPicture>? = vs.p.pictq.ptr?.advanced(by: vs.p.pictq_windex.cast()).cast()
 
        if nil != vp?.p.frame {
            av_frame_free(<<&vp!.p.frame)
        }
        
        vp?.p.frame = av_frame_alloc()
        SDL_LockMutex(vs.p.pictq_mutex)
        SDL_CondSignal(vs.p.pictq_cond)
        SDL_UnlockMutex(vs.p.pictq_mutex)
    }
    
    func queue_picture(vs: UnsafeMutablePointer<VideoState>, pFrame: UnsafeMutablePointer<AVFrame>) -> Int32 {
        SDL_LockMutex(vs.p.pictq_mutex)
        while vs.p.pictq_size >= Tutorial4.VIDEO_PICTURE_QUEUE_SIZE.cast() && 1 != vs.p.quit {
            SDL_CondWait(vs.p.pictq_cond, vs.p.pictq_mutex)
        }
        SDL_UnlockMutex(vs.p.pictq_mutex)
        if 1 == vs.p.quit {
            return -1
        }
        var vp: UnsafeMutablePointer<VideoPicture>? = vs.p.pictq.ptr?.advanced(by: Int(vs.p.pictq_windex)).cast()
        if nil == vp?.p.frame || vp?.p.width != vs.p.w || vp?.p.height != vs.p.h {
            var event: SDL_Event = SDL_Event()
            if nil != vp?.p.frame {
                av_frame_free(&vp!.p.frame)
                vp?.p.frame = nil
            }
            event.type = Tutorial4.FF_ALLOC_EVENT.rawValue
            event.user.data1 = vs.castRaw(from: VideoState.self)
            SDL_PushEvent(&event)
            
            SDL_LockMutex(vs.p.pictq_mutex)
            while false == vp?.p.allocated && 1 != vs.p.quit {
                SDL_CondWait(vs.p.pictq_cond, vs.p.pictq_mutex)
            }
            SDL_UnlockMutex(vs.p.pictq_mutex)
            if 1 == vs.p.quit {
                return -1
            }
        }
        
        if let frame = vp?.p.frame {
            var rect: SDL_Rect = sdl_rect(from: frame)
            SDL_UpdateYUVTexture(vs.p.texture, &rect, frame.p.data.0, frame.p.linesize.0, frame.p.data.1, frame.p.linesize.1, frame.p.data.2, frame.p.linesize.2)
            
        }
        
        return 0
    }
    
    init(paths: [String]) {
        self.paths = paths
    }
    
    func run() {
        guard let helper = AVHelper(inputPath: paths[0]) else {
            return
        }
        
        guard helper.open() else {
            return
        }
        
        guard  SDLHelper().sdl_init(UInt32(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) else {
            return
        }
        
        var event: SDL_Event = SDL_Event()
        var vs: VideoState = VideoState()
        
        vs.filename = paths[0].cString(using: .utf8)?.withUnsafeBufferPointer(){$0}.baseAddress
        
        Tutorial4.schedule_refresh(vs: &vs, delay: 40)
        
        guard let parse_tid = SDL_CreateThread(decode_thread, "video_thread", withUnsafeMutablePointer(to: &vs){$0}.castRaw(from: VideoState.self)) else {
            cPrint(cString: SDL_GetError())
            return
        }
        vs.parse_tid = parse_tid
        
    }
    
}

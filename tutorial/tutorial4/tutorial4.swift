//
//  tutorial4.swift
//  tutorial
//
//  Created by jayios on 2016. 8. 23..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import AVFoundation

let MAX_AUDIOQ_SIZE: Int32 = (5 * 16 * 1024)
let MAX_VIDEOQ_SIZE: Int32 = (5 * 256 * 1024)

@objc public class tutorial4: NSObject {
    
    static var window: OpaquePointer?
    static var renderer: OpaquePointer?
    static var screen_mutex: OpaquePointer?
    
    static public func packet_queue_init(q: UnsafeMutablePointer<PacketQueue>) {
        memset(q, 0, MemoryLayout<PacketQueue>.stride)
        q.pointee.mutex = SDL_CreateMutex()
        q.pointee.cond = SDL_CreateCond()
    }
    
    static public func packet_queue_put(q: UnsafeMutablePointer<PacketQueue>, pkt: UnsafeMutablePointer<AVPacket>?) -> Int32 {
        var pkt1: UnsafeMutablePointer<AVPacketList>!
        if nil == pkt?.pointee.data {
            guard av_success(av_packet_ref(pkt, av_packet_alloc())) else {
                return -1
            }
        }
        
        pkt1 = av_malloc(MemoryLayout<AVPacketList>.stride).assumingMemoryBound(to: AVPacketList.self)
        if let pkt = pkt {
            pkt1.pointee.pkt = pkt.pointee
        }
        pkt1.pointee.next = nil
        
        SDL_LockMutex(q.pointee.mutex)
        
        if nil == q.pointee.last_pkt {
            q.pointee.first_pkt = pkt1
        } else {
            q.pointee.last_pkt.pointee.next = pkt1
        }
        q.pointee.last_pkt = pkt1
        q.pointee.nb_packets += 1
        q.pointee.size += pkt1.pointee.pkt.size
        SDL_CondSignal(q.pointee.cond)
        
        SDL_UnlockMutex(q.pointee.mutex)
        
        return 0
    }
    
    static public func packet_queue_get(is vs: UnsafeMutablePointer<VideoState>, q: UnsafeMutablePointer<PacketQueue>, pkt: UnsafeMutablePointer<AVPacket>, block: Int32) -> Int32 {
        var pkt1: UnsafeMutablePointer<AVPacketList>? = nil
        var ret: Int32 = 0
        
        SDL_LockMutex(q.pointee.mutex)
        
        while true {
            if vs.pointee.quit == 1 {
                ret = -1
                break
            }
            
            pkt1 = q.pointee.first_pkt
            if let pkt1 = pkt1 {
                q.pointee.first_pkt = pkt1.pointee.next
                if nil == q.pointee.first_pkt {
                    q.pointee.last_pkt = nil
                }
                q.pointee.nb_packets -= 1
                q.pointee.size -= pkt1.pointee.pkt.size
                pkt.pointee = pkt1.pointee.pkt
                av_free(pkt1)
                ret = 1
                break
            } else if (0 == block) {
                ret = 0
                break
            } else {
                SDL_CondWait(q.pointee.cond, q.pointee.mutex)
            }
        }
        
        SDL_UnlockMutex(q.pointee.mutex)
        
        return ret
    }
    
    static public func audio_resampling(ctx: UnsafeMutablePointer<AVCodecContext>, frame: UnsafeMutablePointer<AVFrame>, output_format: AVSampleFormat, out_channels: Int32, out_sample_rate: Int32, out_buffer: UnsafeMutablePointer<UInt8>) -> Int32 {
        var ret: Int32 = 0
        var swr_ctx_ptr: OpaquePointer? = swr_alloc()
        guard swr_ctx_ptr != nil else {
            print("swr alloc error")
            return -1
        }
        let swr_ctx = UnsafeMutableRawPointer(swr_ctx_ptr)
        var in_channel_layout = Int64(ctx.pointee.channel_layout)
        var out_channel_layout = Int64(AV_CH_FRONT_LEFT | AV_CH_FRONT_RIGHT)
        var out_nb_channels: Int32 = 0
        var out_linesize: Int32 = 0
        var in_nb_samples: Int32 = 0
        var out_nb_samples: Int32 = 0
        var max_out_nb_samples: Int32 = 0
        var resampled_data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>? = nil
        var resampled_data_size: Int32 = 0
        
        in_channel_layout = av_get_default_channel_layout(ctx.pointee.channels)
        guard 0 < in_channel_layout else {
            print("in channel layout error")
            return -1
        }
        
        if 1 == out_channels {
            out_channel_layout = Int64(AV_CH_LAYOUT_MONO)
        } else if (2 == out_channels) {
            out_channel_layout = Int64(AV_CH_FRONT_LEFT | AV_CH_FRONT_RIGHT)
        } else {
            out_channel_layout = Int64(AV_CH_FRONT_LEFT | AV_CH_FRONT_RIGHT) // AV_CH_LAYOUT_SURROUND
        }
        
        in_nb_samples = frame.pointee.nb_samples
        guard 0 < in_nb_samples else {
            print("in_nb_samples error")
            return -1
        }
        
        av_opt_set_int(swr_ctx, "in_channel_layout", in_channel_layout, 0)
        av_opt_set_int(swr_ctx, "in_sample_rate", Int64(ctx.pointee.sample_rate), 0)
        av_opt_set_sample_fmt(swr_ctx, "in_sample_fmt", ctx.pointee.sample_fmt, 0)
        
        av_opt_set_int(swr_ctx, "out_channel_layout", out_channel_layout, 0)
        av_opt_set_int(swr_ctx, "out_sample_rate", Int64(out_sample_rate), 0)
        av_opt_set_sample_fmt(swr_ctx, "out_sample_fmt", output_format, 0)
        
        guard av_success_desc(swr_init(OpaquePointer.init(swr_ctx)), "Failed to initialization the resampling context") else {
            return -1
        }
        
        // in_nb_samples * out_sample_rate / in_sample_rate and round up
        out_nb_samples = Int32(av_rescale_rnd(Int64(in_nb_samples), Int64(out_sample_rate), Int64(ctx.pointee.sample_rate), AV_ROUND_UP))
        max_out_nb_samples = out_nb_samples
        guard 0 < max_out_nb_samples else {
            print("av_rescale_rnd error")
            return -1
        }
        
        out_nb_channels = av_get_channel_layout_nb_channels(UInt64(out_channel_layout))
        
        ret = av_samples_alloc_array_and_samples(&resampled_data, &resampled_data_size, out_nb_channels, out_nb_samples, output_format, 0)
        guard av_success_desc(ret, "av_samples_alloc_array_and_samples") else {
            return -1
        }
        
        out_nb_samples = Int32(av_rescale_rnd(swr_get_delay(OpaquePointer(swr_ctx), Int64(ctx.pointee.sample_rate)) + Int64(in_nb_samples), Int64(out_sample_rate), Int64(ctx.pointee.sample_rate), AV_ROUND_UP))
        
        guard 0 < out_nb_samples else {
            print("av_rescale_rnd errors")
            return -1
        }
        
        if out_nb_samples > max_out_nb_samples {
            av_free(resampled_data?[0])
            ret = av_samples_alloc(resampled_data, &out_linesize, out_nb_channels, out_nb_samples, output_format, 1)
            max_out_nb_samples = out_nb_samples
        }
        let frame_buffer = withUnsafeMutablePointer(to: &frame.pointee.data){$0}.withMemoryRebound(to: Optional<UnsafePointer<UInt8>>.self, capacity: MemoryLayout<UnsafePointer<UInt8>>.stride * 8){$0}
        ret = swr_convert(OpaquePointer(swr_ctx), resampled_data, out_nb_samples, frame_buffer, frame.pointee.nb_samples)
        guard av_success_desc(ret, "swr_conver") else {
            return -1
        }
        
        resampled_data_size = av_samples_get_buffer_size(&out_linesize, out_nb_channels, ret, output_format, 1)
        guard av_success_desc(resampled_data_size, "av_samples_get_buffer_size") else {
            return -1
        }
        
        memcpy(out_buffer, resampled_data?[0], Int(resampled_data_size))
        
        av_freep(&resampled_data)
        resampled_data = nil
        swr_free(&swr_ctx_ptr)
        
        return resampled_data_size
    }
    
    static public func audio_decode_frame(vs: UnsafeMutablePointer<VideoState>, audio_buf: UnsafeMutablePointer<UInt8>, buf_size: Int32) -> Int32 {
        
        var len1: Int32 = 0
        var data_size: Int32 = 0
        let pkt = withUnsafeMutablePointer(to: &vs.pointee.audio_pkt){$0}
        
        while true {
            while vs.pointee.audio_pkt_size > 0 {
                len1 = tutorial4.decode_frame(stream: vs.pointee.audio_st, codec: vs.pointee.audio_ctx, pkt: pkt, frame: &vs.pointee.audio_frame)
                if 0 > len1 {
                    vs.pointee.audio_pkt_size = 0
                    break
                }
                data_size = tutorial4.audio_resampling(ctx: vs.pointee.audio_ctx, frame: &vs.pointee.audio_frame, output_format: AV_SAMPLE_FMT_S16, out_channels: vs.pointee.audio_frame.channels, out_sample_rate: vs.pointee.audio_frame.sample_rate, out_buffer: audio_buf);
                assert(data_size <= buf_size)
                
                vs.pointee.audio_pkt_data = vs.pointee.audio_pkt_data.advanced(by: Int(len1))
                vs.pointee.audio_pkt_size -= len1
                if 0 >= data_size {
                    continue
                }
                return data_size
            }
            if nil != pkt.pointee.data {
                av_packet_unref(pkt)
            }
            if vs.pointee.quit == 1 {
                return -1
            }
            guard av_success(packet_queue_get(is: vs, q: &vs.pointee.audioq, pkt: pkt, block: 1)) else {
                return -1
            }
            vs.pointee.audio_pkt_data = pkt.pointee.data
            vs.pointee.audio_pkt_size += pkt.pointee.size
        }
    }
    
    static public var audio_callback: SDL_AudioCallback = { userdata, stream, len in
        guard let vs: UnsafeMutablePointer<VideoState> = userdata?.assumingMemoryBound(to: VideoState.self) else {
            return
        }
        var state = vs
        var len1: Int32 = 0
        var audio_size: Int32 = 0
        
        var len = len
        var stream = stream
        
        while 0 < len {
            if vs.pointee.audio_buf_index >= vs.pointee.audio_buf_size {
                audio_size = tutorial4.audio_decode_frame(vs: vs, audio_buf: vs.pointee.audio_buf_ptr, buf_size: Int32(vs.pointee.audio_buf_ptr_length))
                if 0 > audio_size {
                    vs.pointee.audio_buf_size = 1024
                    SDL_memset(vs.pointee.audio_buf_ptr, 0, Int(vs.pointee.audio_buf_size))
                } else {
                    vs.pointee.audio_buf_size = UInt32(audio_size)
                }
                vs.pointee.audio_buf_index = 0
            }
            len1 = Int32(vs.pointee.audio_buf_size - vs.pointee.audio_buf_index)
            if len1 > len {
                len1 = len
            }
            SDL_memcpy(stream, vs.pointee.audio_buf_ptr.advanced(by: Int(vs.pointee.audio_buf_index)), Int(len1))
            len -= len1
            stream = stream?.advanced(by: Int(len1))
            vs.pointee.audio_buf_index += UInt32(len1)
        }
    }
    
    static public var video_thread: SDL_ThreadFunction = { arg in
        
        let vs: UnsafeMutablePointer<VideoState> = arg!.assumingMemoryBound(to: VideoState.self)
        var pkt1: AVPacket = AVPacket()
        let packet: UnsafeMutablePointer<AVPacket> = withUnsafeMutablePointer(to: &pkt1){$0}
        
        var pFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        
        while true {
            if 0 > packet_queue_get(is: vs, q: &vs.pointee.videoq, pkt: packet, block: 1) {
                break
            }
            guard 0 <= tutorial4.decode_frame(stream: vs.pointee.video_st, codec: vs.pointee.video_ctx, pkt: packet, frame: pFrame) else {
                break
            }
            
            if 0 > queue_picture(vs:vs, pFrame: pFrame!) {
                break
            }
            av_packet_unref(packet)
        }
        
        av_frame_free(&pFrame)
        
        return 0
    }
    
    static public func queue_picture(vs: UnsafeMutablePointer<VideoState>, pFrame: UnsafeMutablePointer<AVFrame>) -> Int32 {
        SDL_LockMutex(vs.pointee.pictq_mutex)
        while vs.pointee.pictq_size >= VIDEO_PICTURE_QUEUE_SIZE && 0 == vs.pointee.quit {
            SDL_CondWait(vs.pointee.pictq_cond, vs.pointee.pictq_mutex)
        }
        SDL_UnlockMutex(vs.pointee.pictq_mutex)
        
        if 1 == vs.pointee.quit {
            return -1
        }
        
        let pictq = withUnsafeMutablePointer(to: &vs.pointee.pictq){$0}.withMemoryRebound(to: VideoPicture.self, capacity: Int(VIDEO_PICTURE_QUEUE_SIZE) * MemoryLayout<VideoPicture>.stride){$0}
        let vp: UnsafeMutablePointer<VideoPicture> = pictq.advanced(by: Int(vs.pointee.pictq_windex))
        
        if nil == vp.pointee.texture || vp.pointee.width != vs.pointee.video_ctx.pointee.width || vp.pointee.height != vs.pointee.video_ctx.pointee.height {
            
            vp.pointee.allocated = 0
            alloc_pict(userdata: UnsafeMutableRawPointer(vs))
            if 1 == vs.pointee.quit {
                return -1
            }
        }
        
        if let _ = vp.pointee.texture {
            vp.pointee.yPlane = pFrame.pointee.data.0
            vp.pointee.uPlane = pFrame.pointee.data.1
            vp.pointee.vPlane = pFrame.pointee.data.2
            vp.pointee.width = pFrame.pointee.linesize.0
            vp.pointee.uvPitch = pFrame.pointee.linesize.1
            
            vs.pointee.pictq_windex += 1
            if vs.pointee.pictq_windex >= VIDEO_PICTURE_QUEUE_SIZE {
                vs.pointee.pictq_windex = 0
            }
            SDL_LockMutex(vs.pointee.pictq_mutex)
            vs.pointee.pictq_size += 1
            SDL_UnlockMutex(vs.pointee.pictq_mutex)
        }
        return 0
    }
    
    static var sdl_refresh_timer_cb: SDL_TimerCallback = {
        var event = SDL_Event()
        event.type = (SDL_USEREVENT).rawValue
        event.user.data1 = $1
        SDL_PushEvent(&event)
        return 0
    }
    
    static func schedule_refresh(vs: UnsafeMutablePointer<VideoState>, delay: Int32) {
        SDL_AddTimer(Uint32(delay), tutorial4.sdl_refresh_timer_cb, vs)
    }
    
    static func video_display(vs: UnsafeMutablePointer<VideoState>,
                              mutex: OpaquePointer,
                              window: OpaquePointer,
                              renderer: OpaquePointer) {
        let vp = vs.pointee.pictq_ptr.advanced(by: Int(vs.pointee.pictq_rindex))
        guard let texture = vp.pointee.texture else {
            return
        }
        
        SDL_LockMutex(mutex)
        
        SDL_UpdateYUVTexture(texture, nil, vp.pointee.yPlane, vs.pointee.video_ctx.pointee.width, vp.pointee.uPlane, vp.pointee.uvPitch, vp.pointee.vPlane, vp.pointee.uvPitch)
        SDL_RenderClear(renderer)
        SDL_RenderCopy(renderer, texture, &vs.pointee.src_rect, &vs.pointee.dst_rect)
        SDL_RenderPresent(renderer)
        
        SDL_UnlockMutex(mutex)
    }
    
    static public func video_refresh_timer(userdata: UnsafeMutableRawPointer, mutex: OpaquePointer, window: OpaquePointer, renderer: OpaquePointer) {
        let vs = userdata.assumingMemoryBound(to: VideoState.self)
        if let _ = vs.pointee.video_st {
            if 0 == vs.pointee.pictq_size {
                schedule_refresh(vs: vs, delay: 1)
            } else {
                schedule_refresh(vs: vs, delay: 40)
                
                video_display(vs: vs, mutex: mutex, window: window, renderer: renderer)
                
                vs.pointee.pictq_rindex += 1
                if vs.pointee.pictq_rindex >= VIDEO_PICTURE_QUEUE_SIZE {
                    vs.pointee.pictq_rindex = 0
                }
                
                SDL_LockMutex(vs.pointee.pictq_mutex)
                vs.pointee.pictq_size -= 1
                SDL_CondSignal(vs.pointee.pictq_cond)
                SDL_UnlockMutex(vs.pointee.pictq_mutex)
            }
        } else {
            schedule_refresh(vs: vs, delay: 100)
        }
    }
    
    static public func alloc_pict(userdata: UnsafeMutableRawPointer) {
        let vs = userdata.assumingMemoryBound(to: VideoState.self)
        let vp = vs.pointee.pictq_ptr.advanced(by: Int(vs.pointee.pictq_windex))
        vp.pointee.alloc_picture(vs: vs)
    }
    
    static public func stream_open(vs: UnsafeMutablePointer<VideoState>, at: Int32) -> Int32 {
        return vs.pointee.stream_open(at: at)
    }
    
    static public var decode_thread: SDL_ThreadFunction = { (arg) in
        guard let vs: UnsafeMutablePointer<VideoState> = arg?.assumingMemoryBound(to: VideoState.self) else {
            return -1
        }
        
        var pkt: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        
        defer {
            av_packet_free(&pkt)
        }
        
        vs.pointee.videoStream = -1
        vs.pointee.audioStream = -1
        var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        guard 0 <= avformat_open_input(&pFormatCtx, vs.pointee.filename, nil, nil) else {
            return -1
        }
        
        vs.pointee.pFormatCtx = pFormatCtx
        
        guard 0 <= avformat_find_stream_info(pFormatCtx, nil) else {
            print("Couldn't find stream info for \(String(cString: vs.pointee.filename))")
            return -1
        }
        av_dump_format(pFormatCtx, 0, vs.pointee.filename, 0)
        
        let video_stream_index: Int32 = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        let audio_stream_index: Int32 = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        
        guard 0 <= tutorial4.stream_open(vs: vs, at: video_stream_index) else {
            print("Couldn't open video stream")
            return -1
        }
        
        guard 0 <= tutorial4.stream_open(vs: vs, at: audio_stream_index) else {
            print("Couldn't open audio stream")
            return -1
        }
        
        decode: while true {
            if vs.pointee.quit == 1 {
                break decode
            }
            
            guard MAX_AUDIOQ_SIZE >= vs.pointee.audioq.size && MAX_VIDEOQ_SIZE >= vs.pointee.videoq.size else {
                SDL_Delay(10)
                continue decode
            }
            
            if 0 > av_read_frame(vs.pointee.pFormatCtx, pkt) {
                guard 0 != vs.pointee.pFormatCtx.pointee.pb.pointee.error else {
                    break
                }
                SDL_Delay(100)
                continue decode
            }
            
            switch pkt?.pointee.stream_index {
            case video_stream_index?:
                guard 0 <= tutorial4.packet_queue_put(q:&vs.pointee.videoq, pkt: pkt!) else {
                    break decode
                }
            case audio_stream_index?:
                guard 0 <= tutorial4.packet_queue_put(q:&vs.pointee.audioq, pkt: pkt!) else {
                    break decode
                }
            default:
                av_packet_unref(pkt)
            }
        }
        
        while 0 == vs.pointee.quit {
            SDL_Delay(100)
        }
        
        return 0
    }
    
    static public func decode_frame(stream: UnsafeMutablePointer<AVStream>, codec: UnsafeMutablePointer<AVCodecContext>, pkt: UnsafeMutablePointer<AVPacket>?, frame: UnsafeMutablePointer<AVFrame>?) -> Int32 {
        var got_picture: Bool = true
        var ret: Int32 = 0
        var length: Int32 = 0
        
        decode: while (0 < (pkt?.pointee.size ?? 0) || (nil == pkt?.pointee.data && got_picture)) && 0 <= ret {
            got_picture = false
            
            switch codec.pointee.codec_type {
            case AVMEDIA_TYPE_AUDIO, AVMEDIA_TYPE_VIDEO:
                ret = avcodec_send_packet(codec, pkt)
                if 0 > ret && false == AVFILTER_EOF(ret) {
                    break decode
                }
                if 0 <= ret {
                    pkt?.pointee.size = 0
                }
                ret = avcodec_receive_frame(codec, frame)
                got_picture = 0 <= ret
                if AVFILTER_EOF(ret) {
                    ret = 0
                }
            default:
                break
            }
            if 0 <= ret {
                if got_picture {
                    stream.pointee.nb_decoded_frames += 1
                }
                ret = got_picture ? 1 : 0
            }
        }
        
        length = frame?.pointee.pkt_size ?? 0
        
        if nil == pkt?.pointee.data && got_picture {
            return -1
        }
        
        if 0 <= ret && 0 > length {
            length = 0
        }
        
        return length
    }
}

extension VideoState {
    mutating func stream_open(at: Int32) -> Int32 {
        var ret: Int32 = 0
        if 0 > at || UInt32(at) >= pFormatCtx.pointee.nb_streams  {
            return -1
        }
        
        guard let codecpar = pFormatCtx.pointee.streams[Int(at)]?.pointee.codecpar else {
            return -1
        }
        let codec_name = String(cString: avcodec_get_name(codecpar.pointee.codec_id))
        guard let codec = avcodec_find_decoder(codecpar.pointee.codec_id) else {
            print("Couldn't find decoder for \(codec_name)")
            return -1
        }
        
        guard let codecCtx = avcodec_alloc_context3(codec) else {
            print("Couldn't alloc codec context for \(codec_name)")
            return -1
        }
        
        ret = avcodec_parameters_to_context(codecCtx, codecpar)
        
        var ctx: UnsafeMutablePointer<AVCodecContext>? = codecCtx
        guard 0 <= ret else {
            avcodec_free_context(&ctx)
            print("Couldn't copy to codec context from codec parameters for \(codec_name)")
            return -1
        }
        
        var wanted_spec: SDL_AudioSpec = SDL_AudioSpec()
        var spec: SDL_AudioSpec = SDL_AudioSpec()
        let userdata = UnsafeMutableRawPointer(withUnsafeMutablePointer(to: &self){$0})
        switch codecpar.pointee.codec_type {
        case AVMEDIA_TYPE_AUDIO:
            wanted_spec.freq = codecpar.pointee.sample_rate
            wanted_spec.format = UInt16(AUDIO_S16SYS)
            wanted_spec.channels = UInt8(codecpar.pointee.channels)
            wanted_spec.silence = 0
            wanted_spec.samples = UInt16(SDL_AUDIO_BUFFER_SIZE)
            wanted_spec.callback = tutorial4.audio_callback
            wanted_spec.userdata = userdata
            guard 0 <= SDL_OpenAudio(&wanted_spec, &spec) else {
                print("SDL_OpenAudio failed with \(String(cString: SDL_GetError()))")
                return -1
            }
            
            guard 0 <= avcodec_open2(codecCtx, codec, nil) else {
                avcodec_free_context(&ctx)
                print("Couldn't open \(codec_name)")
                return -1
            }
            
            self.audioStream = at
            self.audio_st = pFormatCtx.pointee.streams.advanced(by: Int(at)).pointee
            self.audio_ctx = codecCtx
            self.audio_buf_size = 0
            self.audio_buf_index = 0
            SDL_memset(&audio_pkt, 0, MemoryLayout<AVPacket>.stride)
            tutorial4.packet_queue_init(q: &audioq)
            
            SDL_PauseAudio(0)
        case AVMEDIA_TYPE_VIDEO:
            guard 0 <= avcodec_open2(codecCtx, codec, nil) else {
                avcodec_free_context(&ctx)
                print("Couldn't open \(codec_name)")
                return -1
            }
            self.videoStream = at
            self.video_st = pFormatCtx.pointee.streams.advanced(by: Int(at)).pointee
            self.video_ctx = codecCtx
            tutorial4.packet_queue_init(q: &videoq)
            self.video_tid = SDL_CreateThread(tutorial4.video_thread, "video_thread", userdata)
            
            let width: Int32 = codecCtx.pointee.width
            let height: Int32 = codecCtx.pointee.height
            
            self.src_rect.w = width
            self.src_rect.h = height
            
            var w: Int32 = 0
            var h: Int32 = 0
            SDL_GetWindowSize(tutorial4.window, &w, &h)
            
            let textureSize = CGSize(width: Int(width), height: Int(height))
            let dstRect = AVMakeRect(aspectRatio: textureSize, insideRect: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            
            dst_rect.x = Int32(ceil(dstRect.origin.x))
            dst_rect.y = Int32(ceil(dstRect.origin.y))
            dst_rect.w = Int32(ceil(dstRect.width))
            dst_rect.h = Int32(ceil(dstRect.height))
            
        default:
            break
        }
        
        return 0
    }
}

extension VideoPicture {
    var uvPlaneSz: Int {
        return self.yPlaneSz / 4
    }
    mutating func alloc_picture(vs: UnsafeMutablePointer<VideoState>) {
        if nil != self.texture {
            SDL_DestroyTexture(self.texture)
        }
        SDL_LockMutex(tutorial4.screen_mutex)
        let w: Int32 = vs.pointee.video_ctx.pointee.width
        let h: Int32 = vs.pointee.video_ctx.pointee.height
        
        self.texture = SDL_CreateTexture(tutorial4.renderer, Uint32(SDL_PIXELFORMAT_IYUV), Int32(SDL_TEXTUREACCESS_STREAMING.rawValue), w, h)
        self.yPlaneSz = size_t(w * h)
        self.yPlane = SDL_malloc(yPlaneSz).assumingMemoryBound(to: UInt8.self)
        self.uPlane = SDL_malloc(uvPlaneSz).assumingMemoryBound(to: UInt8.self)
        self.vPlane = SDL_malloc(uvPlaneSz).assumingMemoryBound(to: UInt8.self)
        
        self.uvPitch = vs.pointee.video_ctx.pointee.width / 2
        
        SDL_UnlockMutex(tutorial4.screen_mutex)
        
        self.width = w
        self.height = h
        self.allocated = 1
    }
}

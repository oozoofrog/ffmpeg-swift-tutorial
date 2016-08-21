
import UIKit
import ffmpeg
import SDL
import AVFoundation

let SDL_AUDIO_BUFFER_SIZE: Int32 =  1024
let MAX_AUDIO_FRAME_SIZE: Int32 = 192000

struct  Tutorial3: Tutorial {
    
    struct PacketQueue {
        var first_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var last_pkt: UnsafeMutablePointer<AVPacketList>? = nil
        var nb_packets: Int32 = 0
        var size: Int32 = 0
        var mutex: OpaquePointer = SDL_CreateMutex()
        var cond: OpaquePointer = SDL_CreateCond()
    }
    
    static var audioq: PacketQueue = PacketQueue()
    
    static var quit: Bool = false
    
    var paths: [String]
    
    init(paths: [String]) {
        self.paths = paths
    }
    
    func put(q: UnsafeMutablePointer<PacketQueue>?, pkt: UnsafeMutablePointer<AVPacket>?) -> Int32 {
        print(#function)
        var pktl: UnsafeMutablePointer<AVPacketList>? = nil
        if nil == pkt || nil == pkt?.pointee.data {
            guard av_success(av_packet_ref(pkt, av_packet_alloc())) else {
                return -1
            }
        }
        
        pktl = av_mallocz(MemoryLayout<AVPacketList>.stride).assumingMemoryBound(to: AVPacketList.self)
        guard let _ = pktl else {
            return -1
        }
        
        pktl?.pointee.pkt = pkt!.pointee
        pktl?.pointee.next = nil
        
        SDL_LockMutex(q?.pointee.mutex)
        
        if nil == q?.pointee.last_pkt {
            q?.pointee.first_pkt = pktl
        } else {
            q?.pointee.last_pkt?.pointee.next = pktl
        }
        
        q?.pointee.last_pkt = pktl
        q?.pointee.nb_packets += 1
        q?.pointee.size += pktl?.pointee.pkt.size ?? 0
        
        SDL_CondSignal(q?.pointee.cond)
        
        SDL_UnlockMutex(q?.pointee.mutex)
        return 0
    }
    
    static func get(q: UnsafeMutablePointer<PacketQueue>?, pkt: UnsafeMutablePointer<AVPacket>, block: Int32) -> Int32 {
        print(#function)
        var pktl: UnsafeMutablePointer<AVPacketList>? = nil
        var ret: Int32 = 0
        
        SDL_LockMutex(q?.pointee.mutex)
        
        while true {
            if Tutorial3.quit {
                ret = -1
                break
            }
            
            pktl = q?.pointee.first_pkt
            
            if nil != pktl {
                q?.pointee.first_pkt = pktl?.pointee.next
                if nil == q?.pointee.first_pkt {
                    q?.pointee.last_pkt = nil
                }
                q?.pointee.nb_packets -= 1
                q?.pointee.size = pktl?.pointee.pkt.size ?? 0
                
                pkt.pointee = pktl?.pointee.pkt ?? AVPacket()
                av_free(pktl)
                ret = 1
                break
            } else if 0 != block {
                ret = 0
                break
            } else {
                SDL_CondWait(q?.pointee.cond, q?.pointee.mutex)
            }
        }
        SDL_UnlockMutex(q?.pointee.mutex)
        
        return ret
    }
    
    static var pkt = av_packet_alloc()!
    static var audio_pkt_data: UnsafeMutablePointer<UInt8>? = nil
    static var audio_pkt_size: Int32 = 0
    static var frame = av_frame_alloc()!
    
    
    static func audio_decode_frame(aCodecCtx: UnsafeMutablePointer<AVCodecContext>, audio_buf: UnsafeMutablePointer<UInt8>, buf_size: Int32) -> Int32 {
        
        var len1: Int32 = 0, data_size: Int32 = 0
        
        while true {
            while 0 < audio_pkt_size {
                var got_frame: Int32 = 0
                len1 = decode_codec(aCodecCtx, stream: Tutorial3.audio_stream, packet: pkt, frame: frame).packet_size
                got_frame = 0 < len1 ? 1 : 0
                print(#function + " -> \(len1)")
                if 0 > len1 {
                    audio_pkt_size = 0
                    break
                }
                audio_pkt_data = audio_pkt_data?.advanced(by: Int(len1))
                audio_pkt_size += len1
                if 0 < got_frame {
                    data_size = av_samples_get_buffer_size(nil, aCodecCtx.pointee.channels, frame.pointee.nb_samples, aCodecCtx.pointee.sample_fmt, 1)
                    memcpy(audio_buf, frame.pointee.data.0, data_size.cast())
                }
                if 0 >= data_size {
                    continue
                }
                return data_size
            }
            
            if nil != self.pkt.pointee.data {
                av_packet_unref(pkt)
            }
            if Tutorial3.quit {
                return -1
            }
            
            guard av_success(self.get(q: &Tutorial3.audioq, pkt: Tutorial3.pkt, block: 1)) else {
                return -1
            }
            
            audio_pkt_data = pkt.pointee.data
            audio_pkt_size = pkt.pointee.size
            
        }
    }
    
    static var audio_buf: [UInt8] = [UInt8](repeating: 0, count: MAX_AUDIO_FRAME_SIZE.cast() * 3 / 2)
    static var audio_buf_ptr = audio_buf.withUnsafeMutableBufferPointer(){$0}
    static var audio_buf_size: UInt32 = 0
    static var audio_buf_index: UInt32 = 0
    static var audio_callback: SDL_AudioCallback = { userdata, stream, len in
        print(#function)
        var aCodecCtx: UnsafeMutablePointer<AVCodecContext> = userdata!.cast(to: AVCodecContext.self)
        var len1: Int32 = 0, audio_size: Int32 = 0
        var len = len
        var stream: UnsafeMutablePointer<UInt8>? = stream
        while len > 0 {
            if Tutorial3.audio_buf_index >= Tutorial3.audio_buf_size {
                audio_size = Tutorial3.audio_decode_frame(aCodecCtx: aCodecCtx, audio_buf: Tutorial3.audio_buf_ptr.baseAddress!, buf_size: Int32(Tutorial3.audio_buf_size))
                if 0 > audio_size {
                    Tutorial3.audio_buf_size = 1024
                    memset(&Tutorial3.audio_buf, 0, Int(Tutorial3.audio_buf_size))
                } else {
                    Tutorial3.audio_buf_size = audio_size.cast()
                }
                Tutorial3.audio_buf_index = 0
            }
            len1 = Tutorial3.audio_buf_size.cast() - Tutorial3.audio_buf_index.cast()
            if len1 > len {
                len1 = len
            }
            var src = audio_buf_ptr.baseAddress?.advanced(by: Tutorial3.audio_buf_index.cast())
            memcpy(stream, src, len1.cast())
            
        }
        len -= len1
        stream = stream?.advanced(by: Int(len1))
        Tutorial3.audio_buf_index += len1.cast()
    }
    
    static var audio_stream: UnsafeMutablePointer<AVStream>!
    
    func run() {
        var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        var i: Int32 = 0, videoStream: Int32 = -1, audioStream: Int32 = -1
        var pCodecCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var pCodec: UnsafeMutablePointer<AVCodec>? = nil
        var pFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        var packet: AVPacket = AVPacket()
        var frameFinished: Int32 = 0
        
        var aCodecCtx: UnsafeMutablePointer<AVCodecContext>? = nil
        var aCodec: UnsafeMutablePointer<AVCodec>? = nil
        
        var window: OpaquePointer? = nil
        var texture: OpaquePointer? = nil
        var renderer: OpaquePointer? = nil
        var event: SDL_Event = SDL_Event()
        var wanted_spec: SDL_AudioSpec = SDL_AudioSpec(), spec: SDL_AudioSpec = SDL_AudioSpec()
        
        SDL_SetMainReady()
        
        guard sdl_success(SDL_Init(SDL_INIT_VIDEO.cast() | SDL_INIT_AUDIO.cast() | SDL_INIT_TIMER.cast())) else {
            return
        }
        
        // 파일 오픈
        guard av_success(avformat_open_input(&pFormatCtx, self.path, nil, nil)) else {
            return
        }
        
        defer {
            avformat_close_input(&pFormatCtx)
        }
        
        // 스트림 정보 파싱
        guard av_success(avformat_find_stream_info(pFormatCtx, nil)) else {
            return
        }
        
        // 코덱 정보 출력
        av_dump_format(pFormatCtx, -1, self.path, 0)
        
        for i in 0..<(pFormatCtx?.pointee.nb_streams ?? 0) {
            guard let st = pFormatCtx?.pointee.streams[Int(i)] else {
                break
            }
            // 디코터 검색
            guard let codec = avcodec_find_decoder(st.pointee.codecpar.pointee.codec_id) else {
                break
            }
            // 컨텍스트 생성
            guard let context = avcodec_alloc_context3(codec) else {
                break
            }
            // 컨텍스트 파라미터를 컨텍스트로 복사
            guard av_success(avcodec_parameters_to_context(context, st.pointee.codecpar)) else {
                break
            }
            switch st.pointee.codecpar.pointee.codec_type {
            case AVMEDIA_TYPE_VIDEO:
                videoStream = i.cast()
                pCodec = codec
                pCodecCtx = context
                guard av_success(avcodec_open2(context, codec, nil)) else {
                    return
                }
            case AVMEDIA_TYPE_AUDIO:
                Tutorial3.audio_stream = st
                audioStream = i.cast()
                aCodec = codec
                aCodecCtx = context
                aCodecCtx?.pointee.request_sample_fmt = AV_SAMPLE_FMT_S16
                
                // 디코더 열기
                guard av_success(avcodec_open2(aCodecCtx, codec, nil)) else {
                    return
                }
            default:
                break
            }
        }
        
        if let aCodecCtx = aCodecCtx {
            wanted_spec.channels = aCodecCtx.pointee.channels.cast()
            wanted_spec.format = AUDIO_S16SYS.cast()
            wanted_spec.freq = aCodecCtx.pointee.sample_rate
            wanted_spec.silence = 0
            wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE.cast()
            wanted_spec.callback = Tutorial3.audio_callback
            wanted_spec.userdata = aCodecCtx.castRaw(from: AVCodecContext.self)
        }
        
        guard sdl_success(SDL_OpenAudio(&wanted_spec, &spec)) else{
            return
        }
        SDL_PauseAudio(0)
        
        if let vctx = pCodecCtx {
            window = SDL_CreateWindow("tutorial3", 0, 0, vctx.pointee.width, vctx.pointee.height, SDL_WINDOW_BORDERLESS.rawValue | SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_OPENGL.rawValue)
            renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue.cast() | SDL_RENDERER_TARGETTEXTURE.rawValue.cast())
            texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_IYUV.cast(), SDL_TEXTUREACCESS_STREAMING.rawValue.cast(), vctx.pointee.width, vctx.pointee.height)
        }
        
        i = 0
        
        let w: Int32 = pCodecCtx?.pointee.width ?? 0, h: Int32 = pCodecCtx?.pointee.height ?? 0
        var rect = SDL_Rect(x: 0, y: 0, w: w, h: h)
        var dst_rect: SDL_Rect = SDL_Rect()
        let fit_rect: CGRect = AVMakeRect(aspectRatio: CGSize(width: Int(w), height: Int(h)), insideRect: UIScreen.main.bounds)
        dst_rect.x = fit_rect.origin.x.cast()
        dst_rect.y = fit_rect.origin.y.cast()
        dst_rect.w = fit_rect.width.cast()
        dst_rect.h = fit_rect.height.cast()
        
        decode: while 0 <= av_read_frame(pFormatCtx, &packet) {
            if packet.stream_index == videoStream {
                frameFinished = decode_codec(pCodecCtx!, stream: pFormatCtx!.pointee.streams[videoStream.cast()], packet: &packet, frame: pFrame).packet_size
                
                if 0 < frameFinished, let frame = pFrame {
                    SDL_UpdateYUVTexture(texture, &rect, frame.pointee.data.0, frame.pointee.linesize.0, frame.pointee.data.1, frame.pointee.linesize.1, frame.pointee.data.2, frame.pointee.linesize.2)
                    SDL_RenderClear(renderer)
                    SDL_RenderCopy(renderer, texture, &rect, &dst_rect)
                    SDL_RenderPresent(renderer)
                }
            } else if packet.stream_index == audioStream {
                self.put(q: &Tutorial3.audioq, pkt: &packet)
            } else {
                av_packet_unref(&packet)
            }
            
            SDL_PollEvent(&event)
            switch SDL_EventType(rawValue: event.type) {
            case SDL_QUIT, SDL_FINGERDOWN:
                Tutorial3.quit = true
                SDL_Quit()
                break decode
            default:
                break
            }
        }
        
        av_frame_free(&pFrame)
        
        avcodec_close(pCodecCtx)
    }
}

//
//  TutorialObjcC.m
//  tutorial
//
//  Created by Kwanghoon Choi on 2016. 8. 17..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import "T3.h"

#import <UIKit/UIKit.h>

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <SDL.h>
#import <SDL_thread.h>
#import <SDL_main.h>
#import "FFmpeg.h"
#import <AVFoundation/AVFoundation.h>

#define SDL_AUDIO_BUFFER_SIZE 1024
#define MAX_AUDIO_FRAME_SIZE 192000

typedef struct PacketQueue {
    AVPacketList *first_pkt, *last_pkt;
    int nb_packets;
    int size;
    SDL_mutex *mutex;
    SDL_cond *cond;
} PacketQueue;

PacketQueue audioq;

int quit = 0;

void packet_queue_init(PacketQueue *q) {
    memset(q, 0, sizeof(PacketQueue));
    q->mutex = SDL_CreateMutex();
    q->cond = SDL_CreateCond();
}

int packet_queue_put(PacketQueue *q, AVPacket *pkt) {
    AVPacketList *pkt1;
    
    if (NULL == pkt) {
        if (isErr(av_packet_ref(pkt, av_packet_alloc()), "av_packet_ref")) {
            return -1;
        }
    }
    
    pkt1 = av_malloc(sizeof(AVPacketList));
    if (NULL == pkt1) {
        return -1;
    }
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
    
    SDL_LockMutex(q->mutex);
    
    if (!q->last_pkt) {
        q->first_pkt = pkt1;
    }
    else {
        q->last_pkt->next = pkt1;
    }
    q->last_pkt = pkt1;
    q->nb_packets++;
    q->size += pkt1->pkt.size;
    SDL_CondSignal(q->cond);
    SDL_UnlockMutex(q->mutex);
    return 0;
}

static int packet_queue_get(PacketQueue *q, AVPacket *pkt, int block) {
    AVPacketList *pkt1;
    int ret;
    
    SDL_LockMutex(q->mutex);
    
    while (true) {
        if(quit) {
            ret = -1;
            break;
        }
        
        pkt1 = q->first_pkt;
        if (pkt1) {
            q->first_pkt = pkt1->next;
            if (NULL == q->first_pkt) {
                q->last_pkt = NULL;
            }
            q->nb_packets -= 1;
            q->size -= pkt1->pkt.size;
            *pkt = pkt1->pkt;
            av_free(pkt1);
            ret = 1;
            break;
        }
        else if (0 == block) {
            ret = 0;
            break;
        }
        else {
            SDL_CondWait(q->cond, q->mutex);
        }
    }
    SDL_UnlockMutex(q->mutex);
    return ret;
}

int audio_decode_frame(AVCodecContext *aCodecCtx, uint8_t *audio_buf, int buf_size) {
    static AVPacket pkt;
    static uint8_t *audio_pkt_data = NULL;
    static int audio_pkt_size = 0;
    static AVFrame frame;
    
    int len1, data_size = 0;
    
    for(;;) {
        while(audio_pkt_size > 0) {
            int ret = 0;
            do {
                ret = avcodec_send_packet(aCodecCtx, &pkt);
            } while(ret == AVERROR(EAGAIN));
            if (isErr(ret, "audio send packet")) {
                break;
            }
            do {
                ret  = avcodec_receive_frame(aCodecCtx, &frame);
            } while(ret == AVERROR(EAGAIN));
            if (isErr(ret, "audio receive frame")) {
                break;
            }
            len1 = frame.pkt_size;
            if (0 > len1) {
                audio_pkt_size = 0;
                break;
            }
            audio_pkt_data += len1;
            audio_pkt_size -= len1;
            
            data_size = av_samples_get_buffer_size(NULL, aCodecCtx->channels, frame.nb_samples, aCodecCtx->sample_fmt, 1);
            memcpy(audio_buf, frame.data[0], data_size);
            av_packet_unref(&pkt);
            av_frame_unref(&frame);
            if (data_size <= 0) {
                continue;
            }
            return data_size;
        }
        if (pkt.data) {
            av_packet_unref(&pkt);
        }
        if (quit) {
            return -1;
        }
        
        if (packet_queue_get(&audioq, &pkt, 1) < 0) {
            return -1;
        }
        audio_pkt_data = pkt.data;
        audio_pkt_size = pkt.size;
    }
}

void audio_callback(void *userdata, UInt8 *stream, int len) {
    AVCodecContext *aCodecCtx = (AVCodecContext *)userdata;
    int len1, audio_size;
    
    static uint8_t audio_buf[(MAX_AUDIO_FRAME_SIZE * 3) / 2];
    static unsigned int audio_buf_size = 0;
    static unsigned int audio_buf_index = 0;
    
    while (len > 0) {
        if (audio_buf_index >= audio_buf_size) {
            audio_size = audio_decode_frame(aCodecCtx, audio_buf, audio_buf_size);
            if (0 > audio_size) {
                audio_buf_size = 1024;
                memset(audio_buf, 0, audio_buf_size);
            }
            else {
                audio_buf_size = audio_size;
            }
            audio_buf_index = 0;
        }
        len1 = audio_buf_size - audio_buf_index;
        if (len1 > len) {
            len1 = len;
        }
        SDL_MixAudio(stream, (uint8_t *)audio_buf + audio_buf_index, len1, 32);
        len -= len1;
        stream += len1;
        audio_buf_index += len1;
    }
}

@interface T3 ()

@property (nonatomic, strong) NSString *path;

@end

@implementation T3

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        self.path = path;
    }
    return self;
}

- (int)run {
    AVFormatContext *pFormatCtx = NULL;
    int             i, videoStream, audioStream;
    AVCodecContext  *pCodecCtx = NULL;
    AVCodec         *pCodec = NULL;
    
    AVCodecParameters *aCodecPar = NULL;
    AVCodecContext  *aCodecCtx = NULL;
    AVCodec         *aCodec = NULL;
    
    SDL_Window      *window = NULL;
    SDL_Texture     *texture = NULL;
    SDL_Renderer    *renderer = NULL;
    
    SDL_Rect        rect;
    SDL_Rect        dst_rect;
    SDL_Event       event;
    SDL_AudioSpec   wanted_spec, spec;
    
    AVDictionary        *videoOptionsDict   = NULL;
    AVDictionary        *audioOptionsDict   = NULL;
    
    // Register all formats and codecs
    av_register_all();
    
    SDL_SetMainReady();
    
    if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) {
        fprintf(stderr, "Could not initialize SDL - %s\n", SDL_GetError());
        exit(1);
    }
    
    // Open video file
    if(avformat_open_input(&pFormatCtx, self.path.UTF8String, NULL, NULL)!=0)
        return -1; // Couldn't open file
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx, NULL)<0)
        return -1; // Couldn't find stream information
    
    // Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, self.path.UTF8String, 0);
    
    // Find the first video stream
    videoStream=-1;
    audioStream=-1;
    for(i=0; i<pFormatCtx->nb_streams; i++) {
        if(pFormatCtx->streams[i]->codecpar->codec_type==AVMEDIA_TYPE_VIDEO &&
           videoStream < 0) {
            videoStream=i;
        }
        if(pFormatCtx->streams[i]->codecpar->codec_type==AVMEDIA_TYPE_AUDIO &&
           audioStream < 0) {
            audioStream=i;
        }
    }
    if(videoStream==-1)
        return -1; // Didn't find a video stream
    if(audioStream==-1)
        return -1;
    
    aCodecPar = pFormatCtx->streams[audioStream]->codecpar;
    
    aCodec = avcodec_find_decoder(aCodecPar->codec_id);
    if(!aCodec) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    aCodecCtx = avcodec_alloc_context3(aCodec);
    avcodec_parameters_to_context(aCodecCtx, aCodecPar);
    
    if(isErr(avcodec_open2(aCodecCtx, aCodec, &audioOptionsDict), "open audio codec")) {
        return -1;
    }
    
    // Set audio settings from codec info
    wanted_spec.freq = aCodecPar->sample_rate;
    wanted_spec.format = AUDIO_S16SYS;
    wanted_spec.channels = aCodecPar->channels;
    wanted_spec.silence = 0;
    wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE;
    wanted_spec.callback = audio_callback;
    wanted_spec.userdata = aCodecCtx;
    
    // audio_st = pFormatCtx->streams[index]
    
    packet_queue_init(&audioq);
    
    if(SDL_OpenAudio(&wanted_spec, &spec) < 0) {
        fprintf(stderr, "SDL_OpenAudio: %s\n", SDL_GetError());
    }
    SDL_PauseAudio(0);
    
    // Get a pointer to the codec context for the video stream
    
    // Find the decoder for the video stream
    pCodec=avcodec_find_decoder(pFormatCtx->streams[videoStream]->codecpar->codec_id);
    if(pCodec==NULL) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1; // Codec not found
    }
    
    pCodecCtx = avcodec_alloc_context3(pCodec);
    avcodec_parameters_to_context(pCodecCtx, pFormatCtx->streams[videoStream]->codecpar);
    
    // Open codec
    if(avcodec_open2(pCodecCtx, pCodec, &videoOptionsDict)<0)
        return -1; // Could not open codec
    
    // Make a screen to put our video
    window = SDL_CreateWindow("Tutorial3", 0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height, SDL_WINDOW_SHOWN | SDL_WINDOW_OPENGL | SDL_WINDOW_BORDERLESS);
    if (NULL == window) {
        NSLog(@"Couldn't create sdl window.");
        return -1;
    }
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_TARGETTEXTURE | SDL_RENDERER_ACCELERATED);
    texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_IYUV, SDL_TEXTUREACCESS_STREAMING, pCodecCtx->width, pCodecCtx->height);
    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_NONE);
    
    rect.x = 0;
    rect.y = 0;
    rect.w = pCodecCtx->width;
    rect.h = pCodecCtx->height;
    CGRect dstRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(rect.w, rect.h), [UIScreen mainScreen].bounds);
    dst_rect.x = dstRect.origin.x;
    dst_rect.y = dstRect.origin.y;
    dst_rect.w = dstRect.size.width;
    dst_rect.h = dstRect.size.height;
    
    i=0;
    int reads = 0;
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    while (0 <= av_read_frame(pFormatCtx, packet)) {
        if (packet->stream_index == videoStream) {
            do {
                reads = avcodec_send_packet(pCodecCtx, packet);
            } while (reads == AVERROR(EAGAIN));
            if (isErr(reads, "send paket")) {
                av_packet_unref(packet);
                break;
            }
            do {
                reads = avcodec_receive_frame(pCodecCtx, frame);
            } while (reads == AVERROR(EAGAIN));
            if (isErr(reads, "receive frame")) {
                av_packet_unref(packet);
                av_frame_unref(frame);
                break;
            }
            SDL_UpdateYUVTexture(texture, &rect, frame->data[0], frame->linesize[0], frame->data[1], frame->linesize[1], frame->data[2], frame->linesize[2]);
            SDL_RenderClear(renderer);
            SDL_RenderCopy(renderer, texture, &rect, &dst_rect);
            SDL_RenderPresent(renderer);
            
            av_packet_unref(packet);
            av_frame_unref(frame);
        }
        else if(packet->stream_index == audioStream) {
            packet_queue_put(&audioq, packet);
        }
        else {
            av_packet_unref(packet);
        }
        
        SDL_PollEvent(&event);
        switch (event.type) {
            case SDL_QUIT:
            case SDL_FINGERDOWN:
                quit = 1;
                goto end;
                break;
                
            default:
                break;
        }
    }
    
end:
    av_packet_free(&packet);
    av_frame_free(&frame);
    
    isErr(reads, "loop finished");
    
    // Close the codec
    avcodec_close(pCodecCtx);
    
    // Close the video file
    avformat_close_input(&pFormatCtx);
    SDL_PauseAudio(1);
    
    SDL_DestroyTexture(texture);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    
    SDL_Quit();
    
    return 0;
}

@end

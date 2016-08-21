//
//  Tutorial4c.m
//  tutorial
//
//  Created by Kwanghoon Choi on 2016. 8. 20..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import "Tutorial4c.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libswscale/swscale.h>
#include <libavutil/avstring.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

#include <SDL.h>
#include <SDL_thread.h>
#include <math.h>

#define SDL_AUDIO_BUFFER_SIZE 1024
#define MAX_AUDIO_FRAME_SIZE 192000

#define MAX_AUDIOQ_SIZE (5 * 16 * 1024)
#define MAX_VIDEOQ_SIZE (5 * 256 * 1024)

#define FF_REFRESH_EVENT (SDL_USEREVENT)
#define FF_QUIT_EVENT (SDL_USEREVENT + 1)

#define VIDEO_PICTURE_QUEUE_SIZE 1
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio

typedef struct PacketQueue {
    AVPacketList *first_pkt, *last_pkt;
    int nb_packets;
    int size;
    SDL_mutex *mutex;
    SDL_cond *cond;
} PacketQueue;


typedef struct VideoPicture {
    /* SDL_Overlay *bmp; */
    SDL_Texture *texture;
    int width, height; /* source height & width */
    int allocated;
} VideoPicture;

typedef struct VideoState {
    
    AVFormatContext *pFormatCtx;
    int             videoStream, audioStream;
    AVStream        *audio_st;
    AVCodecContext  *audio_ctx;
    PacketQueue     audioq;
    uint8_t         audio_buf[(AVCODEC_MAX_AUDIO_FRAME_SIZE * 3) / 2];
    unsigned int    audio_buf_size;
    unsigned int    audio_buf_index;
    AVFrame         audio_frame;
    AVPacket        audio_pkt;
    uint8_t         *audio_pkt_data;
    int             audio_pkt_size;
    AVStream        *video_st;
    AVCodecContext  *video_ctx;
    PacketQueue     videoq;
    
    VideoPicture    pictq[VIDEO_PICTURE_QUEUE_SIZE];
    int             pictq_size, pictq_rindex, pictq_windex;
    SDL_mutex       *pictq_mutex;
    SDL_cond        *pictq_cond;
    
    SDL_Thread      *parse_tid;
    SDL_Thread      *video_tid;
    
    char            filename[1024];
    int             quit;
} VideoState;

/* SDL_Surface     *screen; */
SDL_Window *screen = NULL;
SDL_mutex       *screen_mutex;
SDL_Renderer *renderer = NULL;
SDL_Rect    screenRect;

/* Since we only have one decoding thread, the Big Struct
 can be global in case we need it. */
VideoState *global_video_state;

void packet_queue_init(PacketQueue *q) {
    memset(q, 0, sizeof(PacketQueue));
    q->mutex = SDL_CreateMutex();
    q->cond = SDL_CreateCond();
}
int packet_queue_put(PacketQueue *q, AVPacket *pkt) {
    
    AVPacketList *pkt1;
    if(nil == pkt && nil == pkt->data && av_packet_ref(pkt, av_packet_alloc()) < 0) {
        return -1;
    }
    pkt1 = av_malloc(sizeof(AVPacketList));
    if (!pkt1)
        return -1;
    pkt1->pkt = *pkt;
    pkt1->next = NULL;
    
    SDL_LockMutex(q->mutex);
    
    if (!q->last_pkt)
        q->first_pkt = pkt1;
    else
        q->last_pkt->next = pkt1;
    q->last_pkt = pkt1;
    q->nb_packets++;
    q->size += pkt1->pkt.size;
    SDL_CondSignal(q->cond);
    
    SDL_UnlockMutex(q->mutex);
    return 0;
}
static int packet_queue_get(PacketQueue *q, AVPacket *pkt, int block)
{
    AVPacketList *pkt1;
    int ret;
    
    SDL_LockMutex(q->mutex);
    
    for(;;) {
        
        if(global_video_state->quit) {
            ret = -1;
            break;
        }
        
        pkt1 = q->first_pkt;
        if (pkt1) {
            q->first_pkt = pkt1->next;
            if (!q->first_pkt)
                q->last_pkt = NULL;
            q->nb_packets--;
            q->size -= pkt1->pkt.size;
            *pkt = pkt1->pkt;
            av_free(pkt1);
            ret = 1;
            break;
        } else if (!block) {
            ret = 0;
            break;
        } else {
            SDL_CondWait(q->cond, q->mutex);
        }
    }
    SDL_UnlockMutex(q->mutex);
    return ret;
}

static int audio_resampling(AVCodecContext *audio_decode_ctx,
                            AVFrame *audio_decode_frame,
                            enum AVSampleFormat out_sample_fmt,
                            int out_channels,
                            int out_sample_rate,
                            uint8_t *out_buf)
{
    SwrContext *swr_ctx = NULL;
    int ret = 0;
    int64_t in_channel_layout = audio_decode_ctx->channel_layout;
    int64_t out_channel_layout = AV_CH_LAYOUT_STEREO;
    int out_nb_channels = 0;
    int out_linesize = 0;
    int in_nb_samples = 0;
    int out_nb_samples = 0;
    int max_out_nb_samples = 0;
    uint8_t **resampled_data = NULL;
    int resampled_data_size = 0;
    
    swr_ctx = swr_alloc();
    if (!swr_ctx) {
        printf("swr_alloc error\n");
        return -1;
    }
    
    in_channel_layout = (audio_decode_ctx->channels ==
                         av_get_channel_layout_nb_channels(audio_decode_ctx->channel_layout)) ?
    audio_decode_ctx->channel_layout :
    av_get_default_channel_layout(audio_decode_ctx->channels);
    if (in_channel_layout <=0) {
        printf("in_channel_layout error\n");
        return -1;
    }
    
    if (out_channels == 1) {
        out_channel_layout = AV_CH_LAYOUT_MONO;
    } else if (out_channels == 2) {
        out_channel_layout = AV_CH_LAYOUT_STEREO;
    } else {
        out_channel_layout = AV_CH_LAYOUT_SURROUND;
    }
    
    in_nb_samples = audio_decode_frame->nb_samples;
    if (in_nb_samples <=0) {
        printf("in_nb_samples error\n");
        return -1;
    }
    
    av_opt_set_int(swr_ctx, "in_channel_layout", in_channel_layout, 0);
    av_opt_set_int(swr_ctx, "in_sample_rate", audio_decode_ctx->sample_rate, 0);
    av_opt_set_sample_fmt(swr_ctx, "in_sample_fmt", audio_decode_ctx->sample_fmt, 0);
    
    av_opt_set_int(swr_ctx, "out_channel_layout", out_channel_layout, 0);
    av_opt_set_int(swr_ctx, "out_sample_rate", out_sample_rate, 0);
    av_opt_set_sample_fmt(swr_ctx, "out_sample_fmt", out_sample_fmt, 0);
    
    if ((ret = swr_init(swr_ctx)) < 0) {
        printf("Failed to initialize the resampling context\n");
        return -1;
    }
    
    max_out_nb_samples = out_nb_samples = av_rescale_rnd(in_nb_samples,
                                                         out_sample_rate,
                                                         audio_decode_ctx->sample_rate,
                                                         AV_ROUND_UP);
    
    if (max_out_nb_samples <= 0) {
        printf("av_rescale_rnd error\n");
        return -1;
    }
    
    out_nb_channels = av_get_channel_layout_nb_channels(out_channel_layout);
    
    ret = av_samples_alloc_array_and_samples(&resampled_data, &out_linesize, out_nb_channels, out_nb_samples, out_sample_fmt, 0);
    if (ret < 0) {
        printf("av_samples_alloc_array_and_samples error\n");
        return -1;
    }
    
    out_nb_samples = av_rescale_rnd(swr_get_delay(swr_ctx, audio_decode_ctx->sample_rate) + in_nb_samples,
                                    out_sample_rate, audio_decode_ctx->sample_rate, AV_ROUND_UP);
    if (out_nb_samples <= 0) {
        printf("av_rescale_rnd error\n");
        return -1;
    }
    
    if (out_nb_samples > max_out_nb_samples) {
        av_free(resampled_data[0]);
        ret = av_samples_alloc(resampled_data, &out_linesize, out_nb_channels, out_nb_samples, out_sample_fmt, 1);
        max_out_nb_samples = out_nb_samples;
    }
    
    if (swr_ctx) {
        ret = swr_convert(swr_ctx, resampled_data, out_nb_samples,
                          (const uint8_t **)audio_decode_frame->data, audio_decode_frame->nb_samples);
        if (ret < 0) {
            printf("swr_convert_error\n");
            return -1;
        }
        
        resampled_data_size = av_samples_get_buffer_size(&out_linesize, out_nb_channels, ret, out_sample_fmt, 1);
        if (resampled_data_size < 0) {
            printf("av_samples_get_buffer_size error\n");
            return -1;
        }
    } else {
        printf("swr_ctx null error\n");
        return -1;
    }
    
    memcpy(out_buf, resampled_data[0], resampled_data_size);
    
    if (resampled_data) {
        av_freep(&resampled_data[0]);
    }
    av_freep(&resampled_data);
    resampled_data = NULL;
    
    if (swr_ctx) {
        swr_free(&swr_ctx);
    }
    return resampled_data_size;
}


int audio_decode_frame(VideoState *is, uint8_t *audio_buf, int buf_size) {
    
    int len1, data_size = 0;
    AVPacket *pkt = &is->audio_pkt;
    
    for(;;) {
        while(is->audio_pkt_size > 0) {
            int got_frame = 0;
            int ret = 0;
            while ((0 < pkt->size || (nil == pkt->data && got_frame)) && 0 <= ret) {
                got_frame = 0;
                ret = avcodec_send_packet(is->audio_ctx, pkt);
                if (ret < 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                    break;
                }
                if (ret >= 0) {
                    pkt->size = 0;
                }
                ret = avcodec_receive_frame(is->audio_ctx, &is->audio_frame);
                if (0 <= ret) {
                    got_frame = 1;
                }
                if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                    ret = 0;
                }
            }
            if (0 <= ret && got_frame) {
                is->audio_st->nb_decoded_frames += 1;
            }
            len1 = is->audio_frame.pkt_size;
            if(len1 < 0) {
                /* if error, skip frame */
                is->audio_pkt_size = 0;
                break;
            }
            data_size = 0;
            if(got_frame) {
                data_size = audio_resampling(is->audio_ctx, &is->audio_frame, AV_SAMPLE_FMT_S16, is->audio_frame.channels, is->audio_frame.sample_rate, audio_buf);
                assert(data_size <= buf_size);
                /* data_size = av_samples_get_buffer_size(NULL, */
                /* is->audio_ctx->channels, */
                /* is->audio_frame.nb_samples, */
                /* is->audio_ctx->sample_fmt, */
                /* 1); */
                /* assert(data_size <= buf_size); */
                /* memcpy(audio_buf, is->audio_frame.data[0], data_size); */
            }
            is->audio_pkt_data += len1;
            is->audio_pkt_size -= len1;
            if(data_size <= 0) {
                /* No data yet, get more frames */
                continue;
            }
            /* We have data, return it and come back for more later */
            return data_size;
        }
        if(pkt->data)
            av_free_packet(pkt);
        
        if(is->quit) {
            return -1;
        }
        /* next packet */
        if(packet_queue_get(&is->audioq, pkt, 1) < 0) {
            return -1;
        }
        is->audio_pkt_data = pkt->data;
        is->audio_pkt_size = pkt->size;
    }
}

void audio_callback(void *userdata, Uint8 *stream, int len) {
    
    VideoState *is = (VideoState *)userdata;
    int len1, audio_size;
    
    while(len > 0) {
        if(is->audio_buf_index >= is->audio_buf_size) {
            /* We have already sent all our data; get more */
            audio_size = audio_decode_frame(is, is->audio_buf, sizeof(is->audio_buf));
            if(audio_size < 0) {
                /* If error, output silence */
                is->audio_buf_size = 1024;
                memset(is->audio_buf, 0, is->audio_buf_size);
            } else {
                is->audio_buf_size = audio_size;
            }
            is->audio_buf_index = 0;
        }
        len1 = is->audio_buf_size - is->audio_buf_index;
        if(len1 > len)
            len1 = len;
        memcpy(stream, (uint8_t *)is->audio_buf + is->audio_buf_index, len1);
        len -= len1;
        stream += len1;
        is->audio_buf_index += len1;
    }
}

static Uint32 sdl_refresh_timer_cb(Uint32 interval, void *opaque) {
    SDL_Event event;
    event.type = FF_REFRESH_EVENT;
    event.user.data1 = opaque;
    SDL_PushEvent(&event);
    return 0; /* 0 means stop timer */
}

/* schedule a video refresh in 'delay' ms */
static void schedule_refresh(VideoState *is, int delay) {
    SDL_AddTimer(delay, sdl_refresh_timer_cb, is);
}

void video_display(VideoState *is) {
    
    VideoPicture *vp;
    
    vp = &is->pictq[is->pictq_rindex];
    /* if(vp->bmp) { */
    if(vp->texture) {
        CGRect dst = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(vp->width, vp->height), [UIScreen mainScreen].bounds);
        SDL_Rect rect = {.x = dst.origin.x, .y = dst.origin.y, .w = dst.size.width, .h = dst.size.height};
        SDL_Rect src = {0, 0, vp->width, vp->height};
        
        SDL_LockMutex(screen_mutex);
        SDL_RenderClear(renderer);
        SDL_RenderCopy(renderer, vp->texture, &src, &rect);
        SDL_RenderPresent(renderer);
        SDL_UnlockMutex(screen_mutex);
        
    }
}

void video_refresh_timer(void *userdata) {
    
    VideoState *is = (VideoState *)userdata;
    VideoPicture *vp;
    
    if(is->video_st) {
        if(is->pictq_size == 0) {
            schedule_refresh(is, 1);
        } else {
            vp = &is->pictq[is->pictq_rindex];
            /* Now, normally here goes a ton of code
             about timing, etc. we're just going to
             guess at a delay for now. You can
             increase and decrease this value and hard code
             the timing - but I don't suggest that ;)
             We'll learn how to do it for real later.
             */
            schedule_refresh(is, 40);
            
            /* show the picture! */
            video_display(is);
            
            /* update queue for next picture! */
            if(++is->pictq_rindex == VIDEO_PICTURE_QUEUE_SIZE) {
                is->pictq_rindex = 0;
            }
            SDL_LockMutex(is->pictq_mutex);
            is->pictq_size--;
            SDL_CondSignal(is->pictq_cond);
            SDL_UnlockMutex(is->pictq_mutex);
        }
    } else {
        schedule_refresh(is, 100);
    }
}

void alloc_picture(void *userdata) {
    
    VideoState *is = (VideoState *)userdata;
    VideoPicture *vp;
    
    vp = &is->pictq[is->pictq_windex];
    if(vp->texture) {
        // we already have one make another, bigger/smaller
        /* SDL_FreeYUVOverlay(vp->bmp); */
        SDL_DestroyTexture(vp->texture);
    }
    // Allocate a place to put our YUV image on that screen
    SDL_LockMutex(screen_mutex);
    
    
    vp->texture = SDL_CreateTexture(
                                    renderer,
                                    SDL_PIXELFORMAT_YV12,
                                    SDL_TEXTUREACCESS_STREAMING,
                                    /* is->video_ctx->width, */
                                    is->video_ctx->width,
                                    /* is->video_ctx->height */
                                    is->video_ctx->height
                                    );

    SDL_UnlockMutex(screen_mutex);
    
    vp->width = is->video_ctx->width;
    vp->height = is->video_ctx->height;
    vp->allocated = 1;
    
}

int queue_picture(VideoState *is, AVFrame *pFrame) {
    
    VideoPicture *vp;
    int dst_pix_fmt;
    AVPicture pict;
    
    /* wait until we have space for a new pic */
    SDL_LockMutex(is->pictq_mutex);
    while(is->pictq_size >= VIDEO_PICTURE_QUEUE_SIZE &&
          !is->quit) {
        SDL_CondWait(is->pictq_cond, is->pictq_mutex);
    }
    SDL_UnlockMutex(is->pictq_mutex);
    
    if(is->quit)
        return -1;
    
    // windex is set to 0 initially
    vp = &is->pictq[is->pictq_windex];
    
    /* allocate or resize the buffer! */
    if(!vp->texture||
       vp->width != is->video_ctx->width ||
       vp->height != is->video_ctx->height) {
        SDL_Event event;
        
        vp->allocated = 0;
        alloc_picture(is);
        if(is->quit) {
            return -1;
        }
    }
    
    /* We have a place to put our picture on the queue */
    
    /* if(vp->bmp) { */
    if(vp->texture) {
        
        /* SDL_LockYUVOverlay(vp->bmp); */
        SDL_Rect rect = {0, 0, vp->width, vp->height};
        SDL_UpdateYUVTexture(vp->texture, &rect, pFrame->data[0], pFrame->linesize[0], pFrame->data[1], pFrame->linesize[1], pFrame->data[2], pFrame->linesize[2]);
        
        /* SDL_UnlockYUVOverlay(vp->bmp); */
        /* now we inform our display thread that we have a pic ready */
        if(++is->pictq_windex == VIDEO_PICTURE_QUEUE_SIZE) {
            is->pictq_windex = 0;
        }
        SDL_LockMutex(is->pictq_mutex);
        is->pictq_size++;
        SDL_UnlockMutex(is->pictq_mutex);
    }
    return 0;
}

int video_thread(void *arg) {
    VideoState *is = (VideoState *)arg;
    AVPacket pkt1, *packet = &pkt1;
    int frameFinished;
    AVFrame *pFrame;
    
    pFrame = av_frame_alloc();
    
    for(;;) {
        if(packet_queue_get(&is->videoq, packet, 1) < 0) {
            // means we quit getting packets
            break;
        }
        // Decode video frame
        avcodec_decode_video2(is->video_ctx, pFrame, &frameFinished, packet);
        // Did we get a video frame?
        if(frameFinished) {
            if(queue_picture(is, pFrame) < 0) {
                break;
            }
        }
        av_free_packet(packet);
    }
    av_frame_free(&pFrame);
    return 0;
}

int stream_component_open(VideoState *is, int stream_index) {
    
    AVFormatContext *pFormatCtx = is->pFormatCtx;
    AVCodecContext *codecCtx = NULL;
    AVCodec *codec = NULL;
    SDL_AudioSpec wanted_spec, spec;
    
    if(stream_index < 0 || stream_index >= pFormatCtx->nb_streams) {
        return -1;
    }
    
    codec = avcodec_find_decoder(pFormatCtx->streams[stream_index]->codec->codec_id);
    if(!codec) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    
    codecCtx = avcodec_alloc_context3(codec);
    if(avcodec_copy_context(codecCtx, pFormatCtx->streams[stream_index]->codec) != 0) {
        fprintf(stderr, "Couldn't copy codec context");
        return -1; // Error copying codec context
    }
    
    if(codecCtx->codec_type == AVMEDIA_TYPE_AUDIO) {
        // Set audio settings from codec info
        wanted_spec.freq = codecCtx->sample_rate;
        wanted_spec.format = AUDIO_S16SYS;
        wanted_spec.channels = codecCtx->channels;
        wanted_spec.silence = 0;
        wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE;
        wanted_spec.callback = audio_callback;
        wanted_spec.userdata = is;
        
        if(SDL_OpenAudio(&wanted_spec, &spec) < 0) {
            fprintf(stderr, "SDL_OpenAudio: %s\n", SDL_GetError());
            return -1;
        }
    }
    if(avcodec_open2(codecCtx, codec, NULL) < 0) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    
    switch(codecCtx->codec_type) {
        case AVMEDIA_TYPE_AUDIO:
            is->audioStream = stream_index;
            is->audio_st = pFormatCtx->streams[stream_index];
            is->audio_ctx = codecCtx;
            is->audio_buf_size = 0;
            is->audio_buf_index = 0;
            memset(&is->audio_pkt, 0, sizeof(is->audio_pkt));
            packet_queue_init(&is->audioq);
            SDL_PauseAudio(0);
            break;
        case AVMEDIA_TYPE_VIDEO:
            is->videoStream = stream_index;
            is->video_st = pFormatCtx->streams[stream_index];
            is->video_ctx = codecCtx;
            packet_queue_init(&is->videoq);
            is->video_tid = SDL_CreateThread(video_thread, "video_thread", is);
            break;
        default:
            break;
    }
    return 0;
}

int decode_thread(void *arg) {
    
    VideoState *is = (VideoState *)arg;
    AVFormatContext *pFormatCtx = NULL;
    AVPacket pkt1, *packet = &pkt1;
    
    int video_index = -1;
    int audio_index = -1;
    int i;
    
    is->videoStream=-1;
    is->audioStream=-1;
    
    global_video_state = is;
    
    // Open video file
    printf("here!!decode_thread\n");
    printf("is->filename:  %s\n", is->filename);
    if(avformat_open_input(&pFormatCtx, is->filename, NULL, NULL)!=0) {
        printf("avformat_open_input Failed: %s\n", is->filename);
        return -1; // Couldn't open file
    }
    
    is->pFormatCtx = pFormatCtx;
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx, NULL)<0)
        return -1; // Couldn't find stream information
    
    // Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, is->filename, 0);
    
    // Find the first video stream
    
    for(i=0; i<pFormatCtx->nb_streams; i++) {
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO &&
           video_index < 0) {
            video_index=i;
        }
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO &&
           audio_index < 0) {
            audio_index=i;
        }
    }
    if(audio_index >= 0) {
        stream_component_open(is, audio_index);
    }
    if(video_index >= 0) {
        stream_component_open(is, video_index);
    }
    
    if(is->videoStream < 0 || is->audioStream < 0) {
        fprintf(stderr, "%s: could not open codecs\n", is->filename);
        goto fail;
    }
    
    // main decode loop
    
    for(;;) {
        if(is->quit) {
            break;
        }
        // seek stuff goes here
        if(is->audioq.size > MAX_AUDIOQ_SIZE ||
           is->videoq.size > MAX_VIDEOQ_SIZE) {
            SDL_Delay(10);
            continue;
        }
        if(av_read_frame(is->pFormatCtx, packet) < 0) {
            if(is->pFormatCtx->pb->error == 0) {
                SDL_Delay(100); /* no error; wait for user input */
                continue;
            } else {
                break;
            }
        }
        // Is this a packet from the video stream?
        if(packet->stream_index == is->videoStream) {
            packet_queue_put(&is->videoq, packet);
        } else if(packet->stream_index == is->audioStream) {
            packet_queue_put(&is->audioq, packet);
        } else {
            av_free_packet(packet);
        }
    }
    /* all done - wait for it */
    while(!is->quit) {
        SDL_Delay(100);
    }
    
fail:
    if(1){
        SDL_Event event;
        event.type = FF_QUIT_EVENT;
        event.user.data1 = is;
        SDL_PushEvent(&event);
    }
    return 0;
}

@interface Tutorial4c ()

@property (nonatomic, strong) NSString *path;

@end

@implementation Tutorial4c

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        self.path = path;
    }
    return self;
}

- (int)run {
    
    SDL_SetMainReady();
    
    SDL_Event       event;
    
    VideoState      *is;
    
    is = av_mallocz(sizeof(VideoState));
    
    // Register all formats and codecs
    av_register_all();
    
    if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) {
        fprintf(stderr, "Could not initialize SDL - %s\n", SDL_GetError());
        exit(1);
    }
    
    CGSize size = [UIScreen mainScreen].bounds.size;
    
    // Make a screen to put our video
    //
    /* #ifndef __DARWIN__ */
    /* screen = SDL_SetVideoMode(640, 480, 0, 0); */
    /* #else */
    /* screen = SDL_SetVideoMode(640, 480, 24, 0); */
    /* #endif */
    screen = SDL_CreateWindow(
                              "FFmpeg Tutorial",
                              SDL_WINDOWPOS_UNDEFINED,
                              SDL_WINDOWPOS_UNDEFINED,
                              /* 1280, */
                              /* 640, */
                              size.width,
                              /* pCodecCtx->width, */
                              /* 800, */
                              /* 480, */
                              size.height,
                              /* pCodecCtx->height, */
                              0
                              );
    
    screenRect.x = 0;
    screenRect.y = 0;
    screenRect.w = size.width;
    screenRect.h = size.height;
    
    if(!screen) {
        fprintf(stderr, "SDL: could not set video mode - exiting\n");
        exit(1);
    }
    
    renderer = SDL_CreateRenderer(screen, -1, 0);
    if (!renderer) {
        fprintf(stderr, "SDL: could not create renderer - exiting\n");
        exit(1);
    }
    
    screen_mutex = SDL_CreateMutex();
    
    av_strlcpy(is->filename, self.path.UTF8String, sizeof(is->filename));
    printf("is->filename: %s\n", is->filename);
    
    is->pictq_mutex = SDL_CreateMutex();
    is->pictq_cond = SDL_CreateCond();
    
    schedule_refresh(is, 40);
    
    is->parse_tid = SDL_CreateThread(decode_thread, "decode_thread", is);
    if(!is->parse_tid) {
        av_free(is);
        return -1;
    }
    for(;;) {
        
        SDL_WaitEvent(&event);
        switch(event.type) {
            case FF_QUIT_EVENT:
            case SDL_QUIT:
            case SDL_FINGERDOWN:
                is->quit = 1;
                /* SDL_DestroyTexture(texture); */
                SDL_DestroyRenderer(renderer);
                SDL_DestroyWindow(screen);
                SDL_Quit();
                return 0;
                break;
            case FF_REFRESH_EVENT:
                video_refresh_timer(event.user.data1);
                break;
            default:
                break;
        }
    }
    return 0;
}

@end

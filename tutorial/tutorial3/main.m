//
//  main.m
//  tutorial3
//
//  Created by jayios on 2016. 8. 23..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>
#import <SDL2/SDL.h>

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
    if (nil == pkt || nil == pkt->data) {
        if (0 > av_packet_ref(pkt, av_packet_alloc())) {
            return -1;
        }
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
        
        if(quit) {
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

int audio_decode_frame(AVCodecContext *aCodecCtx, uint8_t *audio_buf, int buf_size) {
    
    static AVPacket pkt;
    static uint8_t *audio_pkt_data = NULL;
    static int audio_pkt_size = 0;
    static AVFrame frame;
    
    int len1, data_size = 0;
    
    for(;;) {
        while(audio_pkt_size > 0) {
            //int got_frame = 0;
            decode_frame_with_size(aCodecCtx, &pkt, &frame, &len1);
            //len1 = avcodec_decode_audio4(aCodecCtx, &frame, &got_frame, &pkt);
            if(len1 < 0) {
                /* if error, skip frame */
                audio_pkt_size = 0;
                break;
            }
            audio_pkt_data += len1;
            audio_pkt_size -= len1;
           // if (got_frame)
            //{
                data_size =
                av_samples_get_buffer_size
                (
                 NULL,
                 aCodecCtx->channels,
                 frame.nb_samples,
                 aCodecCtx->sample_fmt,
                 1
                 );
                memcpy(audio_buf, frame.data[0], data_size);
            //}
            if(data_size <= 0) {
                /* No data yet, get more frames */
                continue;
            }
            /* We have data, return it and come back for more later */
            return data_size;
        }
        if(pkt.data)
            av_packet_unref(&pkt);
        
        if(quit) {
            return -1;
        }
        
        if(packet_queue_get(&audioq, &pkt, 1) < 0) {
            return -1;
        }
        audio_pkt_data = pkt.data;
        audio_pkt_size = pkt.size;
    }
}

void audio_callback(void *userdata, Uint8 *stream, int len) {
    
    AVCodecContext *aCodecCtx = (AVCodecContext *)userdata;
    int len1, audio_size;
    
    static uint8_t audio_buf[(MAX_AUDIO_FRAME_SIZE * 3) / 2];
    static unsigned int audio_buf_size = 0;
    static unsigned int audio_buf_index = 0;
    
    while(len > 0) {
        if(audio_buf_index >= audio_buf_size) {
            /* We have already sent all our data; get more */
            audio_size = audio_decode_frame(aCodecCtx, audio_buf, audio_buf_size);
            if(audio_size < 0) {
                /* If error, output silence */
                audio_buf_size = 1024; // arbitrary?
                memset(audio_buf, 0, audio_buf_size);
            } else {
                audio_buf_size = audio_size;
            }
            audio_buf_index = 0;
        }
        len1 = audio_buf_size - audio_buf_index;
        if(len1 > len)
            len1 = len;
        memcpy(stream, (uint8_t *)audio_buf + audio_buf_index, len1);
        len -= len1;
        stream += len1;
        audio_buf_index += len1;
    }
}

int decode_frame_with_size(AVCodecContext *codec, AVPacket *packet, AVFrame *frame, int *pkt_size);

int decode_frame(AVCodecContext *codec, AVPacket *packet, AVFrame *frame) {
    return decode_frame_with_size(codec, packet, frame, NULL);
}

int decode_frame_with_size(AVCodecContext *codec, AVPacket *packet, AVFrame *frame, int *pkt_size) {
    
    int got_picture = 1;
    int ret = 0;
    
    while ((0 < packet->size || (nil == packet->data && got_picture)) && 0 <= ret) {
        got_picture = 0;
        switch (codec->codec_type) {
            case AVMEDIA_TYPE_VIDEO:
            case AVMEDIA_TYPE_AUDIO:
            {
                ret = avcodec_send_packet(codec, packet);
                if (ret > 0 && ret != AVERROR(EAGAIN) && ret != AVERROR_EOF) {
                    break;
                }
                if (0 <= ret) {
                    packet->size = 0;
                }
                ret = avcodec_receive_frame(codec, frame);
                got_picture = 0 <= ret ? 1 : 0;
                if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                    ret = 0;
                }
                if (pkt_size) {
                    *pkt_size = frame->pkt_size;
                }
            }
                break;
            default:
                break;
        }
        if (0 <= ret) {
            if (got_picture) {
                //stream->nb_decoded_frames += 1;
            }
            ret = got_picture;
        }
    }
    
    if (NULL == packet->data && got_picture) {
        return -1;
    }
    
    return ret;
}

int main(int argc, char *argv[]) {
    AVFormatContext *pFormatCtx = NULL;
    int             i, videoStream, audioStream;
    AVCodecContext  *pCodecCtx = NULL;
    AVCodec         *pCodec = NULL;
    AVFrame         *pFrame = NULL;
    AVPacket        packet;
    
    AVCodecContext  *aCodecCtx = NULL;
    AVCodec         *aCodec = NULL;
    
    SDL_Window      *window = NULL;
    SDL_Renderer    *renderer = NULL;
    SDL_Texture     *texture = NULL;
    
    SDL_Rect        rect;
    SDL_Event       event;
    SDL_AudioSpec   wanted_spec, spec;
    
    AVDictionary        *videoOptionsDict   = NULL;
    AVDictionary        *audioOptionsDict   = NULL;
    
    if(argc < 2) {
        fprintf(stderr, "Usage: test <file>\n");
        exit(1);
    }
    // Register all formats and codecs
    av_register_all();
    
    if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) {
        fprintf(stderr, "Could not initialize SDL - %s\n", SDL_GetError());
        exit(1);
    }
    
    // Open video file
    if(avformat_open_input(&pFormatCtx, argv[1], NULL, NULL)!=0)
        return -1; // Couldn't open file
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx, NULL)<0)
        return -1; // Couldn't find stream information
    
    // Dump information about file onto standard error
    av_dump_format(pFormatCtx, 0, argv[1], 0);
    
    // Find the first video stream
    videoStream=-1;
    audioStream=-1;
    for(i=0; i<pFormatCtx->nb_streams; i++) {
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO &&
           videoStream < 0) {
            videoStream=i;
        }
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO &&
           audioStream < 0) {
            audioStream=i;
        }
    }
    if(videoStream==-1)
        return -1; // Didn't find a video stream
    if(audioStream==-1)
        return -1;
    
    aCodecCtx=pFormatCtx->streams[audioStream]->codec;
    // Set audio settings from codec info
    wanted_spec.freq = aCodecCtx->sample_rate;
    wanted_spec.format = AUDIO_S16SYS;
    wanted_spec.channels = aCodecCtx->channels;
    wanted_spec.silence = 0;
    wanted_spec.samples = SDL_AUDIO_BUFFER_SIZE;
    wanted_spec.callback = audio_callback;
    wanted_spec.userdata = aCodecCtx;
    
    if(SDL_OpenAudio(&wanted_spec, &spec) < 0) {
        fprintf(stderr, "SDL_OpenAudio: %s\n", SDL_GetError());
        return -1;
    }
    aCodec = avcodec_find_decoder(aCodecCtx->codec_id);
    if(!aCodec) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1;
    }
    aCodecCtx->request_sample_fmt = AV_SAMPLE_FMT_S16;
    avcodec_open2(aCodecCtx, aCodec, &audioOptionsDict);
    
    // audio_st = pFormatCtx->streams[index]
    packet_queue_init(&audioq);
    SDL_PauseAudio(0);
    
    // Get a pointer to the codec context for the video stream
    pCodecCtx=pFormatCtx->streams[videoStream]->codec;
    
    // Find the decoder for the video stream
    pCodec=avcodec_find_decoder(pCodecCtx->codec_id);
    if(pCodec==NULL) {
        fprintf(stderr, "Unsupported codec!\n");
        return -1; // Codec not found
    }
    // Open codec
    if(avcodec_open2(pCodecCtx, pCodec, &videoOptionsDict)<0)
        return -1; // Could not open codec
    
    // Allocate video frame
    pFrame=av_frame_alloc();
    
    // Make a screen to put our video
    
    window = SDL_CreateWindow("tutorial3", 0, 0, pCodecCtx->width, pCodecCtx->height, SDL_WINDOW_SHOWN | SDL_WINDOW_OPENGL);
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_TARGETTEXTURE);
    texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_IYUV, SDL_TEXTUREACCESS_STREAMING, pCodecCtx->width, pCodecCtx->height);
    
    rect.w = pCodecCtx->width;
    rect.h = pCodecCtx->height;
    
    // Read frames and save first five frames to disk
    i=0;
    while(av_read_frame(pFormatCtx, &packet)>=0) {
        // Is this a packet from the video stream?
        if(packet.stream_index==videoStream) {
            
            // Decode video frame
            int ret = decode_frame(pCodecCtx, &packet, pFrame);
            
            if (0 <= ret) {
                pFormatCtx->streams[videoStream]->nb_decoded_frames += 1;
            }
            
            SDL_UpdateYUVTexture(texture, &rect, pFrame->data[0], pFrame->linesize[0], pFrame->data[1], pFrame->linesize[1], pFrame->data[2], pFrame->linesize[2]);
            SDL_RenderClear(renderer);
            SDL_RenderCopy(renderer, texture, &rect, &rect);
            SDL_RenderPresent(renderer);
            
            av_packet_unref(&packet);
            
        } else if(packet.stream_index==audioStream) {
            packet_queue_put(&audioq, &packet);
        } else {
            av_packet_unref(&packet);
        }
        // Free the packet that was allocated by av_read_frame
        SDL_PollEvent(&event);
        switch(event.type) {
            case SDL_QUIT:
            case SDL_FINGERDOWN:
                quit = 1;
                SDL_Quit();
                exit(0);
                break;
            default:
                break;
        }
        
    }
    
    avcodec_send_packet(pCodecCtx, NULL);
    avcodec_send_packet(aCodecCtx, NULL);
    
    // Free the YUV frame
    av_free(pFrame);
    
    // Close the codec
    avcodec_close(pCodecCtx);
    
    // Close the video file
    avformat_close_input(&pFormatCtx);
    
    return 0;
}

//
//  TutorialObjcC.m
//  tutorial
//
//  Created by Kwanghoon Choi on 2016. 8. 17..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import "TutorialObjcC.h"

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <SDL.h>
#import <SDL_thread.h>
#import "FFmpeg.h"

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
    return 0;
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

@end

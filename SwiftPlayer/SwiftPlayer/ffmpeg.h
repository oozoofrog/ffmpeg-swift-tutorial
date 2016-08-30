//
//  ffmpeg.h
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 29..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

#ifndef ffmpeg_h
#define ffmpeg_h

#include <stdio.h>
#import <libavutil/error.h>
#import <libavutil/channel_layout.h>
#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>

static int INPUT_CHANNEL_LAYOUT = AV_CH_LAYOUT_5POINT0;

void print_err(int ret);
const char * strFromErr(int ret);

int is_eof(int ret);

int err2averr(int ret);

void test(AVCodecContext *avctx, AVRational time_base);
#endif /* ffmpeg_h */

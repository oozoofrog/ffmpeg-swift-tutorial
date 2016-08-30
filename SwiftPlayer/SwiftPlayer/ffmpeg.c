//
//  ffmpeg.c
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 29..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

#include "ffmpeg.h"
#include <libavutil/common.h>

void print_err(int ret) {
    printf("😭 err: %s\n", av_err2str(ret));
}

const char * strFromErr(int ret) {
    return av_err2str(ret);
}

int is_eof(int ret) {
    return ret == AVERROR_EOF;
}

int err2averr(int ret) {
    return AVERROR(ret);
}

void test(AVCodecContext *avctx, AVRational time_base) {
    printf("time_base=%d/%d:sample_rate=%d:sample_fmt=%s:channel_layout=0x%"PRIx64,
           time_base.num, time_base.den, avctx->sample_rate,
           av_get_sample_fmt_name(avctx->sample_fmt),
           avctx->channel_layout);
}

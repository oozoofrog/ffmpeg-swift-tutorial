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

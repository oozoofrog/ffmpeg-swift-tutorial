//
//  main.m
//  tutorial5
//
//  Created by jayios on 2016. 8. 23..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "tutorial5-Swift.h"
#import <AVFoundation/AVFoundation.h>

// tutorial04.c
// A pedagogical video player that will stream through every video frame as fast as it can,
// and play audio (out of sync).
//
// This tutorial was written by Stephen Dranger (dranger@gmail.com).
//
// Code based on FFplay, Copyright (c) 2003 Fabrice Bellard,
// and a tutorial by Martin Bohme (boehme@inb.uni-luebeckREMOVETHIS.de)
// Tested on Gentoo, CVS version 5/01/07 compiled with GCC 4.1.1
//
// Use the Makefile to build all the samples.
//
// Run using
// tutorial04 myvideofile.mpg
//
// to play the video stream on your screen.

#import "main.h"
/* SDL_Surface     *screen; */
SDL_Window *screen = NULL;
SDL_mutex       *screen_mutex;
SDL_Renderer *renderer = NULL;

/* Since we only have one decoding thread, the Big Struct
 can be global in case we need it. */
VideoState *global_video_state;

int main(int argc, char *argv[]) {
    
    SDL_Event       event;
    
    VideoState      *is;
    
    is = av_mallocz(sizeof(VideoState));
    global_video_state = is;
    is->audio_buf_ptr = is->audio_buf;
    is->audio_buf_ptr_length = sizeof(is->audio_buf);
    
    is->pictq_ptr = is->pictq;
    
    const char *filename;
    
    if(argc < 2) {
        filename = [[[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"sample.mp4"] UTF8String];
    } else {
        filename = argv[1];
    }
    // Register all formats and codecs
    av_register_all();
    
    if(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER)) {
        fprintf(stderr, "Could not initialize SDL - %s\n", SDL_GetError());
        exit(1);
    }
    
    screen = SDL_CreateWindow(
                              "FFmpeg Tutorial",
                              0,
                              0,
                              1280,
                              800,
                              SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN | SDL_WINDOW_MOUSE_FOCUS | SDL_WINDOW_RESIZABLE
                              );
    
    
    if(!screen) {
        fprintf(stderr, "SDL: could not set video mode - exiting\n");
        exit(1);
    }
    
    renderer = SDL_CreateRenderer(screen, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_TARGETTEXTURE);
    if (!renderer) {
        fprintf(stderr, "SDL: could not create renderer - exiting\n");
        exit(1);
    }
    
    screen_mutex = SDL_CreateMutex();
    
    [tutorial5 setWindow:screen];
    [tutorial5 setRenderer:renderer];
    [tutorial5 setScreen_mutex:screen_mutex];
    
    av_strlcpy(is->filename_arr, filename, sizeof(is->filename_arr));
    is->filename = is->filename_arr;
    printf("is->filename: %s\n", is->filename);
    
    is->pictq_mutex = SDL_CreateMutex();
    is->pictq_cond = SDL_CreateCond();
    
    //schedule_refresh(is, 40);
    [tutorial5 schedule_refreshWithVs:is delay:40];
    
    is->parse_tid = SDL_CreateThread([tutorial5 decode_thread], "decode_thread", is);
    if(!is->parse_tid) {
        av_free(is);
        return -1;
    }
    for(;;) {
        
        SDL_WaitEvent(&event);
        switch(event.type) {
            case FF_QUIT_EVENT:
            case SDL_QUIT:
            case SDL_MOUSEBUTTONDOWN:
            case SDL_FINGERDOWN:
                is->quit = 1;
                /* SDL_DestroyTexture(texture); */
                SDL_DestroyRenderer(renderer);
                SDL_DestroyWindow(screen);
                SDL_Quit();
                return 0;
                break;
            case FF_REFRESH_EVENT:
                //video_refresh_timer(event.user.data1);
                [tutorial5 video_refresh_timerWithUserdata:event.user.data1 mutex:screen_mutex window:screen renderer:renderer];
                break;
            default:
                break;
        }
    }
    return 0;
    
}

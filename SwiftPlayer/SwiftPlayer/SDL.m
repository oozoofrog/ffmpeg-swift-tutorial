//
//  SDL.m
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 29..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

#import "SDL.h"

@implementation SDL

+ (BOOL)ready {
    SDL_SetMainReady();
    
    int ret = SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_TIMER);
    if (0 > ret) {
        NSLog(@"😭 %s: %s", __PRETTY_FUNCTION__, SDL_GetError());
    }
    return 0 == ret;
}

@end

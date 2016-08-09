//
//  SDL.m
//  tutorial
//
//  Created by jayios on 2016. 8. 9..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import "SDLHelper.h"
#import "SDL.h"
#import "SDL_main.h"

@implementation SDLHelper

- (instancetype)init {
    self= [super init];
    if (self) {
        /**
         *  directly run initialize function, because of application haven't main.h
         */
        SDL_SetMainReady();
    }
    return self;
}

- (BOOL)SDL_init:(UInt32)flags {
    if (0 > SDL_Init(flags)) {
        NSLog(@"%s", SDL_GetError());
        return NO;
    }
    return YES;
}

@end

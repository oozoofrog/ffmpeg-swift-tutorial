# ffmpeg swift tutorial

>$ git submodule init<br/>
>$ ./FFmpeg-iOS-build-script/build-ffmpeg.sh

###3016.09.03
- add MediaData protocol
- add VideoData: MediaData
- add AudioData: MediaData
- reduce memory usage

###2016.09.02
- pull out SDL from Player.swift and doing update video on ViewController.swift
- resolve thread dead races
- resolve memory leaks
- reduce memory usage

###2016.09.01
- use Accelerate for copy audio stream
- stop using AVFilter
- AVAudioEngine playing with Float Planar audio format

###add SwiftPlayer project
- Using AVAudioEngine, and exclude SDL audio
- syncing with CADisplayLink, DispatchQueue, DispatchSemaphore
- No more referencing ffmpeg tutorials. It is too old, and never working well.

###TODO
- add seeking functions

###olds
- tutorial1
- export from video to image files
- tutorial2
- play video with SDL
- decoding with avfilter

swift only coding is not working now.

- crashing from avfiltercontext type casting problem
- some macros cannot bridging to swift

SDL2.0 + ffmpeg 3.1.1 + swift is different from olds

- using AVFilter instead of SWScale
- using SDL\_Texture, SDL\_Renderer, SDL\_Window instead of SDL\_Overlay, SDL\_Surface
- using avcodec\_send\_packet, avcodec\_receive\_frame instead of avcodec\_decode\_video2, avcodec\_decode\_audio4


now working on tutorial4

//
//  ViewController.swift
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 29..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

import UIKit
import SDL
import AVFoundation

class ViewController: UIViewController {
    
    var path: String? = nil
    var player: Player? = nil
    
    var displayLink: CADisplayLink? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        let prevIO = UIApplication.shared.statusBarOrientation
        if UIInterfaceOrientationIsPortrait(prevIO) {
            UIDevice.current.setValue(UIDeviceOrientation.landscapeLeft.rawValue, forKey: "orientation")
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let path = self.path, 0 < path.lengthOfBytes(using: .utf8) {
            self.player = Player(path: path)
            
            self.player?.start {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard self.setupSDL(player: self.player!) else {
                        self.player?.cancel()
                        return
                    }
                    
                    self.displayLink = CADisplayLink(target: self, selector: #selector(ViewController.update(link:)))
                    self.displayLink?.add(to: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                }
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    var start: Double = 0
    func update(link: CADisplayLink) {
        if 0 == start {
            start = link.timestamp
        }
        self.player?.requestVideoFrame(time: link.timestamp - start, decodeCompletion: { (y, u, v, length) in
            let luma_len = Int32(length)
            let chroma_len = luma_len / 2
            SDL_UpdateYUVTexture(self.texture, &self.videoRect, y, luma_len, u, chroma_len, v, chroma_len)
            SDL_RenderClear(self.renderer)
            SDL_RenderCopy(self.renderer, self.texture, &self.videoRect, &self.dst)
            SDL_RenderPresent(self.renderer)
        })
    }
    
    //MARK: - setupSDL
    var window: OpaquePointer!
    var renderer: OpaquePointer!
    var texture: OpaquePointer!
    
    var videoRect: SDL_Rect = SDL_Rect()
    var dst: SDL_Rect = SDL_Rect()
    lazy var eventQueue: DispatchQueue? = DispatchQueue(label: "sdl.event.queue")
    
    private func setupSDL(player: Player) -> Bool {
        
        SDL_SetMainReady()
        
        let screenSize = UIScreen.main.bounds.size
        
        guard 0 <= SDL_Init(UInt32(SDL_INIT_AUDIO | SDL_INIT_VIDEO)) else {
            print("SDL_Init: " + String(cString: SDL_GetError()))
            return false
        }
        
        guard let w = SDL_CreateWindow("SwiftPlayer", 0, 0, Int32(screenSize.width), Int32(screenSize.height), SDL_WINDOW_OPENGL.rawValue | SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_BORDERLESS.rawValue) else {
            print("SDL_CreateWindow: " + String(cString: SDL_GetError()))
            return false
        }
        
        window = w
        
        guard let r = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED.rawValue | SDL_RENDERER_TARGETTEXTURE.rawValue) else {
            print("SDL_CreateRenderer: " + String(cString: SDL_GetError()))
            return false
        }
        
        renderer = r
        
        let videoSize: CGSize = player.videoSize
        let videoRect: SDL_Rect = SDL_Rect(x: 0, y: 0, w: Int32(videoSize.width), h: Int32(videoSize.height))
        self.videoRect = videoRect
        
        let fitSize = AVMakeRect(aspectRatio: videoSize, insideRect: self.view.window?.bounds ?? CGRect())
        self.dst.x = Int32(fitSize.origin.x)
        self.dst.y = Int32(fitSize.origin.y)
        self.dst.w = Int32(fitSize.width)
        self.dst.h = Int32(fitSize.height)
        guard let t = SDL_CreateTexture(renderer, Uint32(SDL_PIXELFORMAT_IYUV), Int32(SDL_TEXTUREACCESS_TARGET.rawValue), videoRect.w, videoRect.h) else {
            print("SDL_CreateTexture: " + String(cString: SDL_GetError()))
            return false
        }
        
        texture = t
        
        eventQueue?.async {
            var event: SDL_Event = SDL_Event()
            event_loop: while true {
                SDL_PollEvent(&event)
                
                switch event.type {
                case SDL_FINGERDOWN.rawValue, SDL_QUIT.rawValue:
                    DispatchQueue.main.async(execute: {
                        
                        self.player?.cancel()
                        
                        self.displayLink?.isPaused = true
                        self.displayLink?.invalidate()
                        SDL_Quit()
                    })
                    break event_loop
                default:
                    break
                }
            }
        }
        
        return true
    }
}


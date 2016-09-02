//
//  main.swift
//  decode
//
//  Created by Kwanghoon Choi on 2016. 9. 2..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import AVFoundation
import Accelerate

let path = FileManager.default.currentDirectoryPath + "/sample.mp4"

var format: UnsafeMutablePointer<AVFormatContext>?

var videoStreamIndex: Int32 = -1
var audioStreamIndex: Int32 = -1

var videoStream: UnsafeMutablePointer<AVStream>?
var videoCtx: UnsafeMutablePointer<AVCodecContext>?

var audioStream: UnsafeMutablePointer<AVStream>?
var audioCtx: UnsafeMutablePointer<AVCodecContext>?

let engine = AVAudioEngine()
let player = AVAudioPlayerNode()
var audioFormat: AVAudioFormat?
func decode() {
    guard FileManager.default.fileExists(atPath: path) else {
        print("not found \(path)")
        return
    }
    
    av_register_all()
    
    guard av_success(avformat_open_input(&format, path, nil, nil)) else {
        return
    }
    
    defer {
        avformat_close_input(&format)
    }
    
    guard av_success(avformat_find_stream_info(format, nil)) else {
        return
    }
    
    av_dump_format(format, 0, path, 0)
    
    guard let pFormat = format else {
        assertionFailure()
        return
    }
    (0..<pFormat.pointee.nb_streams).forEach{
        if let stream = pFormat.pointee.streams[Int($0)] {
            if stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO {
                videoStreamIndex = Int32($0)
                videoStream = stream
            } else if stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_AUDIO {
                audioStreamIndex = Int32($0)
                audioStream = stream
            }
            
        }
    }
    guard let stream = videoStream else {
        assertionFailure()
        return
    }
    let codec = avcodec_find_decoder(stream.pointee.codecpar.pointee.codec_id)
    guard av_success(avcodec_open2(stream.pointee.codec, codec, nil)) else {
        assertionFailure()
        return
    }
    videoCtx = stream.pointee.codec
    
    guard let astream = audioStream else {
        assertionFailure()
        return
    }
    let acodec = avcodec_find_decoder(astream.pointee.codecpar.pointee.codec_id)
    guard av_success(avcodec_open2(astream.pointee.codec, acodec, nil)) else {
        assertionFailure()
        return
    }
    audioCtx = astream.pointee.codec
    
    engine.attach(player)
    
    audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(audioCtx?.pointee.sample_rate ?? 0), channels: 2, interleaved: false)
    
    engine.connect(player, to: engine.mainMixerNode, format: audioFormat)
    
    engine.prepare()
    
    try! engine.start()
    
    player.play()
    
    var ret: Int32 = 0
    var packet: AVPacket = AVPacket()
    var frame: AVFrame = AVFrame()
    
    var packetList: AVPacketList?
    let sema = DispatchSemaphore(value: 10)
    decode: while true {
        ret = av_read_frame(pFormat, &packet)
        guard 0 <= ret else {
            if IS_AVERROR_EOF(ret) {
                print("finished")
            } else {
                print_err(ret, "")
            }
            break
        }
        if packet.stream_index == audioStreamIndex {
            sema.wait()
            let time = Double(packet.dts) * av_q2d(audioCtx!.pointee.time_base)
            print("packet \(time)")
            ret = avcodec_send_packet(audioCtx, &packet)
            if ret == AVERROR_CONVERT(EAGAIN) {
            } else if 0 > ret {
                print_err(ret, nil)
                assertionFailure()
                break
            }
            
            ret = avcodec_receive_frame(audioCtx, &frame)
            print("frame \(Double(av_frame_get_best_effort_timestamp(&frame)) * av_q2d(audioCtx!.pointee.time_base))")
            if ret == AVERROR_CONVERT(EAGAIN) {
                break
            } else if 0 > ret {
                print_err(ret, "receive")
                assertionFailure()
                break decode
            }
            
            let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat!, frameCapacity: AVAudioFrameCount(Int(frame.linesize.0) / MemoryLayout<Float>.size))
            buffer.frameLength = buffer.frameCapacity / 2
            let channels = buffer.floatChannelData!
            let lbuf = frame.data.0!.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)){$0}
            let rbuf = frame.data.1!.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)){$0}
            let lbuf1 = frame.data.2!.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)){$0}
            let rbuf1 = frame.data.3!.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)){$0}
            let lbuf2 = frame.data.4!.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)){$0}
            let rbuf2 = frame.data.5!.withMemoryRebound(to: Float.self, capacity: Int(buffer.frameLength)){$0}
            vDSP_vadd((channels[0]), 1, lbuf, 1, (channels[0]), 1, vDSP_Length(buffer.frameLength))
            vDSP_vadd((channels[1]), 1, rbuf, 1, (channels[1]), 1, vDSP_Length(buffer.frameLength))
            vDSP_vadd(channels[0], 1, lbuf1, 1, (channels[0]), 1, vDSP_Length(buffer.frameLength))
            vDSP_vadd(channels[1], 1, rbuf1, 1, (channels[1]), 1, vDSP_Length(buffer.frameLength))
            vDSP_vadd(channels[0], 1, lbuf2, 1, (channels[0]), 1, vDSP_Length(buffer.frameLength))
            vDSP_vadd(channels[1], 1, rbuf2, 1, (channels[1]), 1, vDSP_Length(buffer.frameLength))
            
            player.scheduleBuffer(buffer, completionHandler: {sema.signal()})
            av_frame_unref(&frame)
        }
    }
    
    while true {
        
    }
}

decode()

//
//  main.swift
//  tutorial6
//
//  Created by Kwanghoon Choi on 2016. 9. 4..
//  Copyright © 2016년 gretech. All rights reserved.
//

import Foundation
import AVFoundation

var path =  try! FileManager.default.url(for: .musicDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("sample.mp3")

func test() {
    var formatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
    
    guard 0 <= avformat_open_input(&formatCtx, path.path, nil, nil) else {
        print("failed open file \(path.path)")
        return
    }
}

test()

//
//enum SyncType {
//    case audio, video, external
//}
//
//var path =  try! FileManager.default.url(for: .musicDirectory, in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("sample.mp3")
//
//let SDL_AUDIO_BUFFER_SIZE = 1024
//let MAX_AUDIO_FRAME_SIZE = 192000
//
//let MAX_AUDIOQ_SIZE = (5 * 16 * 1024)
//let MAX_VIDEOQ_SIZE = (5 * 256 * 1024)
//
//let AV_SYNC_THRESHOLD = 0.01
//let AV_NOSYNC_THRESHOLD = 10.0
//
//let SAMPLE_CORRECTION_PERCENT_MAX = 10
//let AUDIO_DIFF_AVG_NB = 20
//
//let VIDEO_PICTURE_QUEUE_SIZE = 1
//
//let DEFAULT_AV_SYNC_TYPE: SyncType = .video
//
//struct PacketQueue {
//    var first_pkt: UnsafeMutablePointer<AVPacketList>? = nil
//    var last_pkt: UnsafeMutablePointer<AVPacketList>? = nil
//    var nb_packets: Int = 0
//    var size: Int = 0
//    var lock: DispatchSemaphore = DispatchSemaphore(value: 0)
//}
//
//struct VideoPicture {
//    var luma: Data? = nil
//    var chroma: [Data]? = nil
//    var width: Int = 0, height: Int = 0
//    var allocated: Bool = false
//    var pts: Double = 0
//}
//
//struct AudioBuffer {
//    var buffers: [Data] = []
//    var linesize: Int = 0
//    let bytesPerFrame = MemoryLayout<Float>.size
//    func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
//        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(linesize / bytesPerFrame))
//        buf.frameLength = buf.frameCapacity / 2
//        if Int(format.channelCount) < buffers.count {
//            
//        }
//    }
//}
//
//class VideoState {
//    var pFormatCtx: UnsafeMutablePointer<AVFormatContext>? = nil
//    var videoStream: Int32 = -1
//    var audioStream: Int32 = -1
//    
//    var av_sync_type: SyncType = .external
//    var external_clock: Double = 0.0 /* external clock base */
//    var external_clock_time: Int = 0
//    
//    var audio_clock: Double = 0.0
//    var audio_st: UnsafeMutablePointer<AVStream>? = nil
//    var audio_ctx: UnsafeMutablePointer<AVCodecContext>? = nil
//    var audioq: PacketQueue = PacketQueue()
//    uint8_t         audio_buf[(AVCODEC_MAX_AUDIO_FRAME_SIZE * 3) / 2];
//    unsigned int    audio_buf_size;
//    unsigned int    audio_buf_index;
//    AVFrame         audio_frame;
//    AVPacket        audio_pkt;
//    uint8_t         *audio_pkt_data;
//    int             audio_pkt_size;
//    int             audio_hw_buf_size;
//    double          audio_diff_cum; /* used for AV difference average computation */
//    double          audio_diff_avg_coef;
//    double          audio_diff_threshold;
//    int             audio_diff_avg_count;
//    double          frame_timer;
//    double          frame_last_pts;
//    double          frame_last_delay;
//    double          video_clock; ///<pts of last decoded frame / predicted pts of next decoded frame
//    double          video_current_pts; ///<current displayed pts (different from video_clock if frame fifos are used)
//    int64_t         video_current_pts_time;  ///<time (av_gettime) at which we updated video_current_pts - used to have running video pts
//    AVStream        *video_st;
//    AVCodecContext  *video_ctx;
//    PacketQueue     videoq;
//    struct SwsContext *sws_ctx;
//    
//    VideoPicture    pictq[VIDEO_PICTURE_QUEUE_SIZE];
//    int             pictq_size, pictq_rindex, pictq_windex;
//    SDL_mutex       *pictq_mutex;
//    SDL_cond        *pictq_cond;
//    
//    SDL_Thread      *parse_tid;
//    SDL_Thread      *video_tid;
//    
//    char            filename[1024];
//    int             quit;
//}

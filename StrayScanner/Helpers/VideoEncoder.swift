//
//  VideoEncoder.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 12/30/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import Foundation
import ARKit
import AVFoundation

struct VideoEncoderInput {
    let buffer: CVPixelBuffer
    let time: TimeInterval // Relative to boot time.
}

class VideoEncoder {
    enum EncodingStatus {
        case allGood
        case error
    }
    
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var videoAdapter: AVAssetWriterInputPixelBufferAdaptor?
    private let timeScale = CMTimeScale(60_000)
    private var firstFrameTime: TimeInterval?
    public let width: CGFloat
    public let height: CGFloat
    public var filePath: URL
    public var status: EncodingStatus = EncodingStatus.allGood

    init(file: URL, width: CGFloat, height: CGFloat) {
        self.filePath = file
        self.width = width
        self.height = height
        initializeFile()
    }

    private(set) var droppedFrames = 0

    func finishEncoding() {
        self.doneRecording()
    }

    func add(frame: VideoEncoderInput) -> Bool {
        guard status == .allGood, let writer = videoWriter,
              let input = videoWriterInput, let adapter = videoAdapter else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while writer.status == .writing && !input.isReadyForMoreMediaData &&
              ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let time = CMTime(seconds: frame.time - (firstFrameTime ?? frame.time), preferredTimescale: timeScale)
        guard writer.status == .writing, input.isReadyForMoreMediaData,
              adapter.append(frame.buffer, withPresentationTime: time) else {
            if writer.status != .writing { status = .error }
            droppedFrames += 1
            print("Could not append video frame: \(writer.error?.localizedDescription ?? "writer unavailable")")
            return false
        }
        if firstFrameTime == nil { firstFrameTime = frame.time }
        return true
    }

    private func initializeFile() {
        do {
            let writer = try AVAssetWriter(outputURL: self.filePath, fileType: .mp4)
            let settings: [String : Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: self.width,
                AVVideoHeightKey: self.height
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            input.mediaTimeScale = timeScale
            input.performsMultiPassEncodingIfSupported = false
            videoAdapter = createVideoAdapter(input)
            if writer.canAdd(input) {
                writer.add(input)
                videoWriterInput = input
                guard writer.startWriting() else {
                    status = .error
                    return
                }
                writer.startSession(atSourceTime: .zero)
                videoWriter = writer
            } else {
                status = .error
            }
        } catch let error as NSError {
            status = .error
            print("Creating AVAssetWriter failed. \(error), \(error.userInfo)")
        }
    }

    private func doneRecording() {
        guard let writer = videoWriter, writer.status == .writing,
              let input = videoWriterInput else {
            status = .error
            return
        }
        guard status == .allGood else {
            writer.cancelWriting()
            return
        }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        if writer.status != .completed {
            status = .error
        }
        videoWriter = nil
        videoWriterInput = nil
        videoAdapter = nil
    }

    private func createVideoAdapter(_ input: AVAssetWriterInput) -> AVAssetWriterInputPixelBufferAdaptor {
        return AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    }
}

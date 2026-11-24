//
//  DatasetEncoder.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 1/2/21.
//  Copyright © 2021 Stray Robots. All rights reserved.
//

import Foundation
import ARKit
import CryptoKit
import CoreMotion

#if DEBUG
struct StageTimings {
    private var samples: [Double] = []

    mutating func record(since start: TimeInterval) {
        guard samples.count < 3600 else { return }
        samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
    }

    var summary: [String: Double] {
        guard !samples.isEmpty else { return [:] }
        let sorted = samples.sorted()
        return ["samples": Double(sorted.count),
                "median_ms": sorted[sorted.count / 2],
                "p95_ms": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]]
    }
}
#endif

class DatasetEncoder {
    enum Status {
        case allGood
        case videoEncodingError
        case directoryCreationError
    }
    private let rgbEncoder: VideoEncoder
    private let depthEncoder: DepthEncoder
    private let confidenceEncoder: ConfidenceEncoder
    private let datasetDirectory: URL
    private let odometryEncoder: OdometryEncoder
    private let imuEncoder: IMUEncoder
    private let distortionEncoder: DistortionEncoder
    private var lastFrame: ARFrame?
    private var dispatchGroup = DispatchGroup()
    private var currentFrame: Int = -1
    private var firstCaptureTime: TimeInterval?
    private var lastCaptureTime: TimeInterval?
    private var firstCallbackTime: TimeInterval?
    private var lastCallbackTime: TimeInterval?
    private var captureGaps: [String: Int] = [:]
    private(set) var savedFrameCount = 0
    private var queueDroppedFrames = 0
    private let configuredVideoFps: Int
    private let videoResolution: CGSize
    private let thermalStateAtStart = ProcessInfo.processInfo.thermalState.rawValue
    #if DEBUG
    private var depthTiming = StageTimings()
    private var confidenceTiming = StageTimings()
    private var odometryTiming = StageTimings()
    #endif
    private let captureFps: Double
    private var lastSelectedSlot = -1
    #if DEBUG && SCANNER_QUEUE_EXPERIMENT
    private static let encodingQueueLimit = 6
    #else
    private static let encodingQueueLimit = 3
    #endif
    private let encodingSemaphore = DispatchSemaphore(value: DatasetEncoder.encodingQueueLimit)
    public let id: UUID
    public let rgbFilePath: URL // Relative to app document directory.
    public let depthFilePath: URL // Relative to app document directory.
    public let cameraMatrixPath: URL
    public let odometryPath: URL
    public let imuPath: URL
    public var status = Status.allGood
    private let queue: DispatchQueue
    
    private var latestAccelerometerData: (timestamp: Double, data: simd_double3)?
    private var latestGyroscopeData: (timestamp: Double, data: simd_double3)?


    init(arConfiguration: ARWorldTrackingConfiguration, fps: Int) {
        self.captureFps = Double(fps)
        configuredVideoFps = arConfiguration.videoFormat.framesPerSecond
        videoResolution = arConfiguration.videoFormat.imageResolution
        self.queue = DispatchQueue(label: "encoderQueue")
        
        let width = arConfiguration.videoFormat.imageResolution.width
        let height = arConfiguration.videoFormat.imageResolution.height
        var theId: UUID = UUID()
        datasetDirectory = DatasetEncoder.createDirectory(id: &theId)
        self.id = theId
        self.rgbFilePath = datasetDirectory.appendingPathComponent("rgb.mp4")
        self.rgbEncoder = VideoEncoder(file: self.rgbFilePath, width: width, height: height)
        self.depthFilePath = datasetDirectory.appendingPathComponent("depth", isDirectory: true)
        self.depthEncoder = DepthEncoder(outDirectory: self.depthFilePath)
        let confidenceFilePath = datasetDirectory.appendingPathComponent("confidence", isDirectory: true)
        self.confidenceEncoder = ConfidenceEncoder(outDirectory: confidenceFilePath)
        self.cameraMatrixPath = datasetDirectory.appendingPathComponent("camera_matrix.csv", isDirectory: false)
        self.odometryPath = datasetDirectory.appendingPathComponent("odometry.csv", isDirectory: false)
        self.odometryEncoder = OdometryEncoder(url: self.odometryPath)
        self.imuPath = datasetDirectory.appendingPathComponent("imu.csv", isDirectory: false)
        self.imuEncoder = IMUEncoder(url: self.imuPath)
        self.distortionEncoder = DistortionEncoder(datasetDirectory: datasetDirectory)
    }

    func add(frame: ARFrame, callbackTime: TimeInterval) {
        let captureTime = frame.timestamp
        if let previous = lastCaptureTime {
            let gapMs = Int(((captureTime - previous) * 1000).rounded())
            captureGaps[String(gapMs), default: 0] += 1
        }
        if firstCaptureTime == nil { firstCaptureTime = captureTime }
        if firstCallbackTime == nil { firstCallbackTime = callbackTime }
        lastCaptureTime = captureTime
        lastCallbackTime = callbackTime
        currentFrame += 1
        guard let firstCaptureTime = firstCaptureTime else { return }
        // Allow a quarter-slot of timestamp jitter at each sampling boundary.
        let slot = Int(floor((captureTime - firstCaptureTime) * captureFps + 0.25))
        guard slot > lastSelectedSlot else { return }
        // Drop frame if encoding is backed up to avoid accumulating ARFrame references.
        guard encodingSemaphore.wait(timeout: .now()) == .success else {
            queueDroppedFrames += 1
            return
        }
        lastSelectedSlot = slot
        dispatchGroup.enter()
        queue.async {
            defer {
                self.encodingSemaphore.signal()
                self.dispatchGroup.leave()
            }
            guard self.rgbEncoder.add(frame: VideoEncoderInput(buffer: frame.capturedImage, time: frame.timestamp)) else { return }
            let frameNumber = self.savedFrameCount
            self.savedFrameCount += 1
            if let sceneDepth = frame.sceneDepth {
                #if DEBUG
                let depthStart = ProcessInfo.processInfo.systemUptime
                #endif
                self.depthEncoder.encodeFrame(frame: sceneDepth.depthMap, frameNumber: frameNumber)
                #if DEBUG
                self.depthTiming.record(since: depthStart)
                #endif
                if let confidence = sceneDepth.confidenceMap {
                    #if DEBUG
                    let confidenceStart = ProcessInfo.processInfo.systemUptime
                    #endif
                    self.confidenceEncoder.encodeFrame(frame: confidence, frameNumber: frameNumber)
                    #if DEBUG
                    self.confidenceTiming.record(since: confidenceStart)
                    #endif
                } else {
                    print("warning: confidence map missing.")
                }
            } else {
                print("warning: scene depth missing.")
            }
            #if DEBUG
            let odometryStart = ProcessInfo.processInfo.systemUptime
            #endif
            self.odometryEncoder.add(frame: frame, currentFrame: frameNumber)
            #if DEBUG
            self.odometryTiming.record(since: odometryStart)
            #endif
            self.distortionEncoder.add(frame: frame, currentFrame: frameNumber)
            self.lastFrame = frame
        }
    }
    
   func addRawAccelerometer(data: CMAccelerometerData) {
        let acceleration = simd_double3(data.acceleration.x, data.acceleration.y, data.acceleration.z)
        latestAccelerometerData = (timestamp: data.timestamp, data: acceleration)
        tryWritingIMUData()
    }

    func addRawGyroscope(data: CMGyroData) {
        let rotationRate = simd_double3(data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
        latestGyroscopeData = (timestamp: data.timestamp, data: rotationRate)
        tryWritingIMUData()
    }

    private func tryWritingIMUData() {
        guard
            let accelerometer = latestAccelerometerData,
            let gyroscope = latestGyroscopeData
        else {
            return
        }

        // Write the row to the CSV with the most recent timestamp
        let timestamp = max(accelerometer.timestamp, gyroscope.timestamp)
        imuEncoder.add(
            timestamp: timestamp,
            linear: accelerometer.data,
            angular: gyroscope.data
        )

        // Clear the buffers after writing
        latestAccelerometerData = nil
        latestGyroscopeData = nil
    }

    func wrapUp() {
        dispatchGroup.wait()
        self.rgbEncoder.finishEncoding()
        print("Dropped frames — encoding queue full: \(queueDroppedFrames), RGB writer: \(rgbEncoder.droppedFrames)")
        self.imuEncoder.done()
        self.odometryEncoder.done()
        self.distortionEncoder.done()
        writeIntrinsics()
        switch self.rgbEncoder.status {
            case .allGood:
                break
            case .error:
                status = .videoEncodingError
        }
        switch self.depthEncoder.status {
            case .allGood:
                break
            case .frameEncodingError:
                status = .videoEncodingError
                print("Something went wrong encoding depth.")
        }
        switch self.confidenceEncoder.status {
            case .allGood:
                break
            case .encodingError:
                status = .videoEncodingError
                print("Something went wrong encoding confidence values.")
        }
    }

    func writeCaptureStats(fps: Int, previewMode: String, thermalStateAtStop: Int) {
        var stats: [String: Any] = [
            "configured_camera_fps": configuredVideoFps,
            "configured_camera_width": Int(videoResolution.width),
            "configured_camera_height": Int(videoResolution.height),
            "thermal_state_start": thermalStateAtStart,
            "thermal_state_stop": thermalStateAtStop,
            "arkit_callbacks": currentFrame + 1,
            "arkit_timestamp_gap_histogram_ms": captureGaps,
            "queue_limit": Self.encodingQueueLimit,
            "queue_full_drops": queueDroppedFrames,
            "writer_drops": rgbEncoder.droppedFrames,
            "saved_frames": savedFrameCount,
            "fps_setting": fps,
            "preview_mode": previewMode
        ]
        #if DEBUG
        stats["stage_timing"] = [
            "rgb_writer_wait": rgbEncoder.waitTiming.summary,
            "rgb_append": rgbEncoder.appendTiming.summary,
            "depth_png": depthTiming.summary,
            "confidence_png": confidenceTiming.summary,
            "odometry": odometryTiming.summary
        ]
        #endif
        if let first = firstCaptureTime, let last = lastCaptureTime, last > first {
            stats["arkit_capture_span_s"] = last - first
            stats["arkit_capture_fps"] = Double(currentFrame) / (last - first)
        }
        if let first = firstCallbackTime, let last = lastCallbackTime, last > first {
            stats["arkit_callback_span_s"] = last - first
            stats["arkit_callback_fps"] = Double(currentFrame) / (last - first)
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: datasetDirectory.appendingPathComponent("stats.json"), options: .atomic)
        } catch {
            print("Could not write capture statistics: \(error.localizedDescription)")
        }
    }

    func removeRecordingFiles() {
        do {
            try FileManager.default.removeItem(at: datasetDirectory)
        } catch {
            print("Could not remove incomplete recording: \(error.localizedDescription)")
        }
    }

    private func writeIntrinsics() {
        if let cameraMatrix = lastFrame?.camera.intrinsics {
            let rows = cameraMatrix.transpose.columns
            var csv: [String] = []
            for row in [rows.0, rows.1, rows.2] {
                let csvLine = "\(row.x), \(row.y), \(row.z)"
                csv.append(csvLine)
            }
            let contents = csv.joined(separator: "\n")
            do {
                try contents.write(to: self.cameraMatrixPath, atomically: true, encoding: String.Encoding.utf8)
            } catch let error {
                print("Could not write camera matrix. \(error.localizedDescription)")
            }
        }
    }

    static private func createDirectory(id: inout UUID) -> URL {
        let directoryId = hashUUID(id: id)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = URL(fileURLWithPath: directoryId, relativeTo: url)
        if FileManager.default.fileExists(atPath: directory.path) {
            // Just in case the first 5 characters clash, try again.
            id = UUID()
            return DatasetEncoder.createDirectory(id: &id)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            print("Error creating directory. \(error), \(error.userInfo)")
        }
        return directory
    }

    static private func hashUUID(id: UUID) -> String {
        var hasher: SHA256 = SHA256()
        hasher.update(data: id.uuidString.data(using: .ascii)!)
        let digest = hasher.finalize()
        var string = ""
        digest.makeIterator().prefix(5).forEach { (byte: UInt8) in
            string += String(format: "%02x", byte)
        }
        print("Hash: \(string)")
        return string
    }
}

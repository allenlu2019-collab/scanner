//
//  DepthEncoder.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 1/24/21.
//  Copyright © 2021 Stray Robots. All rights reserved.
//

import Foundation
import CoreImage
import UIKit

class DepthEncoder {
    enum Status {
        case allGood
        case frameEncodingError
    }
    private let baseDirectory: URL
    public var status: Status = Status.allGood

    init(outDirectory: URL) {
        self.baseDirectory = outDirectory
        do {
            try FileManager.default.createDirectory(at: outDirectory.absoluteURL, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            print("Could not create folder. \(error.localizedDescription)")
            status = Status.frameEncodingError
        }
    }

    func encodeFrame(frame: CVPixelBuffer, frameNumber: Int) {
        let filename = String(format: "%06d", frameNumber)
        guard let data = convert(frame: frame)?.fileContents() else {
            status = .frameEncodingError
            return
        }
        let framePath = self.baseDirectory.absoluteURL.appendingPathComponent(filename, isDirectory: false).appendingPathExtension("png")
        do {
            try data.write(to: framePath)
        } catch let error {
            status = .frameEncodingError
            print("Could not save depth image \(frameNumber). \(error.localizedDescription)")
        }
    }
    
    private func convert(frame: CVPixelBuffer) -> PngEncoder? {
        assert(CVPixelBufferGetPixelFormatType(frame) == kCVPixelFormatType_DepthFloat32)
        let height = CVPixelBufferGetHeight(frame)
        let width = CVPixelBufferGetWidth(frame)
        guard CVPixelBufferLockBaseAddress(frame, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(frame) else { return nil }
        return PngEncoder(depth: base.assumingMemoryBound(to: Float32.self),
                          width: Int32(width), height: Int32(height))
    }
}

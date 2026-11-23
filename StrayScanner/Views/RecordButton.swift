//
//  RecordButton.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 12/27/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import Foundation
import UIKit

@IBDesignable
class RecordButton : UIView {
    private let circleStroke: CGFloat = 5.0
    private var recording: Bool = false
    private var disk: CALayer!
    private var edge: CAShapeLayer?
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(buttonPressed))
    private var callback: Optional<(Bool) -> Void> = Optional.none

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setup()
    }

    required public init?(coder aCoder: NSCoder) {
        super.init(coder: aCoder)
        self.backgroundColor = UIColor.clear
    }

    func setCallback(callback: @escaping (Bool) -> Void) {
        self.callback = Optional.some(callback)
    }

    @objc func buttonPressed() {
        disk?.removeAllAnimations()
        self.recording = !self.recording
        updateDiskShape()
        self.callback?(self.recording)
    }

    private func setup() {
        drawInner()
        drawEdge()
        if tap.view == nil { addGestureRecognizer(tap) }
    }

    private func drawEdge() {
        edge?.removeFromSuperlayer()
        let circleLayer = CAShapeLayer()
        edge = circleLayer
        let circleRadius: CGFloat = self.bounds.height * 0.5 - circleStroke;
        let x: CGFloat = self.bounds.size.width / 2
        let y: CGFloat = self.bounds.size.height / 2
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: x, y: y), radius: circleRadius, startAngle: CGFloat(0), endAngle: CGFloat(Float.pi * 2.0), clockwise: false)
        circleLayer.path = path
        circleLayer.fillColor = UIColor.clear.cgColor
        circleLayer.strokeColor = UIColor(named: "DarkColor")!.cgColor
        circleLayer.lineWidth = circleStroke
        circleLayer.opacity = 1.0
        self.layer.addSublayer(circleLayer)
    }

    private func drawInner() {
        disk?.removeFromSuperlayer()
        disk = CALayer()
        let diameter = self.bounds.height - circleStroke * 4.0
        let x: CGFloat = self.bounds.width * 0.5
        let y: CGFloat = self.bounds.height * 0.5
        let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        disk.backgroundColor = UIColor.red.cgColor
        disk.position.x = x
        disk.position.y = y
        disk.bounds = rect
        disk.opacity = 1.0
        updateDiskShape()
        self.layer.addSublayer(disk)
    }

    private func updateDiskShape() {
        disk?.cornerRadius = cornerRadius(recording: recording)
        let scale: CGFloat = recording ? 0.5 : 1
        disk?.transform = CATransform3DMakeScale(scale, scale, 1)
    }

    @objc override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        drawInner()
        drawEdge()
        self.backgroundColor = UIColor.clear
    }

    private func cornerRadius(recording: Bool) -> CGFloat {
        if recording {
            return 10.0
        } else {
            return (self.bounds.height - circleStroke * 4.0) * 0.5
        }
    }
}

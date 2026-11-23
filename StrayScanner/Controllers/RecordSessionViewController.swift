//
//  RecordSessionViewController.swift
//  Stray Scanner
//
//  Created by Kenneth Blomqvist on 11/28/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//

import Foundation
import UIKit
import Metal
import ARKit
import AVKit
import CoreData
import CoreMotion

let FpsDividers: [Int] = [1, 2, 4, 12, 60]
let AvailableFpsSettings: [Int] = FpsDividers.map { Int(60 / $0) }
let FpsUserDefaultsKey: String = "FPS"

class MetalView : UIView {
    override class var layerClass: AnyClass {
        get {
            return CAMetalLayer.self
        }
    }
    override var layer: CAMetalLayer {
        return super.layer as! CAMetalLayer
    }
}

class RecordSessionViewController : UIViewController, ARSessionDelegate {
    private var unsupported: Bool = false
    private var arConfiguration: ARWorldTrackingConfiguration?
    private let session = ARSession()
    private let motionManager = CMMotionManager()
    private var renderer: CameraRenderer?
    private var updateLabelTimer: Timer?
    private var startedRecording: Date?
    private var dataContext: NSManagedObjectContext!
    private var datasetEncoder: DatasetEncoder?
    private let imuOperationQueue = OperationQueue()
    private var finalizingRecording = false
    private var lastRemotePress: TimeInterval?
    private var chosenFpsSetting: Int = 0
    @IBOutlet private var rgbView: MetalView!
    @IBOutlet private var depthView: MetalView!
    @IBOutlet private var recordButton: RecordButton!
    @IBOutlet private var timeLabel: UILabel!
    @IBOutlet weak var fpsButton: UIButton!
    var dismissFunction: Optional<() -> Void> = Optional.none
    
    func setDismissFunction(_ fn: Optional<() -> Void>) {
        self.dismissFunction = fn
    }
    override func viewWillAppear(_ animated: Bool) {
        self.chosenFpsSetting = UserDefaults.standard.integer(forKey: FpsUserDefaultsKey)
        updateFpsSetting()
    }

    override func viewDidLoad() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        self.dataContext = appDelegate.persistentContainer.newBackgroundContext()
        self.renderer = CameraRenderer(rgbLayer: rgbView.layer, depthLayer: depthView.layer)

        depthView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewTapped)))
        rgbView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewTapped)))
        
        setViewProperties()
        setPreviewMode(UserDefaults.standard.bool(forKey: "PreviewDepth") ? .depth : .rgb)
        session.delegate = self

        recordButton.setCallback { [weak self] recording in
            self?.toggleRecording(recording)
        }
        if #available(iOS 17.2, *) {
            view.addInteraction(AVCaptureEventInteraction { [weak self] event in
                if event.phase == .ended {
                    self?.remoteTriggerPressed()
                }
            })
        }
        fpsButton.layer.masksToBounds = true
        fpsButton.layer.cornerRadius = 12.0
        
        imuOperationQueue.maxConcurrentOperationCount = 1
        imuOperationQueue.qualityOfService = .userInitiated
    }

    override func viewDidDisappear(_ animated: Bool) {
        session.pause();
    }

    override func viewWillDisappear(_ animated: Bool) {
        resignFirstResponder()
        stopRawIMU()
        imuOperationQueue.waitUntilAllOperationsAreFinished()
        updateLabelTimer?.invalidate()
        startedRecording = nil
        datasetEncoder = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        startSession()
        becomeFirstResponder()
    }

    private func startSession() {
        let config = ARWorldTrackingConfiguration()
        arConfiguration = config
        if !ARWorldTrackingConfiguration.isSupported || !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            print("AR is not supported.")
            unsupported = true
        } else {
            config.frameSemantics.insert(.sceneDepth)
            session.run(config)
        }
    }
    
    private func startRawIMU() {
        if self.motionManager.isAccelerometerAvailable {
            self.motionManager.accelerometerUpdateInterval = 1.0 / 1200.0 // Set update rate
            self.motionManager.startAccelerometerUpdates(to: imuOperationQueue) { (data, error) in
                guard let data = data else {
                    if let error = error {
                        print("Error retrieving accelerometer data: \(error.localizedDescription)")
                    }
                    return
                }
                self.datasetEncoder?.addRawAccelerometer(data: data)
            }
        } else {
            print("Accelerometer not available on this device.")
        }

        if self.motionManager.isGyroAvailable {
            self.motionManager.gyroUpdateInterval = 1.0 / 1200.0 // Set update rate
            self.motionManager.startGyroUpdates(to: imuOperationQueue) { (data, error) in
                guard let data = data else {
                    if let error = error {
                        print("Error retrieving gyroscope data: \(error.localizedDescription)")
                    }
                    return
                }
                self.datasetEncoder?.addRawGyroscope(data: data)
            }
        } else {
            print("Gyroscope not available on this device.")
        }
    }

    private func stopRawIMU() {
        if self.motionManager.isAccelerometerActive {
            self.motionManager.stopAccelerometerUpdates()
            print("Stopped accelerometer updates.")
        }
        if self.motionManager.isGyroActive {
            self.motionManager.stopGyroUpdates()
            print("Stopped gyroscope updates.")
        }
    }
    
    private func toggleRecording(_ recording: Bool) {
        if unsupported {
            showUnsupportedAlert()
            return
        }
        if recording && self.startedRecording == nil {
            startRecording()
        } else if self.startedRecording != nil && !recording {
            stopRecording()
        } else {
            print("This should not happen. We are either not recording and want to stop, or we are recording and want to start.")
        }
    }

    private func startRecording() {
        self.startedRecording = Date()
        updateTime()
        updateLabelTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.updateTime()
        }
        datasetEncoder = DatasetEncoder(arConfiguration: arConfiguration!, fpsDivider: FpsDividers[chosenFpsSetting])
        startRawIMU()
    }

    private func stopRecording() {
        guard let started = self.startedRecording else {
            print("Hasn't started recording. Something is wrong.")
            return
        }
        startedRecording = nil
        updateLabelTimer?.invalidate()
        updateLabelTimer = nil
        // Stop IMU updates
        stopRawIMU()
        imuOperationQueue.waitUntilAllOperationsAreFinished()
        guard let encoder = datasetEncoder else {
            showError()
            return
        }
        finalizingRecording = true
        recordButton.isUserInteractionEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            encoder.wrapUp()
            DispatchQueue.main.async {
                self.finalizingRecording = false
                self.recordButton.isUserInteractionEnabled = true
                self.datasetEncoder = nil
                switch encoder.status {
                case .allGood:
                    self.saveRecording(started, encoder)
                    self.dismissFunction?()
                case .videoEncodingError, .directoryCreationError:
                    self.showError()
                }
            }
        }
    }

    private func saveRecording(_ started: Date, _ encoder: DatasetEncoder) {
        let sessionCount = countSessions()
        
        let duration = Date().timeIntervalSince(started)
        let entity = NSEntityDescription.entity(forEntityName: "Recording", in: self.dataContext)!
        let recording: Recording = Recording(entity: entity, insertInto: self.dataContext)
        recording.setValue(encoder.id, forKey: "id")
        recording.setValue(duration, forKey: "duration")
        recording.setValue(started, forKey: "createdAt")
        recording.setValue("Recording \(sessionCount)", forKey: "name")
        recording.setValue(encoder.rgbFilePath.relativeString, forKey: "rgbFilePath")
        recording.setValue(encoder.depthFilePath.relativeString, forKey: "depthFilePath")
        do {
            try self.dataContext.save()
        } catch let error as NSError {
            print("Could not save recording. \(error), \(error.userInfo)")
        }
    }

    private func showError() {
        let controller = UIAlertController(title: "Error",
            message: "Something went wrong when encoding video. This should not have happened. You might want to file a bug report.",
            preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default Action"), style: .default, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        }))
        self.present(controller, animated: true, completion: nil)
    }

    private func updateTime() {
        guard let started = self.startedRecording else { return }
        let seconds = Date().timeIntervalSince(started)
        let minutes: Int = Int(floor(seconds / 60).truncatingRemainder(dividingBy: 60))
        let hours: Int = Int(floor(seconds / 3600))
        let roundSeconds: Int = Int(floor(seconds.truncatingRemainder(dividingBy: 60)))
        self.timeLabel.text = String(format: "%02d:%02d:%02d", hours, minutes, roundSeconds)
    }

    private func setPreviewMode(_ mode: RenderMode) {
        renderer?.renderMode = mode
        rgbView.isHidden = mode == .depth
        depthView.isHidden = mode == .rgb
    }

    @objc func viewTapped() {
        let nextMode: RenderMode = renderer?.renderMode == .rgb ? .depth : .rgb
        setPreviewMode(nextMode)
        UserDefaults.standard.set(nextMode == .depth, forKey: "PreviewDepth")
    }

    override var canBecomeFirstResponder: Bool { true }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let otherPresses = Set(presses.filter {
            switch $0.key?.keyCode {
            case .keyboardReturnOrEnter, .keypadEnter, .keyboardSpacebar:
                return false
            default:
                return true
            }
        })
        if otherPresses.count != presses.count { remoteTriggerPressed() }
        if !otherPresses.isEmpty { super.pressesEnded(otherPresses, with: event) }
    }

    private func remoteTriggerPressed() {
        guard isFirstResponder, view.window != nil,
              UIApplication.shared.applicationState == .active,
              !unsupported, !finalizingRecording, session.currentFrame != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPress = lastRemotePress, now - lastPress < 0.8 { return }
        lastRemotePress = now
        recordButton.buttonPressed()
    }

    @IBAction func fpsButtonTapped() {
        chosenFpsSetting = (chosenFpsSetting + 1) % AvailableFpsSettings.count
        updateFpsSetting()
        UserDefaults.standard.set(chosenFpsSetting, forKey: FpsUserDefaultsKey)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        self.renderer!.render(frame: frame)
        if startedRecording != nil {
            if let encoder = datasetEncoder {
                encoder.add(frame: frame)
            } else {
                print("There is no video encoder. That can't be good.")
            }
        }
    }

    private func setViewProperties() {
        self.view.backgroundColor = UIColor(named: "BackgroundColor")
    }
    
    private func updateFpsSetting() {
        let fps = AvailableFpsSettings[chosenFpsSetting]
        let buttonLabel: String = "\(fps) fps"
        fpsButton.setTitle(buttonLabel, for: UIControl.State.normal)
    }
    
    private func showUnsupportedAlert() {
        let alert = UIAlertController(title: "Unsupported device", message: "This device doesn't seem to have the required level of ARKit support.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            self.dismissFunction?()
        }))
        self.present(alert, animated: true)
    }
    
    private func countSessions() -> Int {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return 0 }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Recording")
        do {
            let fetched: [NSManagedObject] = try appDelegate.persistentContainer.viewContext.fetch(request)
            return fetched.count
        } catch let error {
            print("Could not fetch sessions for counting. \(error.localizedDescription)")
        }
        return 0
    }
}

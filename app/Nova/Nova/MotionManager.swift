//
//  MotionManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import CoreMotion
import Combine


struct DeviceBasis: Equatable {
    var right: SIMD3<Double>
    var up: SIMD3<Double>
    var forward: SIMD3<Double>

    static func fromLookDirection(azimuth: Double, altitude: Double) -> DeviceBasis {
        let a = AstronomyEngine.rad(azimuth), h = AstronomyEngine.rad(altitude)
        return DeviceBasis(right: SIMD3(cos(a), -sin(a), 0),
                           up: SIMD3(-sin(a) * sin(h), -cos(a) * sin(h), cos(h)),
                           forward: SIMD3(sin(a) * cos(h), cos(a) * cos(h), sin(h)))
    }
    var lookAzimuthAltitude: (azimuth: Double, altitude: Double) {
        (AstronomyEngine.norm360(AstronomyEngine.deg(atan2(forward.x, forward.y))),
         AstronomyEngine.deg(asin(max(-1, min(1, forward.z)))))
    }
}


@MainActor
final class MotionManager: ObservableObject {

    enum Quality: Int, Comparable {
        case unavailable = 0, uncalibrated, low, medium, high
        static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }

        var spoken: String {
            switch self {
            case .unavailable: return "The motion sensors are not available."
            case .uncalibrated: return "The compass is not calibrated."
            case .low: return "The compass accuracy is low."
            case .medium: return "The compass accuracy is fair."
            case .high: return "The compass accuracy is good."
            }
        }
        var uncertainty: Double {
            switch self {
            case .high: return 5
            case .medium: return 9
            case .low: return 16
            case .uncalibrated, .unavailable: return 45
            }
        }
    }

    @Published private(set) var pointing: Horizontal?
    @Published private(set) var rawAzimuth: Double?
    @Published private(set) var quality: Quality = .unavailable
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var usingTrueNorth = false
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Motion sensors not started."
    @Published private(set) var basis: DeviceBasis?
    private let cm = CMMotionManager()
    private var smoothed: (x: Double, y: Double, z: Double)?
    private var smoothedBasis: (r: SIMD3<Double>, u: SIMD3<Double>, f: SIMD3<Double>)?
    private var sampleCount = 0
    private var simTimer: Timer?

    var settingsProvider: @MainActor () -> AppSettings = { AppSettings() }
    var declinationProvider: @MainActor () -> Double? = { nil }
    var locationAuthorized: @MainActor () -> Bool = { false }
    var saveAzimuthOffset: @MainActor (Double) -> Void = { _ in }


    var isFresh: Bool { lastUpdate.map { Date().timeIntervalSince($0) < 1.0 } ?? false }
    var uncertainty: Double { quality.uncertainty }
    var isReliableForGuidance: Bool { isFresh && quality >= .medium && pointing != nil }
    var isUsableForIdentify: Bool { isFresh && quality >= .low && pointing != nil }


    func start() {
        stop()
        let s = settingsProvider()
        if s.demoMode { startSimulated(); return }
        guard cm.isDeviceMotionAvailable else {
            quality = .unavailable
            statusText = "This device has no usable motion sensors. Try Demo mode in Settings."
            return
        }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let wantTrue = frames.contains(.xTrueNorthZVertical) && locationAuthorized()
        let frame: CMAttitudeReferenceFrame
        if wantTrue { frame = .xTrueNorthZVertical }
        else if frames.contains(.xMagneticNorthZVertical) { frame = .xMagneticNorthZVertical }
        else {
            quality = .unavailable
            statusText = "No compass reference is available on this device. The magnetometer is needed."
            return
        }
        usingTrueNorth = wantTrue
        cm.deviceMotionUpdateInterval = 1.0 / 30.0
        cm.showsDeviceMovementDisplay = true
        cm.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.handle(motion) }
        }
        isRunning = true
        statusText = wantTrue ? "Using the compass with true north." : "Using the magnetic compass; location is needed for true north."
    }

    func stop() {
        cm.stopDeviceMotionUpdates()
        simTimer?.invalidate(); simTimer = nil
        isRunning = false
        smoothed = nil
        smoothedBasis = nil
        basis = nil
    }


    private func handle(_ m: CMDeviceMotion) {
        let s = settingsProvider()
        let r = m.attitude.rotationMatrix
        let g = m.gravity

      
        func dist(_ a: (Double, Double, Double)) -> Double {
            (a.0 - g.x) * (a.0 - g.x) + (a.1 - g.y) * (a.1 - g.y) + (a.2 - g.z) * (a.2 - g.z)
        }
        let gravityIfRowsAreDeviceZ = (-r.m31, -r.m32, -r.m33)
        let gravityIfColsAreDeviceZ = (-r.m13, -r.m23, -r.m33)
        let deviceToRef = dist(gravityIfRowsAreDeviceZ) <= dist(gravityIfColsAreDeviceZ)

        let v: (x: Double, y: Double, z: Double)
        switch (s.pointingMode, deviceToRef) {
        case (.backOfPhone, true):  v = (-r.m13, -r.m23, -r.m33)
        case (.backOfPhone, false): v = (-r.m31, -r.m32, -r.m33)
        case (.topEdge, true):      v = (r.m12, r.m22, r.m32)
        case (.topEdge, false):     v = (r.m21, r.m22, r.m23)
        }

        let xd: (Double, Double, Double), yd: (Double, Double, Double), zd: (Double, Double, Double)
        if deviceToRef { xd = (r.m11, r.m21, r.m31); yd = (r.m12, r.m22, r.m32); zd = (r.m13, r.m23, r.m33) }
        else { xd = (r.m11, r.m12, r.m13); yd = (r.m21, r.m22, r.m23); zd = (r.m31, r.m32, r.m33) }
        func enu(_ v: (Double, Double, Double)) -> SIMD3<Double> { SIMD3(-v.1, v.0, v.2) }   // east = -y_ref, north = x_ref, up = z_ref
        let rawR = enu(xd), rawU = enu(yd), rawF = -enu(zd)
        func unit(_ v: SIMD3<Double>) -> SIMD3<Double> { v / max(1e-9, (v * v).sum().squareRoot()) }
        if let b = smoothedBasis {
            smoothedBasis = (unit(b.r * 0.75 + rawR * 0.25), unit(b.u * 0.75 + rawU * 0.25), unit(b.f * 0.75 + rawF * 0.25))
        } else { smoothedBasis = (rawR, rawU, rawF) }

        let a = 0.25
        if let p = smoothed {
            var n = (p.x * (1 - a) + v.x * a, p.y * (1 - a) + v.y * a, p.z * (1 - a) + v.z * a)
            let len = max(1e-9, (n.0 * n.0 + n.1 * n.1 + n.2 * n.2).squareRoot())
            n = (n.0 / len, n.1 / len, n.2 / len)
            smoothed = n
        } else { smoothed = v }
        guard let sv = smoothed else { return }

        var az = AstronomyEngine.deg(atan2(-sv.y, sv.x))
        let alt = AstronomyEngine.deg(asin(max(-1, min(1, sv.z))))
        var q: Quality
        switch m.magneticField.accuracy {
        case .uncalibrated: q = .uncalibrated
        case .low: q = .low
        case .medium: q = .medium
        case .high: q = .high
        @unknown default: q = .low
        }
        if !usingTrueNorth {
            if let decl = declinationProvider() { az += decl }
            else { q = min(q, .low) }            /
        }
        az = AstronomyEngine.norm360(az)
        lastUpdate = Date()
        sampleCount += 1
        if sampleCount % 3 == 0 || quality != q {
            rawAzimuth = az
            quality = q
            pointing = Horizontal(azimuth: AstronomyEngine.norm360(az + s.azimuthOffset), altitude: alt)
            if let b = smoothedBasis {
                let off = s.azimuthOffset + (usingTrueNorth ? 0 : (declinationProvider() ?? 0))
                basis = DeviceBasis(right: Self.rotateHeading(b.r, by: off), up: Self.rotateHeading(b.u, by: off),
                                    forward: Self.rotateHeading(b.f, by: off))
            }
        }
    }


    private var simAz = 180.0, simAlt = 30.0

    func startSimulated() {
        isRunning = true
        usingTrueNorth = true
        quality = .high
        statusText = "Demo mode: pointing is simulated. Use the demo controls to aim."
        publishSimulated()
        simTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishSimulated() }
        }
    }

    func setSimulated(azimuth: Double, altitude: Double) {
        simAz = AstronomyEngine.norm360(azimuth)
        simAlt = max(-90, min(90, altitude))
        publishSimulated()
    }

    var simulatedPointing: Horizontal { Horizontal(azimuth: simAz, altitude: simAlt) }

    private func publishSimulated() {
        rawAzimuth = simAz
        pointing = Horizontal(azimuth: simAz, altitude: simAlt)
        basis = DeviceBasis.fromLookDirection(azimuth: simAz, altitude: simAlt)
        quality = .high
        lastUpdate = Date()
    }

    private static func rotateHeading(_ v: SIMD3<Double>, by degrees: Double) -> SIMD3<Double> {
        let t = AstronomyEngine.rad(degrees)
        return SIMD3(v.x * cos(t) + v.y * sin(t), v.y * cos(t) - v.x * sin(t), v.z)
    }

    func nudgeAzimuthOffset(by delta: Double) {
        saveAzimuthOffset(AstronomyEngine.norm180(settingsProvider().azimuthOffset + delta))
    }


    func calibrate(toKnownAzimuth expected: Double) {
        guard let raw = rawAzimuth else { return }
        let offset = AstronomyEngine.norm180(expected - raw)
        saveAzimuthOffset(offset)
    }
}

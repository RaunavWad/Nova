//
//  MotionManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import CoreMotion
import Combine

/// The phone's axes expressed in a local East-North-Up frame (x = east, y = north, z = up), after heading corrections.
/// `forward` is where the back camera looks; `right` / `up` are the screen's right and top directions.
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
    /// Compass azimuth and altitude (degrees) of the camera direction.
    var lookAzimuthAltitude: (azimuth: Double, altitude: Double) {
        (AstronomyEngine.norm360(AstronomyEngine.deg(atan2(forward.x, forward.y))),
         AstronomyEngine.deg(asin(max(-1, min(1, forward.z)))))
    }
}

/// Turns CoreMotion attitude into a *world-frame pointing direction* (true azimuth + altitude) with an honest
/// uncertainty estimate.
///
/// Frame: `CMAttitudeReferenceFrame.xTrueNorthZVertical` (x = true north, y = west, z = up; right-handed).
/// Needs location services (to know the declination) and a working magnetometer. If unavailable we fall back to
/// `xMagneticNorthZVertical` and add the declination measured by Core Location's heading (true minus magnetic).
///
/// Device axes: x = right edge, y = top edge, z = out of the screen toward the user.
///   * "Back of phone" pointing direction = -z  (like a camera)
///   * "Top edge" pointing direction      = +y  (like a wand)
///
/// Azimuth is measured clockwise from true north: az = atan2(east, north) = atan2(-y_ref, x_ref); altitude = asin(z_ref).
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
        /// Estimated pointing error (degrees, roughly 1 sigma-ish, deliberately conservative).
        var uncertainty: Double {
            switch self {
            case .high: return 5
            case .medium: return 9
            case .low: return 16
            case .uncalibrated, .unavailable: return 45
            }
        }
    }

    @Published private(set) var pointing: Horizontal?      // calibrated, smoothed (published at ~10 Hz)
    @Published private(set) var rawAzimuth: Double?        // before user offset
    @Published private(set) var quality: Quality = .unavailable
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var usingTrueNorth = false
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Motion sensors not started."
    @Published private(set) var basis: DeviceBasis?       // full orientation, for the Sky Camera overlay

    private let cm = CMMotionManager()
    private var smoothed: (x: Double, y: Double, z: Double)?
    private var smoothedBasis: (r: SIMD3<Double>, u: SIMD3<Double>, f: SIMD3<Double>)?
    private var sampleCount = 0
    private var simTimer: Timer?

    // Wiring (set once at app start)
    var settingsProvider: @MainActor () -> AppSettings = { AppSettings() }
    var declinationProvider: @MainActor () -> Double? = { nil }
    var locationAuthorized: @MainActor () -> Bool = { false }
    var saveAzimuthOffset: @MainActor (Double) -> Void = { _ in }

    // MARK: Derived reliability

    var isFresh: Bool { lastUpdate.map { Date().timeIntervalSince($0) < 1.0 } ?? false }
    var uncertainty: Double { quality.uncertainty }
    /// Directional haptics/speech need decent calibration and a fresh reading.
    var isReliableForGuidance: Bool { isFresh && quality >= .medium && pointing != nil }
    /// Identify can run with lower quality, but then reports wider uncertainty (or says it cannot tell).
    var isUsableForIdentify: Bool { isFresh && quality >= .low && pointing != nil }

    // MARK: Start / stop

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
        cm.showsDeviceMovementDisplay = true   // lets iOS show its own calibration prompt when needed
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

    // MARK: Sensor handling

    private func handle(_ m: CMDeviceMotion) {
        let s = settingsProvider()
        let r = m.attitude.rotationMatrix
        let g = m.gravity   // device frame, unambiguous

        // CoreMotion's matrix may be device->reference or its transpose depending on convention; instead of
        // guessing, test which reading reproduces the measured gravity vector, then use that one.
        func dist(_ a: (Double, Double, Double)) -> Double {
            (a.0 - g.x) * (a.0 - g.x) + (a.1 - g.y) * (a.1 - g.y) + (a.2 - g.z) * (a.2 - g.z)
        }
        let gravityIfRowsAreDeviceZ = (-r.m31, -r.m32, -r.m33)   // R maps device -> reference
        let gravityIfColsAreDeviceZ = (-r.m13, -r.m23, -r.m33)   // R maps reference -> device
        let deviceToRef = dist(gravityIfRowsAreDeviceZ) <= dist(gravityIfColsAreDeviceZ)

        let v: (x: Double, y: Double, z: Double)
        switch (s.pointingMode, deviceToRef) {
        case (.backOfPhone, true):  v = (-r.m13, -r.m23, -r.m33)   // -(device z) in reference coordinates
        case (.backOfPhone, false): v = (-r.m31, -r.m32, -r.m33)
        case (.topEdge, true):      v = (r.m12, r.m22, r.m32)      // device y in reference coordinates
        case (.topEdge, false):     v = (r.m21, r.m22, r.m23)
        }

        // Full device axes in the reference frame (same row/column decision as above), then to East-North-Up.
        let xd: (Double, Double, Double), yd: (Double, Double, Double), zd: (Double, Double, Double)
        if deviceToRef { xd = (r.m11, r.m21, r.m31); yd = (r.m12, r.m22, r.m32); zd = (r.m13, r.m23, r.m33) }
        else { xd = (r.m11, r.m12, r.m13); yd = (r.m21, r.m22, r.m23); zd = (r.m31, r.m32, r.m33) }
        func enu(_ v: (Double, Double, Double)) -> SIMD3<Double> { SIMD3(-v.1, v.0, v.2) }   // east = -y_ref, north = x_ref, up = z_ref
        let rawR = enu(xd), rawU = enu(yd), rawF = -enu(zd)
        func unit(_ v: SIMD3<Double>) -> SIMD3<Double> { v / max(1e-9, (v * v).sum().squareRoot()) }
        if let b = smoothedBasis {
            smoothedBasis = (unit(b.r * 0.75 + rawR * 0.25), unit(b.u * 0.75 + rawU * 0.25), unit(b.f * 0.75 + rawF * 0.25))
        } else { smoothedBasis = (rawR, rawU, rawF) }

        // Low-pass filter on the unit vector (reduces jitter without a heading discontinuity at north).
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
            else { q = min(q, .low) }            // magnetic north without a declination is not trustworthy
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

    // MARK: Demo mode (simulated, never confused with real sensors)

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

    /// Rotates an East-North-Up vector clockwise (seen from above) by `degrees`, matching "azimuth + offset".
    private static func rotateHeading(_ v: SIMD3<Double>, by degrees: Double) -> SIMD3<Double> {
        let t = AstronomyEngine.rad(degrees)
        return SIMD3(v.x * cos(t) + v.y * sin(t), v.y * cos(t) - v.x * sin(t), v.z)
    }

    /// Adds `delta` degrees to the saved heading adjustment (used by Sky Camera: "the cross is on the Moon").
    func nudgeAzimuthOffset(by delta: Double) {
        saveAzimuthOffset(AstronomyEngine.norm180(settingsProvider().azimuthOffset + delta))
    }

    // MARK: Calibration

    /// Sets the heading offset so that the current raw heading equals a known true azimuth
    /// (for example, when a sighted helper confirms the Moon or a known landmark direction).
    func calibrate(toKnownAzimuth expected: Double) {
        guard let raw = rawAzimuth else { return }
        let offset = AstronomyEngine.norm180(expected - raw)
        saveAzimuthOffset(offset)
    }
}

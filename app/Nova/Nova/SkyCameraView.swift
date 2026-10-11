//
//  SkyCameraView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import CoreLocation
import Combine
import SwiftUI
@preconcurrency import AVFoundation


@MainActor
final class CameraManager: ObservableObject {
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var hasCamera = true
    @Published private(set) var missingUsageText = false
    @Published private(set) var fieldOfView: Double = 65
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "nova.camera")
    private var configured = false

    func start() async {
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            missingUsageText = true
            return
        }
        if authorization == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard authorization == .authorized else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            hasCamera = false; return
        }
        if !configured { configure(device) }
        let s = session
        queue.async { if !s.isRunning { s.startRunning() } }
    }

    func stop() {
        let s = session
        queue.async { if s.isRunning { s.stopRunning() } }
    }

    private func configure(_ device: AVCaptureDevice) {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        let f = Double(device.activeFormat.videoFieldOfView)
        if f > 20 && f < 140 { fieldOfView = f }
        configured = true
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let c = previewLayer.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }   // app is portrait-only
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}


struct ProjectedObject: Identifiable {
    let object: CelestialObject
    let point: CGPoint
    let yaw: Double      
    let pitch: Double
    let onScreen: Bool
    var id: String { object.id }
}

enum SkyProjection {
    static func project(_ items: [(object: CelestialObject, pos: Horizontal)], basis: DeviceBasis,
                        size: CGSize, fovLong: Double) -> [ProjectedObject] {
        guard size.width > 0, size.height > 0 else { return [] }
        let tanV = tan(AstronomyEngine.rad(fovLong) / 2)
        let tanH = tanV * Double(size.width / size.height)
        var out: [ProjectedObject] = []
        for item in items {
            let a = AstronomyEngine.rad(item.pos.azimuth), h = AstronomyEngine.rad(item.pos.altitude)
            let d = SIMD3<Double>(sin(a) * cos(h), cos(a) * cos(h), sin(h))
            let xc = (d * basis.right).sum(), yc = (d * basis.up).sum(), zc = (d * basis.forward).sum()
            guard zc > 0.02 else { continue }
            let nx = xc / zc / tanH, ny = yc / zc / tanV
            let p = CGPoint(x: size.width / 2 * CGFloat(1 + nx), y: size.height / 2 * CGFloat(1 - ny))
            out.append(ProjectedObject(object: item.object, point: p,
                                       yaw: AstronomyEngine.deg(atan2(xc, zc)), pitch: AstronomyEngine.deg(atan2(yc, zc)),
                                       onScreen: abs(nx) <= 1 && abs(ny) <= 1))
        }
        return out
    }
}


struct SkyCameraView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var achievements: AchievementManager
    @EnvironmentObject var haptics: HapticsManager
    @StateObject private var camera = CameraManager()

    @State private var items: [(object: CelestialObject, pos: Horizontal)] = []

    private var demo: Bool { persistence.settings.demoMode }

    var body: some View {
        ZStack {
            StarfieldBackground()
            if camera.authorization == .authorized && camera.hasCamera && !demo {
                CameraPreview(session: camera.session).ignoresSafeArea().accessibilityHidden(true)
            }
            GeometryReader { geo in
                overlay(size: geo.size)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                notePanel
                Spacer(minLength: 0)
                controls
            }
            .padding(12)
        }
        .navigationTitle("Sky Camera")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .task {
            location.start()
            motion.start()
            if !demo { await camera.start() }
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onDisappear { camera.stop(); motion.stop(); speech.stop() }
    }


    @ViewBuilder private func overlay(size: CGSize) -> some View {
        if let basis = motion.basis {
            let projected = SkyProjection.project(items, basis: basis, size: size, fovLong: camera.fieldOfView)
            ZStack {
                ForEach(projected.filter(\.onScreen)) { p in
                    VStack(spacing: 2) {
                        Circle().strokeBorder(Theme.violet, lineWidth: 2).frame(width: 26, height: 26)
                        Text(p.object.title)
                            .font(AppFont.style(.footnote, .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    .position(p.point)
                }
                Image(systemName: "plus").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.textSecondary)
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    private var notePanel: some View {
        Panel {
            Text("A visual aid for sighted helpers").sectionHeader()
            Text("Labels come from calculation (your location, the time and the phone's orientation), not from analysing the picture, and can be several degrees off. Clouds and buildings can't be detected. Nothing from the camera is saved or analysed.")
                .font(AppFont.style(.footnote))
            if camera.missingUsageText {
                Text("The camera can't start because the app is missing its camera permission text. In Xcode, open the Nova target, then Info, and add Privacy - Camera Usage Description. The buttons below still work.")
                    .font(AppFont.style(.footnote)).foregroundStyle(Theme.violet)
            } else if camera.authorization == .denied || camera.authorization == .restricted {
                Text("Camera access is off. Turn it on in the iPhone Settings app under Nova to see the live view. The buttons below still work.")
                    .font(AppFont.style(.footnote)).foregroundStyle(Theme.violet)
            } else if !demo && !camera.hasCamera {
                Text("No camera is available on this device. The buttons below still work.")
                    .font(AppFont.style(.footnote)).foregroundStyle(Theme.violet)
            } else if demo {
                Text("Demo mode: simulated pointing, no camera picture.").font(AppFont.style(.footnote)).foregroundStyle(Theme.violet)
            }
        }
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            AppButton(title: "What's in the middle of the view?", systemImage: "scope",
                      hint: "Tells you which object should be at the center of the camera view") { identifyCenter() }
            AppButton(title: "Describe the view", systemImage: "text.viewfinder", prominent: false,
                      hint: "Lists the objects that should be in view and where they are relative to the center") { describeView() }
            calibrateMenu
            DemoControls()
        }
        .padding(10)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 22))
    }

    private var calibrateMenu: some View {
        Menu {
            ForEach(items.filter { $0.pos.altitude > 3 }, id: \.object.id) { item in
                Button(item.object.title) { calibrate(to: item) }
            }
        } label: {
            Label("Align labels: the cross is on...", systemImage: "arrow.left.and.right")
        }
        .buttonStyle(BigButtonStyle(prominent: false))
        .disabled(demo || motion.basis == nil)
        .accessibilityHint("A sighted helper puts a known object under the cross, then picks it here to correct the compass")
    }


    private func refresh() {
        guard let c = location.coordinate(demo: demo) else { items = []; return }
        let now = Date()
        items = Catalog.locatable.compactMap { o in
            if o.kind == .star, (o.magnitude ?? 9) > 3.0 { return nil }      
            guard let p = AstronomyEngine.position(of: o, date: now, latitude: c.latitude, longitude: c.longitude), p.altitude > -2 else { return nil }
            return (o, p)
        }
    }

    private func identifyCenter() {
        guard let basis = motion.basis, let c = location.coordinate(demo: demo), motion.isUsableForIdentify else {
            haptics.play(.warning)
            speech.narrate("I don't have a reliable orientation reading. \(motion.quality.spoken) Try calibrating the compass.")
            return
        }
        let look = basis.lookAzimuthAltitude
        let r = ObjectMatcher.match(pointing: Horizontal(azimuth: look.azimuth, altitude: look.altitude), uncertainty: motion.uncertainty,
                                    date: Date(), latitude: c.latitude, longitude: c.longitude)
        switch r {
        case .confident(let o, _):
            speech.narrate("In the middle of the view: \(o.spokenName). \(o.short)")
            achievements.celebrateDiscovery(o, method: .identified)
        case .ambiguous(let list):
            speech.narrate("Several objects are near the middle: " + list.map { $0.object.spokenName }.joined(separator: ", or ") + ".")
        case .nothingNear(let n, let sep, let dAz, let dAlt):
            speech.narrate("Nothing bright is expected in the middle. The nearest is \(n.spokenName), about \(Int(sep.rounded())) degrees away: \(ObjectMatcher.relativeDirection(dAzimuth: dAz, dAltitude: dAlt)).")
        case .belowHorizon:
            speech.narrate("The camera is pointing below the horizon.")
        case .unreliable(let why):
            speech.narrate(why)
        }
    }

    private func describeView() {
        guard let basis = motion.basis else { speech.narrate("I don't have an orientation reading yet."); return }
        let visible = SkyProjection.project(items, basis: basis, size: CGSize(width: 9, height: 19.5), fovLong: camera.fieldOfView)
            .filter(\.onScreen).sorted { abs($0.yaw) + abs($0.pitch) < abs($1.yaw) + abs($1.pitch) }
        guard !visible.isEmpty else {
            speech.narrate("None of the objects I know should be in view right now. Move the phone and try again."); return
        }
        let parts = visible.map { "\($0.object.spokenName), \(ObjectMatcher.relativeDirection(dAzimuth: $0.yaw, dAltitude: $0.pitch))" }
        speech.narrate("In view: " + parts.joined(separator: ". ") + ".")
    }

    private func calibrate(to item: (object: CelestialObject, pos: Horizontal)) {
        guard let basis = motion.basis else { return }
        let cam = basis.lookAzimuthAltitude
        let delta = AstronomyEngine.norm180(item.pos.azimuth - cam.azimuth)
        motion.nudgeAzimuthOffset(by: delta)
        haptics.play(.aligned)
        speech.narrate("Compass adjusted by \(Int(abs(delta).rounded())) degrees to the \(delta > 0 ? "right" : "left"), using \(item.object.spokenName). Only do this when the real object is under the cross.")
    }
}

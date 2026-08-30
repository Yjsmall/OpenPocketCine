import AVFoundation
import SwiftUI


/// macOS operator root. Same spine as the iOS shell — `AppModel` owns the
/// `CameraSession` — but windowed chrome instead of the portrait monitor rails.
struct MacRootView: View {
    @Environment(AppModel.self) private var model
    @State private var showMedia = false

    var body: some View {
        ZStack {
            LiveDesign.background.ignoresSafeArea()
            if model.isLive {
                if showMedia {
                    MediaLibraryView(safeArea: EdgeInsets()) { showMedia = false }
                } else {
                    MacLiveView(onMedia: { showMedia = true })
                }
            } else {
                MacConnectView()
            }
        }
        .onAppear {
            model.prepareStartup()
            KeepScreenAwake.setEnabled(model.keepScreenAwake)
        }
        .onChange(of: model.keepScreenAwake) { _, awake in
            KeepScreenAwake.setEnabled(awake)
        }
        .onChange(of: model.isLive) { _, live in
            if live {
                model.noteBecameLive()
            } else {
                model.noteLeftLive()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: KeepScreenAwake.resignActiveNotification)
        ) { _ in
            model.session.noteSceneBecameInactive()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: KeepScreenAwake.becameActiveNotification)
        ) { _ in
            model.session.noteSceneBecameActive()
        }
    }
}

/// Connect: saved cameras on the left, live scan on the right, phase strip below.
private struct MacConnectView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            savedColumn
                .frame(maxWidth: .infinity)
            Divider()
            scanColumn
                .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            phaseStrip
        }
    }

    private var savedColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved cameras")
                .font(LiveType.text(13, weight: .semibold))
                .foregroundStyle(LiveDesign.muted)
            if model.savedCameras.isEmpty {
                Text("Paired cameras land here.")
                    .foregroundStyle(LiveDesign.muted)
            }
            ForEach(model.savedCameras) { camera in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.advertisedName)
                            .font(LiveType.text(15, weight: .medium))
                        Text(camera.lastSSID ?? camera.modelName)
                            .font(LiveType.text(12))
                            .foregroundStyle(LiveDesign.muted)
                    }
                    Spacer()
                    Button("Connect") { model.reconnect(camera) }
                        .buttonStyle(.borderedProminent)
                    Button("Forget", role: .destructive) { model.forget(camera) }
                        .buttonStyle(.bordered)
                }
                .padding(10)
                .background(LiveDesign.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var scanColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby cameras")
                    .font(LiveType.text(13, weight: .semibold))
                    .foregroundStyle(LiveDesign.muted)
                Spacer()
                if model.session.phase == .scanning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { model.session.disconnect() }
                } else {
                    Button("Pair new camera") { model.pairNewCamera() }
                }
            }
            ForEach(model.session.found) { camera in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(camera.name.isEmpty ? camera.model.name : camera.name)
                            .font(LiveType.text(15, weight: .medium))
                        Text(camera.model.name)
                            .font(LiveType.text(12))
                            .foregroundStyle(LiveDesign.muted)
                    }
                    Spacer()
                    Button("Connect") { model.session.connect(camera) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(10)
                .background(LiveDesign.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var phaseStrip: some View {
        HStack(spacing: 10) {
            if case .failed(let why) = model.session.phase {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(model.session.phase.label)
                Button("Retry scan") { model.pairNewCamera() }
            } else if model.session.phase != .idle {
                ProgressView().controlSize(.small)
                Text(model.session.phase.label)
            } else {
                Text("Bluetooth pairing → camera Wi-Fi → live view.")
                    .foregroundStyle(LiveDesign.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Live: full-bleed HEVC surface with a compact status deck and record control.
private struct MacLiveView: View {
    @Environment(AppModel.self) private var model
    var onMedia: () -> Void = {}
    private var session: CameraSession { model.session }

    var body: some View {
        ZStack {
            VideoSurface(layer: session.videoLayer)
                .ignoresSafeArea()
            VStack {
                statusDeck
                Spacer()
                controlBar
            }
        }
    }

    private var statusDeck: some View {
        HStack(spacing: 14) {
            if session.status.isRecording {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text(Self.timecode(session.status.recordElapsedSec))
                    .monospacedDigit()
            }
            Text("\(session.status.batteryPercent)%")
            Text(Self.gigabytes(session.status.sdFreeMb))
            Text("\(session.status.fps) fps")
            Text(session.liveFPS)
            if session.status.iso > 0 {
                Text("ISO \(session.status.iso)")
            }
            if session.status.shutterDenom > 0 {
                Text("1/\(session.status.shutterDenom)")
            }
            Spacer()
        }
        .font(LiveType.text(13, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    private var controlBar: some View {
        HStack {
            modeChip
            Button {
                onMedia()
            } label: {
                Label("Media", systemImage: "photo.on.rectangle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .help("Browse the camera SD card")
            Spacer()
            shutterButton
            Spacer()
            Button("Disconnect") { session.disconnect() }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    /// Video / Photo mode. Nil (unknown) stays disabled — unknown mode bytes
    /// must never reach the wire (a swept mode set once froze a Nano).
    private var modeChip: some View {
        Button {
            if session.currentShootingMode?.isPhoto == true {
                session.setShootingMode(.video)
            } else {
                session.setPhotoMode()
            }
        } label: {
            Text(session.currentShootingMode?.label.uppercased() ?? "MODE")
                .font(LiveType.text(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(session.currentShootingMode == nil)
        .help("Switch shooting mode")
    }

    /// Smart shutter: fires a still in Photo / SuperNight, starts or stops
    /// video otherwise (CameraSession.pressShutter owns that decision).
    private var shutterButton: some View {
        Button {
            session.pressShutter()
        } label: {
            let photo = session.currentShootingMode?.isPhoto == true
            Image(
                systemName: photo
                    ? "camera.fill"
                    : (session.status.isRecording ? "stop.fill" : "record.circle")
            )
            .font(.system(size: 30))
            .foregroundStyle(
                !photo && session.status.isRecording ? Color.red : Color.white)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .help(
            session.currentShootingMode?.isPhoto == true
                ? "Take photo"
                : (session.status.isRecording ? "Stop recording" : "Start recording"))
    }

    private static func timecode(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private static func gigabytes(_ freeMb: Int) -> String {
        guard freeMb > 0 else { return "—" }
        return String(format: "%.1f GB free", Double(freeMb) / 1024)
    }
}

/// Hosts the decoder's `AVSampleBufferDisplayLayer` (the identity HEVC path).
/// The decoder enqueues into this layer directly; gravity handles aspect fit.
struct VideoSurface: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.install(layer)
        return view
    }

    func updateNSView(_ view: LayerHostView, context: Context) {
        view.install(layer)
    }

    final class LayerHostView: NSView {
        private weak var hosted: AVSampleBufferDisplayLayer?

        func install(_ layer: AVSampleBufferDisplayLayer) {
            wantsLayer = true
            layer.videoGravity = .resizeAspect
            if hosted !== layer {
                hosted?.removeFromSuperlayer()
                self.layer?.addSublayer(layer)
                hosted = layer
            }
            needsLayout = true
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}

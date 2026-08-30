import AVFoundation
import OpenPocketViewCore
import SwiftUI
import AppKit

/// Hosts the HEVC display layer and the Core Image feed (used only while GPU assists are on).
/// `effects` and `sampleBus` are read here so toggling PEAK/LUT/WAVE refreshes this representable
/// and pushes the current stack + bus into the decoder — LiveViewScreen body otherwise never
/// observes those flags (previous bug: `onChange(of: assist.effects)` never fired).
///
/// Mirror is OpenZCine `LiveFrameRaster.feedScale`: a negative-X transform on a host view
/// that wraps both renderers. Applied at present time (not SwiftUI `scaleEffect`) so
/// MIRROR assist lands with the presented picture.
struct VideoView: View {
    let decoder: HevcDecoder
    var effects: LiveImageEffects
    var sampleBus: LiveFrameSampleBus
    /// `CameraStatus.monitorTransfer` (ColorMode `3F`/`3C`/`17`/`41`). Simulator clip is `.dlog2`.
    var transfer: MonitorTransfer?
    /// MIRROR assist. Applied on the host view so reconnect cannot skip it.
    var pictureFlip = false

    var body: some View {
        VideoDisplayRepresentable(
            decoder: decoder,
            effects: rasterEffects,
            assistMirror: effects.mirror,
            pictureFlip: pictureFlip,
            sampleBus: sampleBus,
            transfer: transfer,
            feedUpscaler: FeedUpscaleSwitch.shared.upscaler
        )
        .transaction { $0.animation = nil }
    }

    /// Mirror stays a view-space flip so the GPU path does not also flip the buffer.
    private var rasterEffects: LiveImageEffects {
        var fx = effects
        fx.mirror = false
        return fx
    }
}

private struct VideoDisplayRepresentable: NSViewRepresentable {
    let decoder: HevcDecoder
    var effects: LiveImageEffects
    var assistMirror: Bool
    var pictureFlip: Bool
    var sampleBus: LiveFrameSampleBus
    var transfer: MonitorTransfer?
    var feedUpscaler: FeedUpscaler

    func makeNSView(context: Context) -> DisplayLayerView {
        let view = DisplayLayerView(decoder.displayLayer)
        view.onReady = { [decoder] in decoder.noteDisplayReady() }
        decoder.processedFeed = view.ciFeed
        bindMirror(decoder, view: view)
        wire(decoder)
        return view
    }

    func updateNSView(_ view: DisplayLayerView, context: Context) {
        view.onReady = { [decoder] in decoder.noteDisplayReady() }
        decoder.processedFeed = view.ciFeed
        bindMirror(decoder, view: view)
        guard
            decoder.sampleBus !== sampleBus
                || decoder.effects != effects
                || decoder.feedUpscaler != feedUpscaler
                || decoder.assistMirror != assistMirror
                || (transfer != nil && decoder.incomingTransfer != transfer)
        else { return }
        wire(decoder)
    }

    private func bindMirror(_ decoder: HevcDecoder, view: DisplayLayerView) {
        decoder.applyPictureMirror = { [weak view] mirrored in
            view?.setPictureMirrored(mirrored)
        }
        decoder.assistMirror = assistMirror
    }

    private func wire(_ decoder: HevcDecoder) {
        decoder.sampleBus = sampleBus
        decoder.effects = effects
        decoder.feedUpscaler = feedUpscaler
        decoder.adoptIncomingTransfer(transfer)
        decoder.startSimulatorSampleIfNeeded()
    }
}

final class DisplayLayerView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer
    private let pictureHost = NSView()
    private var pictureMirrored = false
    let ciFeed = CIFeedView()
    var onReady: (() -> Void)?

    init(_ avLayer: AVSampleBufferDisplayLayer) {
        displayLayer = avLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        avLayer.videoGravity = .resizeAspect
        addSubview(pictureHost)
        pictureHost.layer?.backgroundColor = NSColor.black.cgColor
        pictureHost.layer?.addSublayer(avLayer)
        pictureHost.addSubview(ciFeed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPictureMirrored(_ mirrored: Bool) {
        pictureMirrored = mirrored
        applyPictureTransform()
    }

    private func applyPictureTransform() {
        let x = MirrorAssist.feedScale(mirrored: pictureMirrored).width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureHost.layer?.setAffineTransform(
            CGAffineTransform(scaleX: x, y: 1))
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ciFeed.isEnabled = window != nil
    }

    override func layout() {
        super.layout()
        pictureHost.bounds = CGRect(origin: .zero, size: bounds.size)
        pictureHost.frame.origin = CGPoint(x: bounds.midX - bounds.width / 2, y: bounds.midY - bounds.height / 2)
        displayLayer.frame = pictureHost.bounds
        ciFeed.frame = pictureHost.bounds
        applyPictureTransform()
        ciFeed.isEnabled = window != nil && bounds.width > 1 && bounds.height > 1
        if bounds.width > 1, bounds.height > 1 { onReady?() }
    }
}

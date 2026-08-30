import AppKit
import OpenPocketViewCore
import SwiftUI

/// Mac media browser over the camera's SD card. Same driver as the iOS
/// library — `CameraSession`'s media extension (DUML manifest + SoftAP HTTP
/// thumbnails/originals) — with windowed chrome. Browsing suspends the live
/// stream and resumes it on close (`beginMediaBrowse` / `endMediaBrowse`).
struct MediaLibraryView: View {
    let safeArea: EdgeInsets
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    private var session: CameraSession { model.session }

    @State private var filter: Filter = .all
    @State private var selected: MediaFile?
    @State private var confirmDelete: MediaFile?
    @State private var selectionMode = false
    @State private var multiSelection: Set<MediaFile> = []
    @State private var confirmBatchDelete = false
    @State private var deleting = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, photos, videos
        var id: String { rawValue }

        func matches(_ file: MediaFile) -> Bool {
            switch self {
            case .all: return true
            case .photos: return !Self.isVideo(file)
            case .videos: return Self.isVideo(file)
            }
        }

        static func isVideo(_ file: MediaFile) -> Bool {
            file.durationSeconds > 0
                || ["mp4", "mov", "dji", "lrf", "xrf"].contains(
                    fileExt(file.path).lowercased())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(alignment: .top, spacing: 0) {
                grid
                if let selected {
                    Divider()
                    detail(file: selected)
                        .frame(width: 300)
                }
            }
        }
        .padding(.top, max(0, safeArea.top))
        .background(LiveDesign.background.ignoresSafeArea())
        .onAppear { session.beginMediaBrowse() }
        .onDisappear { session.endMediaBrowse() }
        .confirmationDialog(
            "Delete \(multiSelection.count) files from the camera SD card?",
            isPresented: $confirmBatchDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(multiSelection.count) Files", role: .destructive) {
                Task {
                    deleting = true
                    await session.deleteMediaFiles(Array(multiSelection))
                    multiSelection = []
                    selectionMode = false
                    deleting = false
                    selected = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes them from the card. Copies already downloaded to the Mac stay."
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Camera media")
                .font(LiveType.text(15, weight: .semibold))
            ForEach(Filter.allCases) { tab in
                Button(tab.rawValue) { filter = tab; if !tab.matches(selected ?? .init(path: "", thumbPath: "")) { selected = nil } }
                    .buttonStyle(.plain)
                    .foregroundStyle(filter == tab ? Color.white : LiveDesign.muted)
            }
            Spacer()
            if session.mediaFetchInProgress {
                ProgressView().controlSize(.small)
                Text("Listed \(session.mediaFetchListedCount)…")
                    .foregroundStyle(LiveDesign.muted)
            }
            if let note = session.mediaNote {
                Text(note).foregroundStyle(LiveDesign.muted)
            }
            if deleting {
                ProgressView().controlSize(.small)
                Text("Deleting…").foregroundStyle(LiveDesign.muted)
            } else if selectionMode {
                Text("\(multiSelection.count) selected")
                    .foregroundStyle(LiveDesign.muted)
                Button("Delete \(multiSelection.count)…", role: .destructive) {
                    confirmBatchDelete = true
                }
                .disabled(multiSelection.isEmpty)
                Button("Done") {
                    selectionMode = false
                    multiSelection = []
                }
            } else {
                Button("Select") { selectionMode = true }
            }
            Button("Refresh") { session.refreshMedia() }
            Button("Close") { onClose() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var visibleFiles: [MediaFile] {
        session.mediaFiles.filter { filter.matches($0) }
            .sorted { $0.path > $1.path }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)],
                spacing: 12
            ) {
                ForEach(visibleFiles) { file in
                    MediaCell(
                        session: session, file: file, isSelected: selected == file,
                        selectionMode: selectionMode,
                        isMarked: multiSelection.contains(file)
                    )
                    .onTapGesture {
                        if selectionMode {
                            if multiSelection.contains(file) {
                                multiSelection.remove(file)
                            } else {
                                multiSelection.insert(file)
                            }
                            selected = nil
                        } else {
                            selected = file
                        }
                    }
                }
            }
            .padding(16)
        }
        .overlay {
            if !session.mediaFetchInProgress && visibleFiles.isEmpty {
                Text(
                    session.canReachCameraMedia
                        ? "No media listed yet — press Refresh."
                        : "Connect to the camera to browse its SD card."
                )
                .foregroundStyle(LiveDesign.muted)
            }
        }
    }

    private func detail(file: MediaFile) -> some View {
        MediaDetail(session: session, file: file, confirmDelete: $confirmDelete)
    }

    static func fileExt(_ path: String) -> String {
        (path as NSString).pathExtension
    }

    static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

private struct MediaCell: View {
    let session: CameraSession
    let file: MediaFile
    let isSelected: Bool
    var selectionMode = false
    var isMarked = false

    @State private var thumb: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(16 / 9, contentMode: .fit)
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipped()
                }
                if MediaLibraryView.Filter.isVideo(file) && file.durationSeconds > 0 {
                    Text(Self.duration(file.durationSeconds))
                        .font(LiveType.text(11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.white : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topLeading) {
                if selectionMode {
                    Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isMarked ? Color.white : Color.white.opacity(0.55))
                        .padding(6)
                        .shadow(radius: 2)
                }
            }
            .cornerRadius(8)
            .task(id: file.path) {
                await session.ensureThumbnail(for: file)
                thumb = session.thumbnailURL(for: file).flatMap { NSImage(contentsOf: $0) }
            }
            HStack(spacing: 4) {
                if session.isFavorite(file) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
                Text(MediaLibraryView.fileName(file.path))
                    .font(LiveType.text(11))
                    .lineLimit(1)
                    .foregroundStyle(LiveDesign.muted)
            }
        }
        .contentShape(Rectangle())
    }

    private static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MediaDetail: View {
    let session: CameraSession
    let file: MediaFile
    @Binding var confirmDelete: MediaFile?

    @State private var thumb: NSImage?
    @State private var busy = false

    private var progress: Double? {
        session.mediaDownloadProgress[file.path]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .aspectRatio(16 / 9, contentMode: .fit)
                    if let thumb {
                        Image(nsImage: thumb).resizable().scaledToFit()
                            .aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                .cornerRadius(8)
                .task(id: file.path) {
                    await session.ensureThumbnail(for: file)
                    thumb = session.thumbnailURL(for: file).flatMap { NSImage(contentsOf: $0) }
                }

                Text(MediaLibraryView.fileName(file.path))
                    .font(LiveType.text(14, weight: .semibold))
                Text(Self.infoLine(file))
                    .font(LiveType.text(12))
                    .foregroundStyle(LiveDesign.muted)

                if let progress {
                    ProgressView(value: progress)
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(LiveType.text(12))
                        .foregroundStyle(LiveDesign.muted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if session.isDownloaded(file) {
                        Label("On this Mac", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Save to Mac…") { save() }
                            .disabled(busy)
                        Button("Reveal in Finder") { reveal() }
                            .disabled(busy)
                    } else {
                        Button("Download from camera") {
                            Task { await download() }
                        }
                        .disabled(busy || !session.canReachCameraMedia)
                    }
                    Button {
                        session.toggleFavorite(file)
                    } label: {
                        Label(
                            session.isFavorite(file) ? "Unstar" : "Star",
                            systemImage: session.isFavorite(file) ? "star.fill" : "star")
                    }
                    Button("Delete from camera…", role: .destructive) {
                        confirmDelete = file
                    }
                    .disabled(busy || !session.canReachCameraMedia)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
        }
        .confirmationDialog(
            "Delete \(MediaLibraryView.fileName(file.path)) from the camera SD card?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    busy = true
                    await session.deleteMediaFiles([file])
                    busy = false
                    confirmDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This removes the only copy on the card. The Mac has no backup unless you downloaded it first.")
        }
    }

    private func download() async {
        busy = true
        await session.download(file: file)
        busy = false
    }

    private func save() {
        guard let local = session.localURL(for: file) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MediaLibraryView.fileName(file.path)
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: local, to: dest)
        }
    }

    private func reveal() {
        guard let local = session.localURL(for: file) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([local])
    }

    private static func infoLine(_ file: MediaFile) -> String {
        var parts: [String] = [ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file)]
        if file.durationSeconds > 0 {
            parts.append(String(format: "%d:%02d", file.durationSeconds / 60, file.durationSeconds % 60))
        }
        if let resolution = file.resolution { parts.append(resolution) }
        if let fps = file.fps, fps > 0 { parts.append("\(fps) fps") }
        return parts.joined(separator: " · ")
    }
}

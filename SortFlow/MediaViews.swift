import SwiftUI
import AppKit
import AVKit
import Quartz
import ImageIO
import QuickLookThumbnailing

extension Color {
    init(hex: String) {
        var number: UInt64 = 0; Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&number)
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}
// Własny LRU: budżet dotyczy wyłącznie bitmap przechowywanych w cache.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()
    private let previews: OperationQueue = { let q = OperationQueue(); q.name = "SortFlow.Preview"; q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q }()
    private let thumbnails: OperationQueue = { let q = OperationQueue(); q.name = "SortFlow.Thumbnails"; q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q }()
    private let lock = NSLock()
    private var cache: [String: (CGImage, Int)] = [:]
    private var order: [String] = []
    private var cost = 0
    private let budget = 16 * 1024 * 1024
    private var pressure: DispatchSourceMemoryPressure?
    private init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.clear() }; source.resume(); pressure = source
    }
    func clear() { lock.lock(); cache.removeAll(); order.removeAll(); cost = 0; lock.unlock() }
    private func cached(_ key: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard let value = cache[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key); return value.0
    }
    private func insert(_ image: CGImage, key: String) {
        let bytes = image.bytesPerRow * image.height
        guard bytes <= budget else { return }
        lock.lock(); defer { lock.unlock() }
        if let previous = cache.removeValue(forKey: key) { cost -= previous.1; order.removeAll { $0 == key } }
        while cost + bytes > budget, let oldest = order.first {
            order.removeFirst(); if let removed = cache.removeValue(forKey: oldest) { cost -= removed.1 }
        }
        cache[key] = (image, bytes); order.append(key); cost += bytes
    }
    func load(_ url: URL, pixels: Int, thumbnail: Bool) async -> CGImage? {
        let flag = CancellationFlag()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                (thumbnail ? thumbnails : previews).addOperation {
                    if flag.isCancelled { continuation.resume(returning: nil); return }
                    let entry = try? FileEntry.read(url)
                    let key = "\(url.path)|\(entry?.size ?? 0)|\(entry?.modified.timeIntervalSince1970 ?? 0)|\(pixels)"
                    if let cached = self.cached(key) { continuation.resume(returning: flag.isCancelled ? nil : cached); return }
                    let image: CGImage? = autoreleasepool {
                        guard !flag.isCancelled else { return nil }
                        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                        if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) {
                            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceShouldCacheImmediately: true]
                            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                        }
                        guard thumbnail, !flag.isCancelled else { return nil }
                        return self.quickLook(url, pixels: pixels, flag: flag)
                    }
                    guard !flag.isCancelled else { continuation.resume(returning: nil); return }
                    if thumbnail, let image { self.insert(image, key: key) }
                    continuation.resume(returning: image)
                }
            }
        }, onCancel: { flag.cancel() })
    }
    private func quickLook(_ url: URL, pixels: Int, flag: CancellationFlag) -> CGImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixels, height: pixels), scale: 1, representationTypes: .thumbnail)
        let semaphore = DispatchSemaphore(value: 0)
        let result = ThumbnailResult()
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            result.set(representation?.cgImage); semaphore.signal()
        }
        let deadline = Date().addingTimeInterval(12)
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            if flag.isCancelled || Date() > deadline { QLThumbnailGenerator.shared.cancel(request); return nil }
        }
        return result.get()
    }
}
private final class ThumbnailResult: @unchecked Sendable {
    private let lock = NSLock(); private var image: CGImage?
    func set(_ value: CGImage?) { lock.lock(); image = value; lock.unlock() }
    func get() -> CGImage? { lock.lock(); defer { lock.unlock() }; return image }
}
struct FileThumbnail: View {
    let file: FileEntry
    @AppStorage("lowMemory") private var lowMemory = true
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            else { Image(systemName: file.kind.symbol).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.frame(width: 30, height: 30).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
            .task(id: file) {
                image = nil
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                let value = await ImagePipeline.shared.load(file.url, pixels: lowMemory ? 60 : 90, thumbnail: true)
                if !Task.isCancelled { image = value }
            }.onDisappear { image = nil }
    }
}
struct ImagePreview: View {
    let url: URL
    var sharedZoom: Binding<Double>?
    @AppStorage("lowMemory") private var lowMemory = true
    @AppStorage("previewStyle") private var style: PreviewStyle = .fit
    @State private var image: CGImage?
    @State private var zoom = 1.0
    @State private var rotation = 0.0
    @State private var offset = CGSize.zero
    @State private var startOffset = CGSize.zero
    @State private var startZoom = 1.0
    @State private var failed = false
    @State private var requestedPixels = 1024
    private var effectiveZoom: Double { sharedZoom?.wrappedValue ?? zoom }
    private func setZoom(_ value: Double) { let value = min(max(value, 0.25), 8); if let sharedZoom { sharedZoom.wrappedValue = value } else { zoom = value } }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .textBackgroundColor)
                if let image {
                    if style == .blur && !lowMemory {
                        Image(decorative: image, scale: 1).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).blur(radius: 24).opacity(0.45).clipped()
                    }
                    Image(decorative: image, scale: 1).resizable()
                        .aspectRatio(contentMode: style == .fill ? .fill : .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(effectiveZoom).rotationEffect(.degrees(rotation)).offset(offset)
                        .gesture(MagnificationGesture().onChanged { setZoom(startZoom * $0) }.onEnded { _ in startZoom = effectiveZoom })
                        .simultaneousGesture(DragGesture().onChanged { offset = CGSize(width: startOffset.width + $0.translation.width, height: startOffset.height + $0.translation.height) }.onEnded { _ in startOffset = offset })
                } else if failed { ContentUnavailableView(tr("Brak podglądu", "Preview unavailable"), systemImage: "doc.questionmark", description: Text(tr("Otwórz plik w domyślnej aplikacji", "Open the file in its default app"))) }
                else { ProgressView() }
            }.clipped()
                .overlay(alignment: .bottom) {
                    HStack(spacing: 12) {
                        Button { setZoom(effectiveZoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                        Text("\(Int(effectiveZoom * 100))%").monospacedDigit().frame(width: 50)
                        Button { setZoom(effectiveZoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                        Button(tr("Dopasuj", "Fit")) { setZoom(1); startZoom = 1; offset = .zero; startOffset = .zero }
                        Button("1:1") {
                            if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                               let width = props[kCGImagePropertyPixelWidth] as? Double, let height = props[kCGImagePropertyPixelHeight] as? Double {
                                let scale = NSScreen.main?.backingScaleFactor ?? 2
                                setZoom(max(width / max(geometry.size.width * scale, 1), height / max(geometry.size.height * scale, 1)))
                            }
                        }.help(tr("Skala oryginalnych pikseli; rozdzielczość podglądu ogranicza tryb RAM", "Original pixel scale; preview resolution is bounded by RAM mode"))
                        Button { rotation += 90 } label: { Image(systemName: "rotate.right") }
                    }.buttonStyle(.borderless).padding(10).background(.regularMaterial, in: Capsule()).padding(12)
                }
                .onAppear { updatePixels(geometry.size) }
                .onChange(of: geometry.size) { _, size in updatePixels(size) }
        }
        .task(id: "\(url.path)|\(requestedPixels)|\(lowMemory)|\(effectiveZoom > 1.1)") {
            image = nil; failed = false
            do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
            let pixels = min(lowMemory ? 1024 : 4096, effectiveZoom > 1.1 ? requestedPixels * 2 : requestedPixels)
            let value = await ImagePipeline.shared.load(url, pixels: max(256, pixels), thumbnail: false)
            guard !Task.isCancelled else { return }; image = value; failed = value == nil
        }
        .onChange(of: url) { _, _ in image = nil; zoom = 1; offset = .zero; startOffset = .zero; rotation = 0; startZoom = 1 }
        .onChange(of: lowMemory) { _, _ in ImagePipeline.shared.clear() }
        .onDisappear { image = nil }
    }
    private func updatePixels(_ size: CGSize) {
        let desired = max(size.width, size.height) * (NSScreen.main?.backingScaleFactor ?? 2)
        requestedPixels = max(256, Int(ceil(desired / 256)) * 256)
    }
}
struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer?
    func makeNSView(context: Context) -> AVPlayerView { let view = AVPlayerView(); view.controlsStyle = .inline; view.videoGravity = .resizeAspect; return view }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}
struct MediaPlayer: View {
    let url: URL
    let audio: Bool
    @AppStorage("lowMemory") private var lowMemory = true
    @AppStorage("videoAutoplay") private var autoplay = true
    @AppStorage("videoSound") private var sound = false
    @AppStorage("videoLoop") private var loop = true
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var duration = ""
    var body: some View {
        VStack {
            if audio { Image(systemName: "waveform.circle.fill").font(.system(size: 90)).foregroundStyle(.tint).padding(); Text(duration).monospacedDigit() }
            if failed { Text(tr("Nie można odtworzyć tego formatu", "This format cannot be played")) }
            NativePlayer(player: player).frame(maxWidth: .infinity, maxHeight: audio ? 100 : .infinity)
        }
        .task(id: url) {
            cleanup(); failed = false
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            let asset = AVURLAsset(url: url)
            do {
                guard try await asset.load(.isPlayable) else { failed = true; return }
                let time = try await asset.load(.duration)
                guard !Task.isCancelled else { return }
                let seconds = CMTimeGetSeconds(time)
                duration = seconds.isFinite ? String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) : ""
                let item = AVPlayerItem(asset: asset)
                if lowMemory { item.preferredForwardBufferDuration = 2; item.preferredMaximumResolution = CGSize(width: 1280, height: 720) }
                let value = AVPlayer(playerItem: item); value.isMuted = audio ? false : !sound; player = value
                if autoplay && !lowMemory { value.play() }
            } catch { if !Task.isCancelled { failed = true } }
        }
        .onChange(of: sound) { _, value in if !audio { player?.isMuted = !value } }
        .onChange(of: lowMemory) { _, value in
            if value { player?.pause() }; player?.currentItem?.preferredForwardBufferDuration = value ? 2 : 0
            player?.currentItem?.preferredMaximumResolution = value ? CGSize(width: 1280, height: 720) : .zero
        }
        .onChange(of: autoplay) { _, value in if value && !lowMemory { player?.play() } else { player?.pause() } }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            if loop, let item = notification.object as? AVPlayerItem, item === player?.currentItem { player?.seek(to: .zero); player?.play() }
        }.onDisappear { cleanup() }
    }
    private func cleanup() { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
}
struct DocumentPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.shouldCloseWithWindow = false; view.autostarts = false; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { if view.previewItem as? URL != url { view.previewItem = url as QLPreviewItem } }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.previewItem = nil; view.close() }
}
struct FilePreview: View {
    let file: FileEntry
    @AppStorage("documentPadded") private var padded = true
    var body: some View {
        Group {
            switch file.kind {
            case .image, .raw: ImagePreview(url: file.url)
            case .video: MediaPlayer(url: file.url, audio: false)
            case .audio: AudioPreview(url: file.url)
            case .document: GeometryReader { geo in DocumentPreview(url: file.url).padding(padded ? min(32, geo.size.width * 0.04) : 0) }
            case .all, .other: ContentUnavailableView(tr("Otwórz w aplikacji", "Open in app"), systemImage: "doc", description: Text(file.name))
            }
        }.id(file.url)
    }
}
struct AudioPreview: View {
    let url: URL
    @State private var showWave = false
    var body: some View {
        VStack {
            Spacer(); MediaPlayer(url: url, audio: true)
            Toggle(tr("Pokaż przebieg fali", "Show waveform"), isOn: $showWave).toggleStyle(.button)
            if showWave { WaveformView(url: url).frame(height: 120).padding() }
            Spacer()
        }.onChange(of: url) { _, _ in showWave = false }
    }
}
struct WaveformView: View {
    let url: URL
    @State private var samples: [Float] = []
    @State private var error = ""
    var body: some View {
        Group {
            if !error.isEmpty { Text(error).font(.caption) }
            else if samples.isEmpty { ProgressView() }
            else { Canvas { context, size in
                var path = Path()
                for (index, value) in samples.enumerated() {
                    let x = size.width * Double(index) / Double(max(1, samples.count - 1)), h = size.height * Double(value) / 2
                    path.move(to: CGPoint(x: x, y: size.height / 2 - h)); path.addLine(to: CGPoint(x: x, y: size.height / 2 + h))
                }
                context.stroke(path, with: .color(.accentColor), lineWidth: 1)
            } }
        }.task(id: url) {
            let flag = CancellationFlag()
            await withTaskCancellationHandler(operation: {
                let result = await Task.detached(priority: .utility) { Result { try readWave(url, flag: flag) } }.value
                guard !Task.isCancelled else { return }
                switch result { case .success(let value): samples = value; case .failure(let failure): error = failure.localizedDescription }
            }, onCancel: { flag.cancel() })
        }
    }
    private func readWave(_ url: URL, flag: CancellationFlag) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { throw CocoaError(.fileReadUnknown) }
        var peaks = [Float](repeating: 0, count: 400)
        let total = max(1, file.length)
        while file.framePosition < file.length {
            try flag.check(); let start = file.framePosition
            try file.read(into: buffer, frameCount: 8192)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for index in 0..<Int(buffer.frameLength) {
                let bucket = min(399, Int((start + Int64(index)) * 400 / total))
                for channel in 0..<Int(buffer.format.channelCount) { peaks[bucket] = max(peaks[bucket], abs(channels[channel][index])) }
            }
        }
        let peak = max(peaks.max() ?? 1, 0.001); return peaks.map { $0 / peak }
    }
}

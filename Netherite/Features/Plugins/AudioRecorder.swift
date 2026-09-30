import SwiftUI
import AVFoundation
import NetheriteCore

@Observable
final class AudioRecorderModel: NSObject, AVAudioRecorderDelegate {
    var recording = false
    var elapsed: TimeInterval = 0
    var level: Float = 0
    var error: String?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored let fileURL = URL.temporaryDirectory.appending(path: "netherite-recording-\(UUID().uuidString).m4a")

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            error = String(localized: "Microphone access is off. Allow it in System Settings › Privacy & Security › Microphone.")
            return
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                                       AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        do {
            let r = try AVAudioRecorder(url: fileURL, settings: settings)
            r.isMeteringEnabled = true
            r.delegate = self
            r.record()
            recorder = r
            recording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let r = self.recorder else { return }
                    r.updateMeters()
                    self.elapsed = r.currentTime
                    self.level = max(0, (r.averagePower(forChannel: 0) + 60) / 60)
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    /// Stops and returns the recorded audio.
    func stop() -> Data? {
        recorder?.stop()
        timer?.invalidate()
        recording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
        defer { try? FileManager.default.removeItem(at: fileURL) }
        return try? Data(contentsOf: fileURL)
    }

    func cancel() { _ = stop() }
}

/// Records audio into the attachments folder and embeds it in the current note.
struct AudioRecorderView: View {
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var rec = AudioRecorderModel()

    var body: some View {
        VStack(spacing: 20) {
            Text(rec.recording ? "Recording…" : "Audio recorder").font(.title2.bold())
            Text(Duration.seconds(rec.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
            Gauge(value: Double(rec.level)) { Text("Input level") }
                .gaugeStyle(.accessoryLinearCapacity)
                .frame(maxWidth: 240)
                .accessibilityValue(Text("\(Int(rec.level * 100)) percent"))
            if let e = rec.error { Text(e).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center) }
            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) { rec.cancel(); dismiss() }
                if rec.recording {
                    Button("Stop and Save", systemImage: "stop.fill", action: finish)
                        .buttonStyle(.borderedProminent).tint(.red)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Record", systemImage: "record.circle") { Task { await rec.start() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(minWidth: 360)
        .task { await rec.start() }
        .onDisappear { if rec.recording { rec.cancel() } }
    }

    private func finish() {
        guard let data = rec.stop() else { dismiss(); return }
        let name = String(localized: "Recording") + " " + Templates.format(.now, "yyyyMMddHHmmss")
        guard let path = window.model.saveAttachment(data, name: name, ext: "m4a") else { dismiss(); return }
        let embed = "![[\((path as NSString).lastPathComponent)]]"
        if let note = window.currentNote {
            if let e = window.editor, !window.pane.reading { e.insert(embed) }
            else { window.model.edit(note, text: window.model.text(of: note) + "\n" + embed + "\n") }
        } else {
            window.open(path: path)
        }
        dismiss()
    }
}

import SwiftUI
import AVFoundation
import NetheriteCore

@Observable
final class AudioRecorderModel: NSObject, AVAudioRecorderDelegate {
    var recording = false
    var elapsed: TimeInterval = 0
    var level: Float = 0
    var error: String?
    var denied = false
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored let fileURL = URL.temporaryDirectory.appending(path: "netherite-recording-\(UUID().uuidString).m4a")

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            denied = true
            #if os(iOS)
            error = String(localized: "Microphone access is off. Allow it in Settings › Netherite › Microphone.")
            #else
            error = String(localized: "Microphone access is off. Allow it in System Settings › Privacy & Security › Microphone.")
            #endif
            return
        }
        error = nil
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

    /// Stops and returns the recorded audio. The temporary file is kept until `discard()`.
    func stop() -> Data? {
        recorder?.stop()
        timer?.invalidate()
        recording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
        return try? Data(contentsOf: fileURL)
    }

    func discard() { try? FileManager.default.removeItem(at: fileURL) }

    func cancel() { _ = stop(); discard() }
}

/// Records audio into the attachments folder and embeds it in the current note.
struct AudioRecorderView: View {
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var rec = AudioRecorderModel()
    /// Recorded audio that couldn't be saved yet; kept so the user can retry.
    @State private var unsaved: Data?
    @State private var confirmDiscard = false

    private var hasWork: Bool { (rec.recording && rec.elapsed > 3) || unsaved != nil }

    private var settingsURL: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #else
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        #endif
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(rec.recording ? "Recording…" : "Audio Recorder").font(.title2.bold())
            Text(Duration.seconds(rec.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
            Gauge(value: Double(rec.level)) { Text("Input level") }
                .gaugeStyle(.accessoryLinearCapacity)
                .frame(maxWidth: 240)
                .accessibilityValue(Text("\(Int(rec.level * 100)) percent"))
            if let e = rec.error {
                // Symbol as well as color, so the error reads as one without color.
                Label { Text(e) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }.font(.callout).multilineTextAlignment(.center)
            }
            if rec.denied, let settingsURL {
                Button("Open Settings") { openURL(settingsURL) }
            }
            HStack(spacing: 16) {
                Button("Cancel", role: .cancel) {
                    if hasWork { confirmDiscard = true } else { rec.cancel(); dismiss() }
                }
                if rec.recording {
                    Button("Stop and Save", systemImage: "stop.fill", action: finish)
                        .buttonStyle(.borderedProminent).tint(.red)
                        .keyboardShortcut(.defaultAction)
                } else if unsaved != nil {
                    Button("Try Again", systemImage: "square.and.arrow.down", action: finish)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else if !rec.denied {
                    Button("Record", systemImage: "record.circle") { Task { await rec.start() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(minWidth: 360)
        .interactiveDismissDisabled(rec.recording || unsaved != nil)
        // VoiceOver focus stays on the button that failed: say why.
        .onChange(of: rec.error) { if let e = rec.error { AccessibilityNotification.Announcement(e).post() } }
        .confirmationDialog("Discard Recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { rec.cancel(); dismiss() }
        }
        .task { await rec.start() }
        .onDisappear { rec.cancel() }
    }

    private func finish() {
        guard let data = unsaved ?? rec.stop() else {
            rec.error = String(localized: "The recording couldn't be read.")
            return
        }
        let name = String(localized: "Recording") + " " + Templates.format(.now, "yyyyMMddHHmmss")
        guard let path = window.model.saveAttachment(data, name: name, ext: "m4a") else {
            unsaved = data
            // Shown here instead of the window alert, which the sheet would hide.
            rec.error = window.model.lastError ?? String(localized: "The recording couldn't be saved.")
            window.model.lastError = nil
            return
        }
        unsaved = nil
        rec.discard()
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

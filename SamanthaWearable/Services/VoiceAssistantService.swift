// Services/VoiceAssistantService.swift
// Foreground "Hey Samantha" listener. Audio stays on device until a command transcript exists.

import Foundation
import Speech
import AVFoundation

@MainActor
struct SpokenReply {
    var reply: String
    var intent: String
    var apiMs: Double
    var needsConfirmation: Bool
    var speak: Bool = true
    var audioPath: String?
    var gpu: Int?
}

final class VoiceAssistantService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Phase: String {
        case idle = "IDLE"
        case wakeListening = "WAKE LISTENING"
        case listening = "LISTENING"
        case thinking = "THINKING"
        case speaking = "SPEAKING"
        case error = "ERROR"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript: String = ""
    @Published private(set) var reply: String = ""
    @Published private(set) var intent: String = ""
    @Published private(set) var audioRoute: String = "—"
    @Published private(set) var routeDetail: String = ""
    @Published private(set) var wakeToTranscriptMs: Double?
    @Published private(set) var apiLatencyMs: Double?
    @Published private(set) var totalLatencyMs: Double?
    @Published private(set) var voiceEngine: String = "—"
    @Published private(set) var ttsGPU: String = "—"
    @Published private(set) var firstAudioMs: Double?
    @Published private(set) var synthesisMs: Double?
    @Published private(set) var needsConfirmation = false
    @Published var heySamanthaEnabled = true
    @Published var proactiveEnabled = true
    @Published var muted = false
    @Published private(set) var lastError: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var playbackNode: AVAudioPlayerNode?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var commandMode = false
    private var wakeStartedAt: Date?
    private var silenceWork: DispatchWorkItem?
    private var latestPartial = ""
    private var eventBaseURL: String = ""
    private var eventTask: URLSessionWebSocketTask?
    private var eventSession: URLSession?
    private var reconnectTask: Task<Void, Never>?
    private var greeted = false
    private var tapInstalled = false
    private var speakGeneration = 0
    private var fallbackText = ""

    var onCommand: ((String) async -> SpokenReply?)?
    var fetchAudio: ((String) async throws -> WearableAudio)?
    var onPhase: ((Phase) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func setForeground(_ active: Bool, glassesConnected: Bool) {
        refreshRoute()
        if active && heySamanthaEnabled && glassesConnected {
            startWakeListening()
        } else {
            stopCapture()
            if phase != .speaking {
                phase = .idle
            }
        }
    }

    func startWakeListening() {
        guard heySamanthaEnabled else {
            stopCapture()
            phase = .idle
            return
        }
        guard phase != .speaking, phase != .thinking, phase != .listening else { return }
        commandMode = false
        beginRecognition()
    }

    func toggleTalkFallback() {
        if phase == .listening || phase == .wakeListening {
            let text = latestPartial
            if commandMode || text.lowercased().contains("hey samantha") {
                finishCommand(from: text)
            } else {
                commandMode = true
                phase = .listening
                wakeStartedAt = Date()
            }
        } else if phase != .speaking && phase != .thinking {
            commandMode = true
            beginRecognition()
            phase = .listening
            wakeStartedAt = Date()
        }
    }

    func confirmPending() {
        Task { await submit(text: "yes") }
    }

    func cancelPending() {
        needsConfirmation = false
        Task { await submit(text: "cancel") }
    }

    func stopSpeaking() {
        speakGeneration += 1
        synthesizer.stopSpeaking(at: .immediate)
        stopPlaybackNode()
        resumeWake()
    }

    func speakConnectedGreeting() {
        guard !greeted else { return }
        greeted = true
        speak("Connected. Samantha is online.")
    }

    func handleEvent(text: String, speakOut: Bool) {
        reply = text
        print("[ProactiveEvent] \(text)")
        if speakOut && proactiveEnabled && !muted && phase != .listening && phase != .thinking {
            speak(text)
        }
    }

    func connectEvents(baseURL: String) {
        eventBaseURL = baseURL
        disconnectEvents()
        guard var parts = URLComponents(string: baseURL) else { return }
        if parts.scheme == "https" { parts.scheme = "wss" } else { parts.scheme = "ws" }
        parts.path = "/api/wearable/events"
        parts.query = nil
        guard let url = parts.url else { return }
        let session = URLSession(configuration: .default)
        eventSession = session
        let task = session.webSocketTask(with: url)
        eventTask = task
        task.resume()
        receiveLoop()
        print("[ProactiveEvent] socket \(url.absoluteString)")
    }

    func disconnectEvents() {
        reconnectTask?.cancel()
        eventTask?.cancel(with: .goingAway, reason: nil)
        eventTask = nil
        eventSession?.invalidateAndCancel()
        eventSession = nil
    }

    private func receiveLoop() {
        eventTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message {
                        self.consumeEvent(text)
                    }
                    self.receiveLoop()
                case .failure(let error):
                    print("[ProactiveEvent] socket closed \(error.localizedDescription)")
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func consumeEvent(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let text = obj["text"] as? String ?? ""
        let speakOut = obj["speak"] as? Bool ?? false
        let type = obj["type"] as? String ?? "event"
        print("[ProactiveEvent] type=\(type)")
        if !text.isEmpty {
            handleEvent(text: text, speakOut: speakOut)
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard let self, self.heySamanthaEnabled, !self.eventBaseURL.isEmpty else { return }
                print("[ProactiveEvent] reconnect")
                self.connectEvents(baseURL: self.eventBaseURL)
            }
        }
    }

    private func beginRecognition() {
        stopCaptureEngineOnly()
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.phase = .error
                    self.lastError = "Speech recognition is not authorized"
                    print("[SpeechRecognition] auth \(status.rawValue)")
                    return
                }
                self.startEngine()
            }
        }
    }

    private func startEngine() {
        refreshRoute()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            phase = .error
            lastError = error.localizedDescription
            print("[AudioRoute] session \(error.localizedDescription)")
            return
        }
        refreshRoute()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest, let recognizer, recognizer.isAvailable else {
            phase = .error
            lastError = "Speech recognizer unavailable"
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .error
            lastError = "Microphone is not ready"
            print("[WakeWord] microphone format not ready")
            return
        }
        removeInputTap()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        tapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            phase = .error
            lastError = error.localizedDescription
            return
        }
        phase = commandMode ? .listening : .wakeListening
        print("[WakeWord] \(phase.rawValue)")
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.consume(transcript: result.bestTranscription.formattedString, isFinal: result.isFinal)
                }
                if let error, self.phase == .wakeListening || self.phase == .listening {
                    let ns = error as NSError
                    let cancelled = ns.code == NSURLErrorCancelled
                        || ns.code == 216
                        || ns.code == 203
                        || error.localizedDescription.lowercased().contains("cancel")
                    if cancelled {
                        print("[SpeechRecognition] ignored \(error.localizedDescription)")
                        return
                    }
                    self.lastError = error.localizedDescription
                    print("[SpeechRecognition] \(error.localizedDescription)")
                    self.stopCaptureEngineOnly()
                    self.phase = .error
                }
            }
        }
    }

    private func consume(transcript text: String, isFinal: Bool) {
        latestPartial = text
        let lower = text.lowercased()
        if !commandMode {
            guard let range = lower.range(of: "hey samantha") else { return }
            print("[WakeWord] detected")
            wakeStartedAt = Date()
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = after.trimmingCharacters(in: CharacterSet(charactersIn: ",.:;"))
            if cleaned.split(separator: " ").count >= 2 || (isFinal && !cleaned.isEmpty) {
                finishCommand(from: cleaned)
                return
            }
            commandMode = true
            phase = .listening
            transcript = ""
            playAck()
            armSilence()
            return
        }
        transcript = text
        armSilence()
        if isFinal {
            finishCommand(from: text)
        }
    }

    private func armSilence() {
        silenceWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.commandMode, self.phase == .listening else { return }
                self.finishCommand(from: self.latestPartial)
            }
        }
        silenceWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: item)
    }

    private func finishCommand(from text: String) {
        silenceWork?.cancel()
        var spoken = text
        if let range = spoken.lowercased().range(of: "hey samantha") {
            spoken = String(spoken[range.upperBound...])
        }
        spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.:")))
        guard !spoken.isEmpty else {
            commandMode = false
            phase = .wakeListening
            return
        }
        if let start = wakeStartedAt {
            wakeToTranscriptMs = Date().timeIntervalSince(start) * 1000
        }
        transcript = spoken
        print("[SpeechRecognition] \(spoken)")
        stopCaptureEngineOnly()
        phase = .thinking
        Task { await submit(text: spoken) }
    }

    private func submit(text: String) async {
        let started = Date()
        phase = .thinking
        guard let onCommand else {
            phase = .error
            lastError = "No command handler"
            return
        }
        guard let result = await onCommand(text) else {
            phase = .error
            lastError = "Samantha server did not answer"
            resumeWake()
            return
        }
        apiLatencyMs = result.apiMs
        totalLatencyMs = Date().timeIntervalSince(started) * 1000
        reply = result.reply
        intent = result.intent
        needsConfirmation = result.needsConfirmation
        print("[WearableVoice] intent=\(result.intent) api_ms=\(Int(result.apiMs)) total_ms=\(Int(totalLatencyMs ?? 0))")
        if muted || !result.speak {
            resumeWake()
            return
        }
        if let path = result.audioPath {
            speakServer(result.reply, path: path, gpu: result.gpu)
        } else {
            voiceEngine = "iOS Fallback"
            speak(result.reply)
        }
    }

    private func speakServer(_ text: String, path: String, gpu: Int?) {
        refreshRoute()
        stopCaptureEngineOnly()
        phase = .speaking
        speakGeneration += 1
        let token = speakGeneration
        let started = Date()
        fallbackText = text
        ttsGPU = gpu.map { "P100 \($0)" } ?? "—"
        print("[TTS] fetch \(path)")
        Task {
            do {
                guard let fetchAudio else { throw URLError(.badURL) }
                let audio = try await fetchAudio(path)
                guard token == speakGeneration else { return }
                firstAudioMs = Date().timeIntervalSince(started) * 1000
                synthesisMs = audio.synthesisMs
                try playWav(audio.data)
                voiceEngine = "F5-TTS"
                print("[TTS] f5 first_audio_ms=\(Int(firstAudioMs ?? 0)) synthesis_ms=\(Int(audio.synthesisMs ?? 0)) rtf=\(audio.rtf ?? -1)")
            } catch {
                guard token == speakGeneration else { return }
                print("[TTS] fallback \(error.localizedDescription)")
                voiceEngine = "iOS Fallback"
                speak(text)
            }
        }
    }

    private func playWav(_ data: Data) throws {
        let pcm = try decodeWav(data)
        guard !pcm.samples.isEmpty else { throw URLError(.cannotDecodeContentData) }
        stopCaptureEngineOnly()
        audioEngine.reset()
        try activateSpokenSession()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: pcm.sampleRate, channels: 1, interleaved: false)
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.samples.count)),
              let channel = buffer.floatChannelData else {
            throw URLError(.cannotDecodeContentData)
        }
        buffer.frameLength = AVAudioFrameCount(pcm.samples.count)
        pcm.samples.withUnsafeBufferPointer { source in
            channel[0].update(from: source.baseAddress!, count: source.count)
        }
        let node = AVAudioPlayerNode()
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        audioEngine.mainMixerNode.outputVolume = 1
        playbackNode = node
        audioEngine.prepare()
        try audioEngine.start()
        let token = speakGeneration
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, token == self.speakGeneration else { return }
                print("[TTS] playback finished")
                self.stopPlaybackNode()
                self.resumeWake()
            }
        }
        node.volume = 1
        node.play()
        refreshRoute()
        print("[TTS] engine route=\(audioRoute) \(routeDetail) frames=\(pcm.samples.count)")
    }

    private func speak(_ text: String) {
        refreshRoute()
        stopCaptureEngineOnly()
        audioEngine.reset()
        try? activateSpokenSession()
        phase = .speaking
        print("[TTS] route=\(audioRoute) \(routeDetail)")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = 0.48
        voiceEngine = "iOS Fallback"
        synthesizer.speak(utterance)
    }

    private func activateSpokenSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)
    }

    private func decodeWav(_ data: Data) throws -> (samples: [Float], sampleRate: Double) {
        guard data.count > 44 else { throw URLError(.cannotDecodeContentData) }
        var offset = 12
        var sampleRate = 24000.0
        var channels = 1
        var bits = 16
        var pcm = Data()
        while offset + 8 <= data.count {
            let chunk = data.subdata(in: offset..<(offset + 4))
            let size = Int(UInt32(littleEndian: data.subdata(in: (offset + 4)..<(offset + 8)).withUnsafeBytes { $0.load(as: UInt32.self) }))
            let start = offset + 8
            let end = min(data.count, start + size)
            if chunk == Data("fmt ".utf8), end - start >= 16 {
                channels = Int(UInt16(littleEndian: data.subdata(in: (start + 2)..<(start + 4)).withUnsafeBytes { $0.load(as: UInt16.self) }))
                sampleRate = Double(UInt32(littleEndian: data.subdata(in: (start + 4)..<(start + 8)).withUnsafeBytes { $0.load(as: UInt32.self) }))
                bits = Int(UInt16(littleEndian: data.subdata(in: (start + 14)..<(start + 16)).withUnsafeBytes { $0.load(as: UInt16.self) }))
            } else if chunk == Data("data".utf8) {
                pcm = data.subdata(in: start..<end)
                break
            }
            offset = start + size + (size % 2)
        }
        guard bits == 16, channels >= 1, !pcm.isEmpty else { throw URLError(.cannotDecodeContentData) }
        var samples: [Float] = []
        samples.reserveCapacity(pcm.count / 2 / channels)
        pcm.withUnsafeBytes { raw in
            let frames = raw.count / 2 / channels
            let shorts = raw.bindMemory(to: Int16.self)
            for frame in 0..<frames {
                let value = Int16(littleEndian: shorts[frame * channels])
                samples.append(Float(value) / 32768.0)
            }
        }
        return (samples, sampleRate)
    }

    private func stopPlaybackNode() {
        playbackNode?.stop()
        if let playbackNode {
            audioEngine.disconnectNodeOutput(playbackNode)
            if audioEngine.attachedNodes.contains(playbackNode) {
                audioEngine.detach(playbackNode)
            }
        }
        playbackNode = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return voices.first { $0.gender == .female && $0.quality == .premium }
            ?? voices.first { $0.gender == .female && $0.quality == .enhanced }
            ?? voices.first { $0.gender == .female }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func playAck() {
        AudioServicesPlaySystemSound(1113)
    }

    private func stopCapture() {
        commandMode = false
        silenceWork?.cancel()
        stopCaptureEngineOnly()
    }

    private func stopCaptureEngineOnly() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        stopPlaybackNode()
        removeInputTap()
    }

    private func removeInputTap() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func resumeWake() {
        commandMode = false
        if heySamanthaEnabled {
            beginRecognition()
        } else {
            phase = .idle
        }
    }

    func refreshRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        guard let port = outputs.first else {
            audioRoute = "Other"
            routeDetail = "none"
            return
        }
        routeDetail = port.portName
        let name = port.portName.lowercased()
        if name.contains("meta") || name.contains("ray-ban") || name.contains("rayban") {
            audioRoute = "Meta Glasses"
        } else if name.contains("airpod") {
            audioRoute = "AirPods"
        } else if port.portType == .bluetoothA2DP || port.portType == .bluetoothHFP || port.portType == .bluetoothLE {
            audioRoute = "Bluetooth"
        } else if port.portType == .builtInSpeaker || port.portType == .builtInReceiver {
            audioRoute = "iPhone Speaker"
        } else {
            audioRoute = "Other"
        }
        print("[AudioRoute] \(audioRoute) \(port.portName)")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            print("[TTS] finished")
            self.resumeWake()
        }
    }

}

import AudioToolbox

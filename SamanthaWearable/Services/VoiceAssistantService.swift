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
    var responseMode: String?
    var mood: String?
    var llmMs: Double?
    var f5FirstChunkMs: Double?
    var generation: String?
    var followUpSeconds: Double?
    var ackDelayMs: Double?
    var llmFirstTokenMs: Double?
    var firstSentenceMs: Double?
}

final class VoiceAssistantService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    enum Phase: String {
        case idle = "IDLE"
        case wakeListening = "WAKE LISTENING"
        case listening = "LISTENING"
        case thinking = "THINKING"
        case speaking = "SPEAKING"
        case followUp = "FOLLOW-UP LISTENING"
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
    @Published private(set) var responseMode: String = "—"
    @Published private(set) var mood: String = "—"
    @Published private(set) var llmMs: Double?
    @Published private(set) var ttsGPU: String = "—"
    @Published private(set) var firstAudioMs: Double?
    @Published private(set) var synthesisMs: Double?
    @Published private(set) var llmFirstTokenMs: Double?
    @Published private(set) var firstSentenceMs: Double?
    @Published private(set) var f5FirstChunkMs: Double?
    @Published private(set) var playbackStartMs: Double?
    @Published private(set) var followUpOpen = false
    @Published private(set) var followUpRemaining: Double = 0
    @Published private(set) var needsConfirmation = false
    @Published var heySamanthaEnabled = true
    @Published var proactiveEnabled = true
    @Published var muted = false
    @Published private(set) var lastError: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var playbackNode: AVAudioPlayerNode?
    private var speakerPlayer: AVAudioPlayer?
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
    private var listenGeneration = 0
    private var restartWork: DispatchWorkItem?
    private var playbackWatchdog: DispatchWorkItem?
    private var awaitingReportChoice = false
    private var fallbackText = ""
    private var chunkQueue: [(generation: String, seq: Int, path: String)] = []
    private var activeGeneration: String?
    private var retiredGenerations: Set<String> = []
    private var playedStream = false
    private var playingChunk = false
    private var streamFinished = false
    private var f5AudioStarted = false
    private var fillerUtterance = false
    private var spokenFillers: [AVSpeechUtterance] = []
    private var fillerIndex = 0
    private var progressWork: DispatchWorkItem?
    private var listenerWarningSpoken = false
    private var followUpWork: DispatchWorkItem?
    private var followUpEnds: Date?
    private var followUpSeconds: Double = 10
    private var ackDelayMs: Double = 1200
    private var speechEndedAt: Date?
    private var bargeIn = false
    private var recognitionStarting = false

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
        guard phase != .speaking, phase != .thinking, phase != .listening, phase != .wakeListening, phase != .followUp else { return }
        commandMode = false
        awaitingReportChoice = false
        beginRecognition()
    }

    func sendTypedCommand(_ text: String) {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        interruptForCommand()
        transcript = spoken
        commandMode = true
        stopCaptureEngineOnly()
        phase = .thinking
        Task { await submit(text: spoken) }
    }

    func startTalking() {
        speakGeneration += 1
        playbackWatchdog?.cancel()
        followUpWork?.cancel()
        followUpOpen = false
        followUpRemaining = 0
        awaitingReportChoice = false
        bargeIn = false
        synthesizer.stopSpeaking(at: .immediate)
        speakerPlayer?.stop()
        speakerPlayer = nil
        stopPlaybackNode()
        commandMode = true
        wakeStartedAt = Date()
        transcript = ""
        latestPartial = ""
        phase = .listening
        beginRecognition()
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
        speakerPlayer?.stop()
        speakerPlayer = nil
        stopPlaybackNode()
        resumeWake()
    }

    func speakConnectedGreeting() {
        guard !greeted else { return }
        greeted = true
        awaitingReportChoice = true
        commandMode = true
        speak("Connected. Do you want a small report?")
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
                    self.noteListenerDown()
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
        if type == "speech_chunk" {
            let generation = obj["generation"] as? String ?? ""
            let seq = obj["seq"] as? Int ?? 0
            let path = obj["audio_url"] as? String ?? ""
            if !generation.isEmpty, !path.isEmpty {
                enqueueChunk(generation: generation, seq: seq, path: path)
            }
            return
        }
        if type == "speech_done" {
            streamFinished = true
            pumpQueue()
            return
        }
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
                self.listenerWarningSpoken = false
                self.connectEvents(baseURL: self.eventBaseURL)
            }
        }
    }

    private func beginRecognition() {
        guard !recognitionStarting else { return }
        recognitionStarting = true
        stopCaptureEngineOnly()
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.recognitionStarting = false
                    self.phase = .error
                    self.lastError = "Speech recognition is not authorized"
                    print("[SpeechRecognition] auth \(status.rawValue)")
                    return
                }
                await self.prepareListeningSession()
            }
        }
    }

    /// Bluetooth route changes block for several seconds. Keep that off the main thread.
    private func prepareListeningSession() async {
        do {
            try await Self.configureAudioSession(playback: false)
        } catch {
            await MainActor.run {
                self.recognitionStarting = false
                self.phase = .wakeListening
                self.lastError = error.localizedDescription
                print("[AudioRoute] session \(error.localizedDescription)")
                self.scheduleListenRestart()
            }
            return
        }
        await MainActor.run {
            self.recognitionStarting = false
            self.startEngine()
        }
    }

    private static func configureAudioSession(playback: Bool) async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .allowBluetoothA2DP])
            if playback {
                let inputs = session.availableInputs ?? []
                if let glasses = inputs.first(where: { Self.isGlassesPort($0.portName) }) {
                    try session.setPreferredInput(glasses)
                    try session.overrideOutputAudioPort(.none)
                } else if session.currentRoute.outputs.contains(where: { Self.isGlassesPort($0.portName) }) {
                    try session.overrideOutputAudioPort(.none)
                } else {
                    try session.setPreferredInput(nil)
                    try session.overrideOutputAudioPort(.speaker)
                }
            } else if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(mic)
            }
            try session.setActive(true, options: playback ? [] : [.notifyOthersOnDeactivation])
        }.value
    }

    private static func isGlassesPort(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("meta") || lowered.contains("ray-ban") || lowered.contains("rayban")
    }

    private func startEngine() {
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
            phase = .wakeListening
            lastError = "Microphone is not ready"
            print("[WakeWord] microphone format not ready")
            scheduleListenRestart()
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
            phase = .wakeListening
            lastError = error.localizedDescription
            scheduleListenRestart()
            return
        }
        if !bargeIn {
            phase = commandMode ? .listening : (phase == .followUp ? .followUp : .wakeListening)
        }
        listenGeneration += 1
        let generation = listenGeneration
        print("[WakeWord] \(phase.rawValue)")
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self, generation == self.listenGeneration else { return }
                if let result {
                    self.consume(transcript: result.bestTranscription.formattedString, isFinal: result.isFinal)
                    if result.isFinal, !self.bargeIn, self.phase == .wakeListening || self.phase == .listening || self.phase == .followUp {
                        self.scheduleListenRestart()
                    }
                }
                if let error, self.bargeIn {
                    self.bargeIn = false
                    return
                }
                if let error, self.phase == .wakeListening || self.phase == .listening || self.phase == .followUp || self.phase == .error {
                    let ns = error as NSError
                    let cancelled = ns.code == NSURLErrorCancelled
                        || ns.code == 216
                        || ns.code == 203
                        || error.localizedDescription.lowercased().contains("cancel")
                    if cancelled {
                        print("[SpeechRecognition] ignored \(error.localizedDescription)")
                    } else {
                        self.lastError = error.localizedDescription
                        print("[SpeechRecognition] \(error.localizedDescription)")
                    }
                    self.scheduleListenRestart()
                }
            }
        }
    }

    private func consume(transcript text: String, isFinal: Bool) {
        if bargeIn {
            guard text.lowercased().contains("hey samantha") else { return }
            interruptForCommand()
            finishCommand(from: text)
            return
        }
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
        if awaitingReportChoice {
            let choice = spoken.lowercased()
            if choice.isEmpty { return }
            awaitingReportChoice = false
            if Self.isYes(choice) {
                spoken = "small report"
            } else if Self.isNo(choice) {
                commandMode = false
                speak("Okay.")
                return
            }
        }
        guard !spoken.isEmpty else {
            commandMode = false
            phase = .wakeListening
            scheduleListenRestart()
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
        speechEndedAt = started
        phase = .thinking
        if let activeGeneration {
            retiredGenerations.insert(activeGeneration)
        }
        activeGeneration = nil
        playedStream = false
        playingChunk = false
        streamFinished = false
        f5AudioStarted = false
        playbackStartMs = nil
        chunkQueue.removeAll()
        bargeIn = false
        if !muted {
            armLocalAck()
        }
        guard let onCommand else {
            cancelLocalAck()
            phase = .error
            lastError = "No command handler"
            return
        }
        guard let result = await onCommand(text) else {
            cancelLocalAck()
            phase = .error
            lastError = "Samantha server did not answer"
            openFollowUp()
            return
        }
        apiLatencyMs = result.apiMs
        totalLatencyMs = Date().timeIntervalSince(started) * 1000
        reply = result.reply
        intent = result.intent
        needsConfirmation = result.needsConfirmation
        responseMode = result.responseMode ?? "—"
        mood = result.mood ?? "—"
        llmMs = result.llmMs
        llmFirstTokenMs = result.llmFirstTokenMs
        firstSentenceMs = result.firstSentenceMs
        f5FirstChunkMs = result.f5FirstChunkMs
        if let window = result.followUpSeconds { followUpSeconds = window }
        if let delay = result.ackDelayMs { ackDelayMs = delay }
        if let generation = result.generation { activeGeneration = generation }
        streamFinished = true
        print("[WearableVoice] intent=\(result.intent) api_ms=\(Int(result.apiMs)) total_ms=\(Int(totalLatencyMs ?? 0))")
        if muted || !result.speak {
            cancelLocalAck()
            openFollowUp()
            return
        }
        if playedStream || playingChunk || !chunkQueue.isEmpty {
            cancelLocalAck()
            pumpQueue()
            return
        }
        if let path = result.audioPath {
            speakServer(result.reply, path: path, gpu: result.gpu)
        } else {
            voiceEngine = "iOS Fallback"
            speak(result.reply)
        }
    }

    private func enqueueChunk(generation: String, seq: Int, path: String) {
        if retiredGenerations.contains(generation) { return }
        if let active = activeGeneration, active != generation { return }
        activeGeneration = generation
        f5AudioStarted = true
        cancelLocalAck()
        chunkQueue.append((generation, seq, path))
        chunkQueue.sort { $0.seq < $1.seq }
        pumpQueue()
    }

    private func pumpQueue() {
        guard !playingChunk else { return }
        guard let next = chunkQueue.first else {
            if streamFinished, phase == .speaking || phase == .thinking {
                openFollowUp()
            }
            return
        }
        guard next.generation == activeGeneration else {
            chunkQueue.removeFirst()
            pumpQueue()
            return
        }
        chunkQueue.removeFirst()
        playingChunk = true
        playedStream = true
        phase = .speaking
        if playbackStartMs == nil, let speechEndedAt {
            playbackStartMs = Date().timeIntervalSince(speechEndedAt) * 1000
        }
        Task {
            do {
                guard let fetchAudio else { return }
                let audio = try await fetchAudio(next.path)
                guard next.generation == activeGeneration else {
                    playingChunk = false
                    return
                }
                if firstAudioMs == nil {
                    firstAudioMs = audio.downloadMs
                }
                synthesisMs = audio.synthesisMs
                try await playWav(audio.data)
                voiceEngine = "F5-TTS"
            } catch {
                playingChunk = false
                guard next.generation == activeGeneration else { return }
                print("[TTS] chunk failed \(error.localizedDescription)")
                pumpQueue()
            }
        }
    }

    private func armLocalAck() {
        cancelLocalAck()
        let openers = [
            "Oh, I got you.",
            "Got it.",
            "On it.",
            "Okay.",
        ]
        let later = [
            "Working on that now.",
            "Please wait. I'm still checking.",
            "Give me a second.",
            "Still on it.",
        ]
        speakFiller(openers[fillerIndex % openers.count])
        let follow = later[fillerIndex % later.count]
        fillerIndex += 1
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !self.f5AudioStarted, self.phase == .thinking else { return }
                self.speakFiller(follow)
            }
        }
        progressWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
    }

    private func cancelLocalAck() {
        progressWork?.cancel()
        progressWork = nil
        if fillerUtterance {
            fillerUtterance = false
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func speakFiller(_ text: String) {
        if fillerUtterance, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        fillerUtterance = true
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = 0.5
        spokenFillers.append(utterance)
        synthesizer.speak(utterance)
    }

    private func openFollowUp() {
        cancelLocalAck()
        followUpWork?.cancel()
        playingChunk = false
        bargeIn = false
        commandMode = true
        followUpOpen = true
        followUpEnds = Date().addingTimeInterval(followUpSeconds)
        followUpRemaining = followUpSeconds
        phase = .followUp
        beginRecognition()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .followUp else { return }
                self.followUpOpen = false
                self.followUpRemaining = 0
                self.commandMode = false
                self.resumeWake()
            }
        }
        followUpWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + followUpSeconds, execute: item)
        tickFollowUp()
    }

    private func tickFollowUp() {
        guard followUpOpen, let followUpEnds else { return }
        followUpRemaining = max(0, followUpEnds.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.followUpOpen else { return }
            self.tickFollowUp()
        }
    }

    private func noteListenerDown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.listenerWarningSpoken, self.eventTask == nil else { return }
            self.listenerWarningSpoken = true
            self.reply = "The wearable listener is offline."
            if !self.muted, self.phase != .speaking, self.phase != .thinking {
                self.speak(self.reply)
            }
        }
    }

    private func interruptForCommand() {
        speakGeneration += 1
        if let activeGeneration {
            retiredGenerations.insert(activeGeneration)
        }
        activeGeneration = nil
        chunkQueue.removeAll()
        playingChunk = false
        playedStream = false
        bargeIn = false
        synthesizer.stopSpeaking(at: .immediate)
        speakerPlayer?.stop()
        speakerPlayer = nil
        playbackWatchdog?.cancel()
        phase = .listening
        commandMode = true
        followUpOpen = false
        followUpWork?.cancel()
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
                try await playWav(audio.data)
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

    private func playWav(_ data: Data) async throws {
        stopCaptureEngineOnly()
        audioEngine.reset()
        try await Self.configureAudioSession(playback: true)
        refreshRoute()
        cancelLocalAck()
        speakerPlayer = try AVAudioPlayer(data: data)
        speakerPlayer?.delegate = self
        speakerPlayer?.volume = 1
        guard let player = speakerPlayer, player.play() else {
            throw URLError(.cannotDecodeContentData)
        }
        armPlaybackWatchdog(seconds: max(player.duration, 0.5) + 1.5)
        print("[TTS] player route=\(audioRoute) \(routeDetail)")
    }

    private func speak(_ text: String) {
        stopCaptureEngineOnly()
        audioEngine.reset()
        phase = .speaking
        let token = speakGeneration
        Task { @MainActor in
            try? await Self.configureAudioSession(playback: true)
            guard token == self.speakGeneration, self.phase == .speaking else { return }
            self.refreshRoute()
            print("[TTS] route=\(self.audioRoute) \(self.routeDetail)")
            self.cancelLocalAck()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = self.preferredVoice()
            utterance.rate = 0.48
            self.voiceEngine = "iOS Fallback"
            let seconds = Double(text.split(separator: " ").count) * 0.45 + 2
            self.armPlaybackWatchdog(seconds: seconds)
            self.synthesizer.speak(utterance)
        }
    }

    private func armPlaybackWatchdog(seconds: Double) {
        playbackWatchdog?.cancel()
        let token = speakGeneration
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, token == self.speakGeneration, self.phase == .speaking else { return }
                print("[TTS] watchdog resume")
                self.synthesizer.stopSpeaking(at: .immediate)
                self.speakerPlayer?.stop()
                self.speakerPlayer = nil
                self.continueAfterSpeech()
            }
        }
        playbackWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func scheduleListenRestart() {
        guard phase != .speaking, phase != .thinking else { return }
        restartWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.phase != .speaking, self.phase != .thinking else { return }
                print("[WakeWord] restart")
                self.beginRecognition()
            }
        }
        restartWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private func continueAfterSpeech() {
        playbackWatchdog?.cancel()
        guard phase == .speaking else { return }
        if playedStream {
            playingChunk = false
            bargeIn = false
            pumpQueue()
            return
        }
        if awaitingReportChoice {
            commandMode = true
            phase = .listening
            beginRecognition()
            followUpWork?.cancel()
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, self.awaitingReportChoice, self.phase == .listening else { return }
                    self.awaitingReportChoice = false
                    self.commandMode = false
                    self.resumeWake()
                }
            }
            followUpWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + followUpSeconds, execute: item)
            return
        }
        openFollowUp()
    }

    private static func isYes(_ text: String) -> Bool {
        let words = Set(text.split(separator: " ").map(String.init))
        return !words.isDisjoint(with: ["yes", "yeah", "yep", "sure", "please", "ok", "okay", "report"])
    }

    private static func isNo(_ text: String) -> Bool {
        let words = Set(text.split(separator: " ").map(String.init))
        return !words.isDisjoint(with: ["no", "nope", "nah", "cancel"]) || text.contains("not now")
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
            if self.spokenFillers.contains(where: { $0 === utterance }) {
                self.spokenFillers.removeAll { $0 === utterance }
                if self.spokenFillers.isEmpty {
                    self.fillerUtterance = false
                }
                return
            }
            print("[TTS] finished")
            self.continueAfterSpeech()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.speakerPlayer = nil
            if flag {
                print("[TTS] playback finished")
                self.continueAfterSpeech()
            } else {
                let text = self.fallbackText
                if text.isEmpty {
                    self.continueAfterSpeech()
                } else {
                    self.fallbackText = ""
                    self.speak(text)
                }
            }
        }
    }
}

import AudioToolbox

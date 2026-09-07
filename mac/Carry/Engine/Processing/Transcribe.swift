import AVFoundation
import Foundation
import Speech

/// Voice memo → text, on this Mac, with the system speech models.
/// macOS 26: `SpeechAnalyzer` + `SpeechTranscriber` (on-device, long-form). macOS 14/15: `SFSpeechRecognizer`
/// with on-device recognition over ≤ 60 s chunks. The audio is copied into `~/.carry/tmp/` first: the source
/// folder may be readable only by this process, and a `.qta` is a QuickTime container AVFoundation reads as `.m4a`.
enum Transcribe {
    /// What produced the transcript, for `meta.model`.
    static var engineName: String {
        if #available(macOS 26.0, *) { return "SpeechAnalyzer" }
        return "SFSpeechRecognizer"
    }

    /// Returns (text, error). Blocks the calling (background) thread; never call on the main thread.
    static func audio(path: String) -> (String?, String?) {
        let scratchDir = CarryPaths.tmp
        try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        var ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ext.isEmpty || ext == "qta" { ext = "m4a" }
        let scratch = scratchDir.appendingPathComponent("memo-\(UUID().uuidString.prefix(8)).\(ext)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: scratch)
        } catch {
            return (nil, "cannot read audio: \(error.localizedDescription)")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: (String?, String?) = (nil, nil)
        Task.detached(priority: .userInitiated) {
            do {
                let text = try await transcribe(url: scratch)
                let trimmed = Py.strip(text)
                outcome = (trimmed.isEmpty ? nil : trimmed, nil)
            } catch {
                let message = Py.split(String(describing: error)).joined(separator: " ")
                outcome = (nil, "\(type(of: error)): \(String(message.suffix(300)))")
            }
            semaphore.signal()
        }
        semaphore.wait()
        return outcome
    }

    /// Duration in seconds via AVFoundation, for recordings whose database row says 0.
    static func seconds(path: String) -> Double? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let semaphore = DispatchSemaphore(value: 0)
        var result: Double?
        Task.detached {
            if let d = try? await asset.load(.duration) { result = CMTimeGetSeconds(d) }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result, result.isFinite, result > 0 else { return nil }
        return result
    }

    private static func transcribe(url: URL) async throws -> String {
        if #available(macOS 26.0, *) {
            return try await transcribeWithAnalyzer(url: url)
        }
        return try await transcribeWithRecognizer(url: url)
    }

    // MARK: - macOS 26: SpeechAnalyzer

    struct TranscribeError: Error, CustomStringConvertible {
        let description: String
    }

    /// The user's preferred languages the transcriber supports, in order; en-US when none is.
    @available(macOS 26.0, *)
    static func candidateLocales() async -> [Locale] {
        var out: [Locale] = []
        for id in Locale.preferredLanguages {
            if let l = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)),
               !out.contains(where: { $0.identifier == l.identifier }) {
                out.append(l)
            }
        }
        if out.isEmpty, let en = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) { out.append(en) }
        return out
    }

    /// A transcriber speaks one language; Whisper guessed it. With several preferred languages, transcribe the
    /// first 45 s in each and keep the one the model is most confident about (weighted by how much it heard).
    @available(macOS 26.0, *)
    static func pickLocale(for url: URL) async throws -> Locale {
        let candidates = await candidateLocales()
        guard candidates.count > 1 else { return candidates.first ?? Locale(identifier: "en-US") }
        let head = try slice(url: url, seconds: 45)
        defer { try? FileManager.default.removeItem(at: head) }
        var best: (Locale, Double)? = nil
        var notes: [String] = []
        for locale in candidates {
            let (text, confidence) = try await run(url: head, locale: locale, withConfidence: true)
            let heard = Double(Py.len(text))
            let score = heard > 0 ? confidence * log(1 + heard) : 0
            notes.append("\(locale.identifier) \(Py.fixed(confidence, 2))×\(Int(heard))")
            if best == nil || score > best!.1 { best = (locale, score) }
        }
        AppLog.write("transcribe: language pick " + notes.joined(separator: ", ") + " → \(best?.0.identifier ?? "?")")
        return best?.0 ?? candidates[0]
    }

    @available(macOS 26.0, *)
    static func transcribeWithAnalyzer(url: URL) async throws -> String {
        guard SpeechTranscriber.isAvailable else { throw TranscribeError(description: "SpeechTranscriber is not available on this Mac") }
        let locale = try await pickLocale(for: url)
        return try await run(url: url, locale: locale, withConfidence: false).0
    }

    /// One pass over a file with one locale. Returns the text and, when asked, the character-weighted mean confidence.
    @available(macOS 26.0, *)
    static func run(url: URL, locale: Locale, withConfidence: Bool) async throws -> (String, Double) {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: withConfidence ? [.transcriptionConfidence] : [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let collector = Task<(String, Double), Error> {
            var pieces: [String] = []
            var weighted = 0.0, weight = 0.0
            for try await result in transcriber.results {
                let text = result.text
                pieces.append(String(text.characters))
                if withConfidence {
                    for r in text.runs {
                        let n = Double(text[r.range].characters.count)
                        if let c = r.transcriptionConfidence, n > 0 { weighted += c * n; weight += n }
                    }
                }
            }
            return (pieces.joined(), weight > 0 ? weighted / weight : 0)
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: file) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw error
        }
        return try await collector.value
    }

    /// The first `seconds` of a file as PCM in a .caf next to it.
    static func slice(url: URL, seconds: Double) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let count = min(AVAudioFrameCount(seconds * format.sampleRate), AVAudioFrameCount(input.length))
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
            throw TranscribeError(description: "empty audio")
        }
        try input.read(into: buffer, frameCount: count)
        let out = url.deletingPathExtension().appendingPathExtension("head.caf")
        let writer = try AVAudioFile(forWriting: out, settings: format.settings)
        try writer.write(from: buffer)
        return out
    }

    // MARK: - macOS 14/15: SFSpeechRecognizer over ≤ 60 s chunks

    static func transcribeWithRecognizer(url: URL) async throws -> String {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            let current = SFSpeechRecognizer.authorizationStatus()
            if current == .notDetermined { SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } } else { c.resume(returning: current) }
        }
        guard status == .authorized else { throw TranscribeError(description: "speech recognition not authorized (\(status.rawValue))") }
        let preferred = Locale.preferredLanguages.map { Locale(identifier: $0) }
        let supported = SFSpeechRecognizer.supportedLocales()
        let locale = preferred.first { l in supported.contains { $0.identifier.replacingOccurrences(of: "_", with: "-") == l.identifier } } ?? Locale(identifier: "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscribeError(description: "no speech recognizer for \(locale.identifier)")
        }
        let chunks = try splitIntoChunks(url: url, maxSeconds: 60)
        defer { for c in chunks { try? FileManager.default.removeItem(at: c) } }
        var pieces: [String] = []
        for chunk in chunks {
            let request = SFSpeechURLRecognitionRequest(url: chunk)
            request.shouldReportPartialResults = false
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            let text: String = try await withCheckedThrowingContinuation { c in
                var finished = false
                recognizer.recognitionTask(with: request) { result, error in
                    guard !finished else { return }
                    if let error { finished = true; c.resume(throwing: error); return }
                    if let result, result.isFinal { finished = true; c.resume(returning: result.bestTranscription.formattedString) }
                }
            }
            if !text.isEmpty { pieces.append(text) }
        }
        return pieces.joined(separator: " ")
    }

    /// Writes ≤ `maxSeconds` PCM slices of the file next to it, as .caf.
    static func splitIntoChunks(url: URL, maxSeconds: Double) throws -> [URL] {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let framesPerChunk = AVAudioFrameCount(maxSeconds * format.sampleRate)
        var out: [URL] = []
        var index = 0
        while input.framePosition < input.length {
            let remaining = AVAudioFrameCount(input.length - input.framePosition)
            let count = min(framesPerChunk, remaining)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
            try input.read(into: buffer, frameCount: count)
            let chunkURL = url.deletingPathExtension().appendingPathExtension("part\(index).caf")
            let writer = try AVAudioFile(forWriting: chunkURL, settings: format.settings)
            try writer.write(from: buffer)
            out.append(chunkURL)
            index += 1
        }
        return out
    }
}

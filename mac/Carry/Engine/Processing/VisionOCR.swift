import Foundation
import Vision

/// Text inside a picture, the way pro.py's `ocr_image` does it through ocrmac: `VNRecognizeTextRequest`,
/// accurate, languages zh-Hans / en-US / ja-JP, keep observations with confidence ≥ 0.3, one line each.
enum VisionOCR {
    static let languages = ["zh-Hans", "en-US", "ja-JP"]

    static func recognize(path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        var lines: [String] = []
        for observation in request.results ?? [] {
            guard observation.confidence >= 0.3, let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            if !text.isEmpty { lines.append(text) }
        }
        let joined = Py.strip(lines.joined(separator: "\n"))
        return joined.isEmpty ? nil : joined
    }
}

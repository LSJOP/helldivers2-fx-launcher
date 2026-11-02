import Foundation
import AppKit
import Vision

@main struct VisualChecks {
    static func main() {
        do { try run() } catch { print("Visual checks failed: \(error.localizedDescription)"); exit(1) }
    }
    static func run() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("gui-smoke.json"))) as! [String: Any]
        guard manifest["programmatic_result"] as? String == "PASS", manifest["visual_capture"] as? String == "PASS" else { throw ErrorState("GUI_SMOKE_FAILED") }
        var records: [[String: Any]] = []
        var failed = false
        for capture in manifest["captures"] as! [[String: Any]] {
            let name = capture["file"] as! String
            let url = directory.appendingPathComponent(name)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = capture["language"] as? String == "zh" ? ["zh-Hans", "en-US"] : ["en-US"]
            try VNImageRequestHandler(url: url).perform([request])
            let strings = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = strings.joined(separator: "\n")
            let title = capture["title"] as! String
            // Vision can recognize the Chinese 查 glyph as its Japanese variant 査.
            // Keep the raw OCR in evidence; normalize only this known glyph for matching.
            let normalized = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "査", with: "查").lowercased()
            let titleFound = normalized.contains(title.replacingOccurrences(of: " ", with: "").lowercased())
            guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)), let color = bitmap.colorAt(x: bitmap.pixelsWide - 50, y: bitmap.pixelsHigh - 60)?.usingColorSpace(.deviceRGB) else { throw ErrorState("IMAGE_UNAVAILABLE") }
            let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            let themeOK = capture["appearance"] as? String == "light" ? brightness > 0.6 : brightness < 0.4
            let dashboardControlsFound: Bool
            if capture["page"] as? String == "dashboard" {
                let zh = capture["language"] as? String == "zh"
                let required = zh ? ["检查环境", "启动helldivers2", "尚未开放"] : ["checkenvironment", "launchhelldivers2", "notavailableyet"]
                dashboardControlsFound = required.allSatisfy { normalized.contains($0) }
            } else { dashboardControlsFound = true }
            let passed = titleFound && themeOK && dashboardControlsFound
            failed = failed || !passed
            records.append(["file": name, "title_found": titleFound, "dashboard_controls_found": dashboardControlsFound, "theme_background_brightness": brightness,
                            "theme_matches": themeOK, "result": passed ? "PASS" : "FAIL", "recognized_text": text])
        }
        let result: [String: Any] = ["result": failed ? "FAIL" : "PASS", "checks": records,
                                     "method": "Apple Vision OCR page labels and native image pixel theme check"]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("visual-checks.json"))
        print("\(records.count) screenshot checks: \(failed ? "FAIL" : "PASS")")
        if failed { throw ErrorState("VISUAL_CHECK_FAILED") }
    }
}

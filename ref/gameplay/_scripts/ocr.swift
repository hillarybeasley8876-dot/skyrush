// OCR images with Apple Vision. Usage: swift ocr.swift img1.png [img2.png ...]
import Foundation
import Vision
import AppKit

for path in CommandLine.arguments.dropFirst() {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("### \(path): cannot load"); continue
    }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["en-US", "zh-Hans"]
    req.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try handler.perform([req]) } catch { print("### \(path): \(error)"); continue }
    let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    print("### \((path as NSString).lastPathComponent)")
    print(lines.joined(separator: "\n"))
}

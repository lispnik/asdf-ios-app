// LispSwift.swift -- the Swift side of examples/swift, for iOS.
//
// Some of Apple's frameworks have no Objective-C surface at all: CryptoKit,
// Swift Charts, SwiftUI, and FoundationModels, the on-device language model
// of iOS 26.  A Lisp that speaks Objective-C reaches them the only way
// anything else does, through Swift.  This file is that Swift: each class is
// @objc, so the runtime sees it once the framework is loaded, and each method
// takes and returns what Objective-C can carry -- strings, arrays, view
// controllers, blocks -- so that the Lisp side is ordinary objc:invoke calls.
//
// Built by build.sh into a framework per platform, which the app embeds; the
// calls the demonstration makes are all in swift.lisp.

import Foundation
import UIKit
import SwiftUI
import Charts
import CryptoKit
#if canImport(FoundationModels)
import FoundationModels
#endif

private func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

// MARK: - CryptoKit

@objc(LispCrypto) public final class LispCrypto: NSObject {
    /// SHA-256 of the UTF-8 of `string`, as hex.
    @objc public static func sha256(_ string: String) -> String {
        hex(SHA256.hash(data: Data(string.utf8)))
    }

    /// HMAC-SHA256 of `string` under `key`, both UTF-8, as hex.
    @objc public static func hmac(_ string: String, key: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(string.utf8),
                                                    using: SymmetricKey(data: Data(key.utf8)))
        return hex(code)
    }

    /// A fresh 256-bit key, base64.
    @objc public static func randomKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// `string` sealed with ChaCha20-Poly1305 under the base64 `key`: nonce,
    /// ciphertext and tag together, base64.  nil if the key is malformed.
    @objc public static func seal(_ string: String, key: String) -> String? {
        guard let keyData = Data(base64Encoded: key),
              let box = try? ChaChaPoly.seal(Data(string.utf8), using: SymmetricKey(data: keyData))
        else { return nil }
        return box.combined.base64EncodedString()
    }

    /// The string `seal` sealed, or nil if the key is wrong or the box was
    /// tampered with -- Poly1305 refuses, which is the point of the tag.
    @objc public static func open(_ sealed: String, key: String) -> String? {
        guard let keyData = Data(base64Encoded: key),
              let combined = Data(base64Encoded: sealed),
              let box = try? ChaChaPoly.SealedBox(combined: combined),
              let plain = try? ChaChaPoly.open(box, using: SymmetricKey(data: keyData))
        else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }
}

// MARK: - Swift Charts, in SwiftUI

private struct BarChart: View {
    let title: String
    let labels: [String]
    let values: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Chart(Array(zip(labels, values)), id: \.0) { item in
                BarMark(x: .value("Label", item.0), y: .value("Value", item.1))
                    .foregroundStyle(by: .value("Label", item.0))
                    .annotation(position: .top) {
                        Text(String(format: "%.0f", item.1)).font(.caption)
                    }
            }
            .chartLegend(.hidden)
        }
        .padding(16)
    }
}

@objc(LispCharts) public final class LispCharts: NSObject {
    /// A view controller showing a bar chart of `values` under `labels`, for
    /// UIKit to place as a child.  Main thread only, as every view is.
    @objc(barChartControllerWithTitle:labels:values:) @MainActor
    public static func barChartController(title: String, labels: [String], values: [NSNumber]) -> UIViewController {
        let controller = UIHostingController(rootView: BarChart(title: title, labels: labels,
                                                                values: values.map { $0.doubleValue }))
        controller.view.backgroundColor = .clear
        return controller
    }

    /// The same chart rendered to a PNG at `path`, `width` by `height`
    /// points at 2x -- SwiftUI's own renderer, so no window is needed.
    @objc(barChartWithTitle:labels:values:width:height:pngTo:) @MainActor
    public static func barChart(title: String, labels: [String], values: [NSNumber],
                                width: Double, height: Double, pngTo path: String) -> Bool {
        let chart = BarChart(title: title, labels: labels, values: values.map { $0.doubleValue })
            .frame(width: width, height: height)
            .background(Color(uiColor: .systemBackground))
        let renderer = ImageRenderer(content: chart)
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData() else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

// MARK: - FoundationModels

@objc(LispLanguageModel) public final class LispLanguageModel: NSObject {
    /// "available", or "unavailable: <why>": Apple Intelligence off, the
    /// model not downloaded, the device, the simulator or the OS too old.
    @objc public static var availability: String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "available"
            case .unavailable(let reason): return "unavailable: \(reason)"
            }
        }
        #endif
        return "unavailable: FoundationModels needs iOS 26"
    }

    /// Ask the on-device model.  `reply` gets the response, or an error
    /// message, on a thread of the model's choosing.
    @objc(respondTo:instructions:reply:)
    public static func respond(to prompt: String, instructions: String?,
                               reply: @escaping @Sendable (String?, String?) -> Void) {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            Task {
                do {
                    let session = instructions.map { LanguageModelSession(instructions: $0) }
                        ?? LanguageModelSession()
                    let response = try await session.respond(to: prompt)
                    reply(response.content, nil)
                } catch {
                    reply(nil, "\(error)")
                }
            }
            return
        }
        #endif
        reply(nil, "FoundationModels needs iOS 26")
    }
}

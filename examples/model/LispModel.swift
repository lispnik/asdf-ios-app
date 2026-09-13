// LispModel.swift -- the Swift side of examples/model.
//
// FoundationModels is the on-device language model of iOS 26, and it is
// Swift only: its session, its tools and its guided generation are Swift
// protocols and macros with no Objective-C behind them.  This file gives a
// Lisp that speaks Objective-C two things through @objc: a way to register
// a tool whose implementation is a Lisp closure, and a way to ask the model
// a question with those tools in hand.
//
// The tool is the point.  The model cannot do arithmetic; Lisp can, exactly
// and without limit.  So the model is told to call Lisp for any calculation,
// and what it calls is a block made from a Lisp closure -- the model's own
// thread arrives in Lisp, gets a string back, and carries on.

import Foundation
import UIKit
import FoundationModels

/// A tool whose implementation lives in Lisp.
struct LispTool: Tool {
    let name: String
    let description: String
    let handler: (String) -> String
    let log: LogBox

    @Generable
    struct Arguments {
        @Guide(description: "The tool's one input, as text")
        var input: String
    }

    func call(arguments: Arguments) async throws -> String {
        // A small model can loop, calling the same tool on its own answer
        // until the context window overflows -- measured.  Past a handful
        // of calls the tool refuses, which fails this attempt and lets a
        // fresh session try again.
        guard log.count < 8 else { throw TooManyToolCalls() }
        let output = handler(arguments.input)
        log.append("\(name)(\(arguments.input)) → \(output)")
        return output
    }
}

struct TooManyToolCalls: Error, CustomStringConvertible {
    var description: String { "the model called tools eight times for one question" }
}

/// The tool calls one question made, in order, safe to append from the
/// model's thread and read afterwards.
final class LogBox: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()
    func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    var count: Int { lock.lock(); defer { lock.unlock() }; return lines.count }
}

private struct ToolSpec {
    let name: String
    let description: String
    let handler: (String) -> String
}

@objc(LispModel) public final class LispModel: NSObject {
    private static var specs: [ToolSpec] = []

    /// "available", or "unavailable: <why>".
    @objc public static var availability: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "available"
        case .unavailable(let reason): return "unavailable: \(reason)"
        }
    }

    /// Register a tool.  `handler` is called with the model's input and
    /// returns what the model is told; a Lisp block, in this example.
    @objc(addToolNamed:description:handler:)
    public static func addTool(named name: String, description: String,
                               handler: @escaping (String) -> String) {
        specs.append(ToolSpec(name: name, description: description, handler: handler))
    }

    /// Ask the model, with every registered tool available to it.  `reply`
    /// is called on the main thread with the answer or an error, and the
    /// tool calls the model made, each as "name(input) → output".
    @objc(askWithPrompt:instructions:reply:)
    public static func ask(prompt: String, instructions: String?,
                           reply: @escaping (String?, String?, [String]) -> Void) {
        let log = LogBox()
        let tools = specs.map { LispTool(name: $0.name, description: $0.description,
                                         handler: $0.handler, log: log) }
        Task {
            // Generation fails now and then with a bare tokengeneration
            // error -- measured, a run that had just answered the same
            // question -- so a fresh session gets two more tries before
            // the failure is reported.
            var failure = ""
            for attempt in 1...3 {
                do {
                    let session = LanguageModelSession(tools: tools, instructions: instructions ?? "")
                    let text = try await session.respond(to: prompt).content
                    let calls = log.all
                    await MainActor.run { reply(text, nil, calls) }
                    return
                } catch {
                    failure = "\(error)"
                    // The console, not the transcript: a retry that works
                    // is not the user's business.
                    print("LispModel: attempt \(attempt) failed: \(failure.prefix(120))")
                }
            }
            let message = failure
            let calls = log.all
            await MainActor.run { reply(nil, message, calls) }
        }
    }
}

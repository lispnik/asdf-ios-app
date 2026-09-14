// LispSettings.swift -- a SwiftUI settings sheet whose values live in Lisp.
//
// Every other Swift example here sends values one way: Lisp builds the
// interface and Swift reports results back.  This one goes the other way.
// The sheet is SwiftUI, a Form of sliders, toggles and pickers; the values
// it edits are Lisp variables.  Each control's current value comes from
// Lisp when the sheet is made, and every change goes back through one
// block, made from a Lisp lambda, which redraws whatever depends on it.
//
// A setting is described by one string, so that the Lisp side needs no
// dictionaries: "slider:name:min:max:value", "toggle:name:on|off",
// "picker:name:value:option|option|...".

import Foundation
import UIKit
import SwiftUI

private enum Setting: Identifiable {
    case slider(name: String, min: Double, max: Double, value: Double)
    case toggle(name: String, on: Bool)
    case picker(name: String, value: String, options: [String])

    var id: String { name }
    var name: String {
        switch self {
        case .slider(let n, _, _, _), .toggle(let n, _), .picker(let n, _, _): return n
        }
    }

    init?(_ spec: String) {
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        switch parts[0] {
        case "slider" where parts.count == 5:
            guard let lo = Double(parts[2]), let hi = Double(parts[3]), let v = Double(parts[4]) else { return nil }
            self = .slider(name: parts[1], min: lo, max: hi, value: v)
        case "toggle":
            self = .toggle(name: parts[1], on: parts[2] == "on")
        case "picker" where parts.count == 4:
            self = .picker(name: parts[1], value: parts[2], options: parts[3].split(separator: "|").map(String.init))
        default:
            return nil
        }
    }
}

/// The values, observable so the Form follows them, and reported to Lisp
/// on every change.
private final class Values: ObservableObject {
    @Published var numbers: [String: Double] = [:]
    @Published var flags: [String: Bool] = [:]
    @Published var choices: [String: String] = [:]
    let changed: (String, String) -> Void

    init(settings: [Setting], changed: @escaping (String, String) -> Void) {
        self.changed = changed
        for setting in settings {
            switch setting {
            case .slider(let n, _, _, let v): numbers[n] = v
            case .toggle(let n, let on): flags[n] = on
            case .picker(let n, let v, _): choices[n] = v
            }
        }
    }
}

private struct SettingsForm: View {
    let title: String
    let settings: [Setting]
    @ObservedObject var values: Values

    var body: some View {
        NavigationStack {
            Form {
                ForEach(settings) { setting in
                    switch setting {
                    case .slider(let name, let lo, let hi, _):
                        VStack(alignment: .leading) {
                            Text("\(name): \(Int(values.numbers[name] ?? lo))")
                            Slider(value: Binding(
                                get: { values.numbers[name] ?? lo },
                                set: { values.numbers[name] = $0; values.changed(name, String(Int($0))) }),
                                   in: lo...hi, step: 1)
                        }
                    case .toggle(let name, _):
                        Toggle(name, isOn: Binding(
                            get: { values.flags[name] ?? false },
                            set: { values.flags[name] = $0; values.changed(name, $0 ? "on" : "off") }))
                    case .picker(let name, _, let options):
                        Picker(name, selection: Binding(
                            get: { values.choices[name] ?? options.first ?? "" },
                            set: { values.choices[name] = $0; values.changed(name, $0) })) {
                            ForEach(options, id: \.self) { Text($0) }
                        }
                    }
                }
            }
            .navigationTitle(title)
        }
    }
}

@objc(LispSettings) public final class LispSettings: NSObject {
    /// A view controller holding the form.  Present it as a sheet.
    /// `specs` describe the settings, one string each; `changed` is called
    /// with a setting's name and its new value as text, on the main thread,
    /// every time a control moves.
    @objc(settingsControllerWithTitle:specs:changed:) @MainActor
    public static func settingsController(title: String, specs: [String],
                                          changed: @escaping (String, String) -> Void) -> UIViewController {
        let settings = specs.compactMap(Setting.init)
        let values = Values(settings: settings, changed: changed)
        return UIHostingController(rootView: SettingsForm(title: title, settings: settings, values: values))
    }
}

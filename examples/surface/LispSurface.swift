// LispSurface.swift -- the Swift side of examples/surface.
//
// Swift Charts gained a third dimension in iOS 26: Chart3D draws a surface
// z = f(x, y), lit and rotatable, from nothing more than the function.  It
// is Swift only, SwiftUI all the way down.  This file hands it to Lisp: the
// function is a block, and Chart3D samples it -- a few thousand times per
// mesh -- by calling back into the Lisp closure the block was made from.
//
// Nothing here knows what the surfaces are.  That is swift.lisp's business.

import Foundation
import UIKit
import SwiftUI
import Charts

/// How many times Chart3D has asked Lisp for a height, for the console.
final class Counter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private struct SurfaceView: View {
    let title: String
    let function: (Double, Double) -> Double
    let counter: Counter
    @State private var pose: Chart3DPose = .default

    var body: some View {
        // Local copies: SurfacePlot's closure is Sendable and may run off
        // the main thread, so it captures values rather than the view.
        let function = function
        let counter = counter
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal, 16)
            // Chart3D's vertical axis is y; x and z are the floor.  The
            // Lisp function takes the two floor coordinates and returns
            // the height, whatever the letters.
            Chart3D {
                SurfacePlot(x: "x", y: "height", z: "z") { x, z in
                    counter.increment()
                    return function(x, z)
                }
                .foregroundStyle(.heightBased)
            }
            .chartXScale(domain: -2 ... 2)
            .chartZScale(domain: -2 ... 2)
            .chartYScale(domain: -1.5 ... 1.5)
            .chart3DPose($pose)
        }
    }
}

@objc(LispSurface) public final class LispSurface: NSObject {
    private static let counter = Counter()

    /// A view controller showing the surface `function` describes, for
    /// UIKit to place as a child.  Drag to turn it.  Main thread only.
    @objc(surfaceControllerWithTitle:function:) @MainActor
    public static func surfaceController(title: String,
                                         function: @escaping (Double, Double) -> Double) -> UIViewController {
        let controller = UIHostingController(rootView: SurfaceView(title: title, function: function,
                                                                    counter: counter))
        controller.view.backgroundColor = .clear
        return controller
    }

    /// How many heights Chart3D has asked Lisp for so far.
    @objc public static var evaluations: Int { counter.count }
}

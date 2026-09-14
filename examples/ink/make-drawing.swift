// make-drawing.swift -- a PencilKit drawing, made on the Mac and shipped as
// a resource.  PKStroke and PKDrawing are Swift only, so a drawing cannot be
// composed from Lisp; it can be loaded, shown, edited, read back and
// rendered, which is what the example does.  Run by build.sh.
import PencilKit
import Foundation

var points: [PKStrokePoint] = []
for i in 0...160 {
    let t = Double(i) / 160 * 6 * .pi
    let r = 10 + 6.5 * t
    let p = CGPoint(x: 180 + r * cos(t), y: 180 + r * sin(t))
    points.append(PKStrokePoint(location: p, timeOffset: Double(i) / 40,
                                size: CGSize(width: 4 + 3 * sin(t), height: 4 + 3 * sin(t)),
                                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
}
let path = PKStrokePath(controlPoints: points, creationDate: Date())
let ink = PKInk(.pen, color: .systemIndigo)
let drawing = PKDrawing(strokes: [PKStroke(ink: ink, path: path)])
try! drawing.dataRepresentation().write(to: URL(fileURLWithPath: "spiral.drawing"))
print("wrote spiral.drawing, \(drawing.bounds)")

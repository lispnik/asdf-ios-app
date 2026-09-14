// make-model.swift -- a Core ML model, trained on the Mac and shipped.
//
// Create ML fits a small regressor to a table Lisp could have made: the
// area of a triangle from its base and height, plus noise.  The point is
// not the model, which is trivial; it is that the app carries a real
// .mlmodelc and runs it from Lisp with feature dictionaries in and out.
import CreateML
import Foundation

var base: [Double] = [], height: [Double] = [], area: [Double] = []
var generator = SystemRandomNumberGenerator()
for _ in 0..<400 {
    let b = Double.random(in: 1...20, using: &generator)
    let h = Double.random(in: 1...20, using: &generator)
    base.append(b); height.append(h)
    area.append(0.5 * b * h + Double.random(in: -0.5...0.5, using: &generator))
}
let table = try MLDataTable(dictionary: ["base": base, "height": height, "area": area])
let model = try MLBoostedTreeRegressor(trainingData: table, targetColumn: "area")
let metadata = MLModelMetadata(author: "asdf-ios-app", shortDescription: "Triangle area from base and height", version: "1")
try model.write(to: URL(fileURLWithPath: "Area.mlmodel"), metadata: metadata)
print("wrote Area.mlmodel; training RMSE \(model.trainingMetrics.rootMeanSquaredError)")

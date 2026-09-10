;;;; layers.asd -- Core Animation, with the path computed in Lisp.

(defsystem "layers"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "layers:start"
  :description "A CGPath built in Lisp, stroked by CAShapeLayer and animated."
  :version "1.0.0"
  :serial t
  :depends-on ("objc-lite")
  :components ((:file "layers"))

  :bundle-identifier "org.asdf-ios-app.layers"
  :bundle-name "Layers"
  :bundle-executable "layers"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)

  ;; No trampolines, which is the surprising part. Core Graphics' path
  ;; functions take CGFloats and pointers -- the CGAffineTransform argument is
  ;; a POINTER to a struct, not a struct -- and Core Animation's properties are
  ;; objects. Nothing here passes an aggregate by value except CGRect and
  ;; CGPoint arguments, which travel as doubles by the coincidence
  ;; examples/abi-probe measures.
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "QuartzCore"))

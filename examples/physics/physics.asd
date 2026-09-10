;;;; physics.asd -- UIKit Dynamics, driven from Lisp.

(defsystem "physics"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "physics:start"
  :description "Gravity, collisions and elasticity, with the shapes made in Lisp."
  :version "1.0.0"
  :serial t
  :depends-on ("objc-lite")
  :components ((:file "glue-package")
               (:file "physics"))

  :bundle-identifier "org.asdf-ios-app.physics"
  :bundle-name "Physics"
  :bundle-executable "physics"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)

  ;; One function, four lines of C. -[UITapGestureRecognizer locationInView:]
  ;; returns a CGPoint BY VALUE, and a returned struct is the case the dynamic
  ;; FFI can never express -- see examples/abi-probe. Everything else in this
  ;; app goes through objc-lite; this is what the escape hatch looks like at
  ;; its smallest.
  :bundle-trampolines ("glue.lisp")
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

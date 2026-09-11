;;;; physics.asd -- UIKit Dynamics, driven from Lisp.

(defsystem "physics"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "physics:start"
  :description "Gravity, collisions and elasticity, with the shapes made in Lisp."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "physics"))

  :bundle-identifier "org.asdf-ios-app.physics"
  :bundle-name "Physics"
  :bundle-executable "physics"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)

  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

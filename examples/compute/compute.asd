;;;; compute.asd -- Metal on iOS: a compute kernel written and dispatched from Lisp.

(defsystem "compute"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "compute:start"
  :description "A Metal compute kernel compiled from a string at run time, its parameters and buffer from Lisp, its threadgroups sized with MTLSize structures passed as vectors, and its output turned into an image."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "compute"))

  :bundle-identifier "org.asdf-ios-app.compute"
  :bundle-name "Compute"
  :bundle-executable "compute"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "Metal"))

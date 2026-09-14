;;;; coreml.asd -- a Core ML model, trained on the Mac, run from Lisp on the phone.

(defsystem "coreml"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "coreml:start"
  :description "Core ML from Lisp: a compiled model shipped as a resource, loaded, and asked for predictions through feature providers built from Lisp numbers, against the exact answer Lisp computes."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "coreml"))

  :bundle-identifier "org.asdf-ios-app.coreml"
  :bundle-name "CoreML"
  :bundle-executable "coreml"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "CoreML")
  ;; The compiled model, from build.sh: Create ML trains it, coremlc compiles it.
  :bundle-resources ("Area.mlmodelc")
  :perform (asdf::ios-app-op :before (o c)
             (uiop:run-program (list "/bin/sh" (namestring (asdf:system-relative-pathname c "build.sh")))
                               :output t :error-output t)))

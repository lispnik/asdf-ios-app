;;;; model.asd -- the on-device language model, with its tools written in Lisp.

(defsystem "model"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "model-ios:start"
  :description "FoundationModels from Lisp: the on-device model answers arithmetic by calling tools that are Lisp closures."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "model"))

  :bundle-identifier "org.asdf-ios-app.model"
  :bundle-name "Model"
  :bundle-executable "model"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  ;; FoundationModels is iOS 26.
  :bundle-minimum-os-version "26.0"

  ;; The Swift side, as a framework per platform; see examples/swift for the
  ;; mechanism.
  :bundle-embedded-frameworks ("build/~a/LispModel.framework")
  :perform (asdf::ios-app-op :before (o c)
             (uiop:run-program (list "/bin/sh" (namestring (asdf:system-relative-pathname c "build.sh")))
                               :output t :error-output t)))

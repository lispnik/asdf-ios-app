;;;; surface.asd -- a 3D surface plot whose surface is a Lisp function.

(defsystem "surface"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "surface-ios:start"
  :description "Swift Charts 3D from Lisp: Chart3D samples a surface by calling a block made from a Lisp lambda, thousands of times per mesh."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "surface"))

  :bundle-identifier "org.asdf-ios-app.surface"
  :bundle-name "Surface"
  :bundle-executable "surface"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  ;; Chart3D is iOS 26.
  :bundle-minimum-os-version "26.0"

  :bundle-embedded-frameworks ("build/~a/LispSurface.framework")
  :perform (asdf::ios-app-op :before (o c)
             (uiop:run-program (list "/bin/sh" (namestring (asdf:system-relative-pathname c "build.sh")))
                               :output t :error-output t)))

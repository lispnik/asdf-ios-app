;;;; ink.asd -- PencilKit: a canvas drawn on, read back by Lisp.

(defsystem "ink"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "ink:start"
  :description "A PencilKit canvas whose every change reaches a Lisp delegate, which reads the drawing's bounds, renders it, and keeps it."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "ink"))

  :bundle-identifier "org.asdf-ios-app.ink"
  :bundle-name "Ink"
  :bundle-executable "ink"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "PencilKit")
  ;; A drawing made on the Mac by build.sh, shipped and loaded at launch.
  :bundle-resources ("spiral.drawing")
  :perform (asdf::ios-app-op :before (o c)
             (uiop:run-program (list "/bin/sh" (namestring (asdf:system-relative-pathname c "build.sh")))
                               :output t :error-output t)))

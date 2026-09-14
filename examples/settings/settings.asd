;;;; settings.asd -- a SwiftUI settings sheet whose values are Lisp's.

(defsystem "settings"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "settings-ios:start"
  :description "SwiftUI controls editing Lisp variables: every slider, toggle and picker change crosses the bridge and Lisp redraws."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "settings"))

  :bundle-identifier "org.asdf-ios-app.settings"
  :bundle-name "Settings"
  :bundle-executable "settings"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-minimum-os-version "16.0"

  :bundle-embedded-frameworks ("build/~a/LispSettings.framework")
  :perform (asdf::ios-app-op :before (o c)
             (uiop:run-program (list "/bin/sh" (namestring (asdf:system-relative-pathname c "build.sh")))
                               :output t :error-output t)))

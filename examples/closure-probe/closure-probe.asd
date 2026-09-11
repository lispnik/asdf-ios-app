;;;; closure-probe.asd -- can ECL make a libffi closure on a phone, and call it?

(defsystem "closure-probe"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "closure-probe:start"
  :description "Measures SI:MAKE-DYNAMIC-CALLBACK on the device it is meant for."
  :version "1.0.0"
  :serial t
  :components ((:file "glue-package")
               (:file "probe"))

  :bundle-identifier "org.asdf-ios-app.closure-probe"
  :bundle-name "ClosureProbe"
  :bundle-executable "closure-probe"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment below says how. The simulator is always ad hoc.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here:
  ;;
  ;;   IOS_SIGNING_IDENTITY      "Apple Development: Name (XXXXXXXXXX)"
  ;;   IOS_DEVELOPMENT_TEAM      the ten-character team identifier
  ;;   IOS_PROVISIONING_PROFILE  path to a .mobileprovision
  ;;
  ;; Unset, the simulator build is ad hoc as usual and a device build
  ;; refuses with the reason.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE")

  ;; The C side: a caller that invokes a function pointer the way any
  ;; framework would, and a text view to show the report on a screen.
  :bundle-trampolines ("glue.lisp")
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

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
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "Metal")

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

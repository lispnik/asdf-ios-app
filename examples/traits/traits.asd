;;;; traits.asd -- dark mode and Dynamic Type, answered from Lisp.

(defsystem "traits"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "traits:start"
  :description "The trait collection: appearance, text size, size class and scale read in Lisp, and a block registered for their changes that re-lays the screen when the system flips them."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "traits"))

  :bundle-identifier "org.asdf-ios-app.traits"
  :bundle-name "Traits"
  :bundle-executable "traits"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait :landscape-left :landscape-right)

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

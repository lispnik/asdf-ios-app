;;;; keychain.asd -- the Keychain, through the Security framework's C API.

(defsystem "keychain"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "keychain:start"
  :description "SecItemAdd, SecItemCopyMatching, SecItemUpdate and SecItemDelete from Lisp, with their CFDictionary queries built from Foundation objects: a secret that survives relaunches and lives nowhere Lisp can read by accident."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "keychain"))

  :bundle-identifier "org.asdf-ios-app.keychain"
  :bundle-name "Keychain"
  :bundle-executable "keychain"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "Security")

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

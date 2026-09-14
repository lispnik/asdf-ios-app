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
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "Security"))

;;;; swift.asd -- frameworks with no Objective-C surface, reached through Swift.

(defsystem "swift"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "swift-ios:start"
  :description "CryptoKit, Swift Charts in SwiftUI and FoundationModels, from Lisp, through a hundred lines of @objc Swift shipped as a framework."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "swift"))

  :bundle-identifier "org.asdf-ios-app.swift"
  :bundle-name "Swift"
  :bundle-executable "swift"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  ;; Swift Charts and SwiftUI's ImageRenderer arrived in iOS 16.
  :bundle-minimum-os-version "16.0"

  ;; The point of the example.  A framework is built per platform, so the
  ;; entry names the platform with ~A: build.sh leaves one under each of
  ;; build/iphonesimulator/ and build/iphoneos/.  It goes into the bundle's
  ;; Frameworks/, is linked with an rpath that finds it there, and is signed
  ;; before the app is.
  :bundle-embedded-frameworks ("build/~a/LispSwift.framework")

  ;; Build the framework first, when the Swift is newer than it.  Needs
  ;; swiftc, which is Xcode's; nothing else in this repository does.
  :perform (asdf::ios-app-op :before (o c)
             (uiop:run-program (list "/bin/sh" (namestring (asdf:system-relative-pathname c "build.sh")))
                               :output t :error-output t)))

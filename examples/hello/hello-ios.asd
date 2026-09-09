;;;; hello-ios.asd -- the smallest iOS application.

(defsystem "hello-ios"
  :defsystem-depends-on ("asdf-ios-app")
  :description "A label, and the least you can write that produces an app."
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "hello-ios:start"
  :version "1.0.0"
  :serial t
  :components ((:file "hello"))

  :bundle-identifier "org.asdf-ios-app.hello"
  :bundle-name "Hello"
  :bundle-executable "hello"
  :bundle-platforms (:simulator))

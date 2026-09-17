;;;; exceptions.asd -- three failures earned on purpose, on a phone.

(defsystem "exceptions"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "exceptions:start"
  :description "An NSRangeException, an NSInvalidArgumentException and an NSError, each earned on purpose and shown as the Lisp condition it becomes."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "exceptions"))

  :bundle-identifier "org.asdf-ios-app.exceptions"
  :bundle-name "Exceptions"
  :bundle-executable "exceptions"
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

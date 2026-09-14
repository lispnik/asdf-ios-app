;;;; fetch.asd -- JSON over the network, decoded in Lisp, shown in a table.

(defsystem "fetch"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "fetch-ios:start"
  :description "NSURLSession from Lisp: a request whose completion block is a Lisp closure, arriving on a background queue with JSON that Lisp walks and lists."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "fetch"))

  :bundle-identifier "org.asdf-ios-app.fetch"
  :bundle-name "Fetch"
  :bundle-executable "fetch"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait))

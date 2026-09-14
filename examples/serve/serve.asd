;;;; serve.asd -- an HTTP server in the app, on Network.framework, found by Bonjour.

(defsystem "serve"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "serve:start"
  :description "Network.framework from Lisp: a listener whose connection, receive and send handlers are Lisp blocks on a dispatch queue, serving a page about the image to any browser, and advertised over Bonjour."
  :version "1.0.0"
  :serial t
  ;; BABEL is named rather than relied on through CFFI, for the UTF-8.
  :depends-on ("objc/uikit" "babel")
  :components ((:file "serve"))

  :bundle-identifier "org.asdf-ios-app.serve"
  :bundle-name "Serve"
  :bundle-executable "serve"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "Network")
  ;; Bonjour advertising needs the service type declared.
  :bundle-info-plist (("NSBonjourServices" . (:array "_http._tcp"))
                      ("NSLocalNetworkUsageDescription" . "To be found by browsers on the network.")))

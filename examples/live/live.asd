;;;; live.asd -- a phone you program from Emacs.
;;;;
;;;; The app is a canvas, a caption and a button, and every one of them is a
;;;; function you redefine over SLY while the phone is in your hand. Nothing
;;;; here is the point; the tour in tour.lisp is.

(defsystem "live"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "live:start"
  :description "A canvas, a caption and a button, all of them Lisp you redefine from Emacs."
  :version "1.0.0"
  :serial t
  ;; slynk is not on Quicklisp under that name: put sly's slynk/ directory on
  ;; your source registry. It is the whole demonstration, so it is not optional.
  :depends-on ("objc/uikit" "slynk")
  :components ((:file "live"))

  :bundle-identifier "org.asdf-ios-app.live"
  :bundle-name "Live"
  :bundle-executable "live"

  ;; A device build must be signed, and is built for only when it can be:
  ;; identity, team and profile come from the environment at read time --
  ;; IOS_SIGNING_IDENTITY, IOS_DEVELOPMENT_TEAM, IOS_PROVISIONING_PROFILE --
  ;; so that nobody's identity is committed here. Unset, this is a simulator
  ;; build, ad hoc signed, as usual.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE")
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics")

  ;; On, on a device too. slynk listens on the phone's loopback before the
  ;; entry point runs; iproxy carries port 4005 over the USB cable and
  ;; M-x sly-connect to localhost does the rest. Loopback only: this is an
  ;; unauthenticated eval server, and the cable is the whole security model.
  :remote-repl t)

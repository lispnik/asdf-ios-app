;;;; attractor-dynamic.asd -- the de Jong attractor again, with no C anywhere:
;;;; everything through the dynamic FFI, nothing compiled ahead of time.

(defsystem "attractor-dynamic"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "attractor-dynamic:start"
  :description "The attractor with its drawRect: in Lisp and its pixels from Lisp memory."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "attractor-dynamic"))

  :bundle-identifier "org.asdf-ios-app.attractor-dynamic"
  :bundle-name "AttractorDynamic"
  :bundle-executable "attractor-dynamic"

  ;; A device build must be signed, and is built for only when it can be:
  ;; identity, team and profile come from the environment at read time --
  ;; IOS_SIGNING_IDENTITY, IOS_DEVELOPMENT_TEAM, IOS_PROVISIONING_PROFILE --
  ;; so that nobody's identity is committed here.  Unset, this is a simulator
  ;; build, ad hoc signed, as usual.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE")
  :bundle-orientations (:portrait :landscape-left :landscape-right)

  ;; No :bundle-trampolines.  The sibling `attractor-aot' keeps a C file for its
  ;; drawRect: and its point loop; this one has neither, which is the point.
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

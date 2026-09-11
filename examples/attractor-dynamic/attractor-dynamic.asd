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
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait :landscape-left :landscape-right)

  ;; No :bundle-trampolines.  The sibling `attractor-aot' keeps a C file for its
  ;; drawRect: and its point loop; this one has neither, which is the point.
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

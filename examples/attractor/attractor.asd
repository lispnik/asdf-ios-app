;;;; attractor.asd -- a de Jong attractor, drawn by Lisp, on a phone.

(defsystem "attractor"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "attractor:start"
  :description "Two million points of arithmetic, and a view whose drawRect: is Lisp."
  :version "1.0.0"
  :serial t
  :components ((:file "glue-package")
               (:file "attractor"))

  :bundle-identifier "org.asdf-ios-app.attractor"
  :bundle-name "Attractor"
  :bundle-executable "attractor"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait :landscape-left :landscape-right)

  ;; The C side. Cross-compiled only, which is what lets it use FFI:C-INLINE:
  ;; a drawRect: IMP receives a CGRect BY VALUE, and no Lisp-side FFI on ECL
  ;; can name an aggregate.
  :bundle-trampolines ("glue.lisp")
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

;;;; repl.asd -- a read-eval-print loop with a keyboard, on the phone.

(defsystem "repl"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "ios-repl:start"
  :description "A REPL you type into, with a UITextFieldDelegate written in Lisp."
  :version "1.0.0"
  :serial t
  :depends-on ("objc-lite")
  :components ((:file "repl"))

  :bundle-identifier "org.asdf-ios-app.repl"
  :bundle-name "Repl"
  :bundle-executable "repl"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)

  ;; No :BUNDLE-TRAMPOLINES. Nothing here takes or returns a struct: the
  ;; delegate method is BOOL(id, SEL, id), and the layout is anchors and
  ;; CGFloats. FFI:DEFCALLBACK in an ordinary component is enough.
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

;;;; editor.asd -- a Lisp editor on the phone: TextKit, highlighted by Lisp.

(defsystem "editor"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "editor:start"
  :description "A UITextView highlighted by a Lisp tokenizer on every keystroke, parentheses matched at the cursor, and the buffer evaluated in the image it runs in."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "editor"))

  :bundle-identifier "org.asdf-ios-app.editor"
  :bundle-name "Editor"
  :bundle-executable "editor"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait :landscape-left :landscape-right))

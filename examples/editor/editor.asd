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
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait :landscape-left :landscape-right)

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

;;;; objc-lite.asd -- the smallest Objective-C bridge that is useful.
;;;;
;;;; Shared by the examples beside it. Not part of asdf-ios-app: the real
;;;; interface is the objc library, and this is what you write in an afternoon
;;;; when you would rather not take a dependency.

(defsystem "objc-lite"
  :description "Send Objective-C messages, and define classes, from Lisp."
  :version "1.0.0"
  :serial t
  :components ((:file "package")
               (:file "objc-lite")))

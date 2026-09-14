;;;; traits.asd -- dark mode and Dynamic Type, answered from Lisp.

(defsystem "traits"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "traits:start"
  :description "The trait collection: appearance, text size, size class and scale read in Lisp, and a block registered for their changes that re-lays the screen when the system flips them."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "traits"))

  :bundle-identifier "org.asdf-ios-app.traits"
  :bundle-name "Traits"
  :bundle-executable "traits"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait :landscape-left :landscape-right))

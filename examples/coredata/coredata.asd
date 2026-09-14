;;;; coredata.asd -- Core Data, with the model built in code from Lisp.

(defsystem "coredata"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "coredata:start"
  :description "Core Data from Lisp: an entity and its attributes described in code, a persistent container loaded through a block, objects inserted, saved, and fetched with a predicate and a sort."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "coredata"))

  :bundle-identifier "org.asdf-ios-app.coredata"
  :bundle-name "CoreData"
  :bundle-executable "coredata"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "CoreData"))

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
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "CoreData")

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

;;;; sprites.asd -- SpriteKit and GameplayKit, with the rules in Lisp.

(defsystem "sprites"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "sprites:start"
  :description "A SpriteKit scene of agents steered by GameplayKit behaviours, the goals and weights chosen in Lisp, the scene's per-frame update a Lisp method, and a Lisp-built graph pathfound by GameplayKit."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "sprites"))

  :bundle-identifier "org.asdf-ios-app.sprites"
  :bundle-name "Sprites"
  :bundle-executable "sprites"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "SpriteKit" "GameplayKit")

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

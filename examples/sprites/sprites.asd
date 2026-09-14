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
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "SpriteKit" "GameplayKit"))

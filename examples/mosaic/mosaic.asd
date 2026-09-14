;;;; mosaic.asd -- a collection view laid out by a Lisp delegate returning structs.

(defsystem "mosaic"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "mosaic:start"
  :description "The packages of the running image as a mosaic: a UICollectionView whose flow-layout delegate is a Lisp class returning CGSize and UIEdgeInsets by value."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "mosaic"))

  :bundle-identifier "org.asdf-ios-app.mosaic"
  :bundle-name "Mosaic"
  :bundle-executable "mosaic"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait :landscape-left :landscape-right))

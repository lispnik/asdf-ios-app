;;;; photos.asd -- the photo library, read and written from Lisp.

(defsystem "photos"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "photos:start"
  :description "PhotoKit from Lisp: the library's assets fetched and thumbnailed through result blocks, and an image rendered pixel by pixel in Lisp saved back into it."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "photos"))

  :bundle-identifier "org.asdf-ios-app.photos"
  :bundle-name "Photos"
  :bundle-executable "photos"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "Photos" "PhotosUI")
  :bundle-info-plist (("NSPhotoLibraryUsageDescription" . "To list the library from Lisp, and add a picture Lisp drew.")
                      ("NSPhotoLibraryAddUsageDescription" . "To add a picture Lisp drew.")))

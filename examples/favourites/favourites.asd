;;;; favourites.asd -- the songs favourited in Music, listed by Lisp.

(defsystem "favourites"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "favourites-ios:start"
  :description "MediaPlayer from Lisp: the media library's authorisation asked for through a block, the Favorite Songs playlist found among the library's playlists with MPMediaQuery, and its songs read out property by property into a table whose data source is a Lisp class."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "favourites"))

  :bundle-identifier "org.asdf-ios-app.favourites"
  :bundle-name "Favourites"
  :bundle-executable "favourites"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.  This is
  ;; the one example with nothing to show on a simulator: it has no library.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "MediaPlayer")
  :bundle-info-plist (("NSAppleMusicUsageDescription" . "To list the songs you have favourited, from Lisp."))

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

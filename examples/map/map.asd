;;;; map.asd -- MapKit and CoreLocation, from Lisp.

(defsystem "map"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "map-ios:start"
  :description "A map centred on the phone's location, with a route computed in Lisp drawn over it; the location delegate and the overlay renderer delegate are Lisp classes, and the region is a nested structure passed as a vector."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "map"))

  :bundle-identifier "org.asdf-ios-app.map"
  :bundle-name "Map"
  :bundle-executable "map"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "MapKit" "CoreLocation")
  :bundle-info-plist (("NSLocationWhenInUseUsageDescription" . "To centre the map where the phone is."))

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

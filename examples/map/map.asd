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
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "MapKit" "CoreLocation")
  :bundle-info-plist (("NSLocationWhenInUseUsageDescription" . "To centre the map where the phone is.")))

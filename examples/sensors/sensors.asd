;;;; sensors.asd -- what only a device has: motion, haptics, biometrics.

(defsystem "sensors"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "sensors:start"
  :description "A bubble level from the accelerometer, a haptic tap, and Face ID: three things a simulator cannot do, each reached from Lisp through a block on a background queue."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "sensors"))

  :bundle-identifier "org.asdf-ios-app.sensors"
  :bundle-name "Sensors"
  :bundle-executable "sensors"
  ;; Both, so that the interface can be checked on the simulator, where
  ;; each of the three reports itself unavailable, and the device build is
  ;; the one that matters.  A device build takes its signing from the
  ;; environment, as the attractor examples do.
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as closure-probe does.  A runner has no
  ;; identity, no profile, and no iphoneos ECL prefix, and this is the one
  ;; example that is really about the phone.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "CoreMotion" "LocalAuthentication")
  :bundle-info-plist (("NSFaceIDUsageDescription" . "To show that Face ID can be asked for from Lisp.")
                      ("NSMotionUsageDescription" . "To show the accelerometer from Lisp."))
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

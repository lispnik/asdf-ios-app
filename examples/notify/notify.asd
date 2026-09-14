;;;; notify.asd -- local notifications, scheduled and received by Lisp.

(defsystem "notify"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "notify-ios:start"
  :description "UNUserNotificationCenter from Lisp: authorisation through a block, a notification scheduled from Lisp, and a delegate written in Lisp that presents it and hears the tap."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "notify"))

  :bundle-identifier "org.asdf-ios-app.notify"
  :bundle-name "Notify"
  :bundle-executable "notify"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "UserNotifications"))

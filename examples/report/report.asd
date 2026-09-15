;;;; report.asd -- a PDF written by Lisp, previewed and shared.

(defsystem "report"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "report:start"
  :description "UIGraphicsPDFRenderer drawing a report from Lisp data inside its actions block, Quick Look previewing it through a Lisp data source, and the share sheet offering it."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "report"))

  :bundle-identifier "org.asdf-ios-app.report"
  :bundle-name "Report"
  :bundle-executable "report"
  ;; The device is built for only when it can be signed for, which is when
  ;; the environment says how -- as sensors and closure-probe do.
  :bundle-platforms #.(if (uiop:getenv "IOS_SIGNING_IDENTITY")
                          '(:simulator :device)
                          '(:simulator))
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "QuickLook")

  ;; A device build must be signed. Read from the environment at the time
  ;; this file is read, so that nobody's identity is committed here.
  :code-signing-identity #.(or (uiop:getenv "IOS_SIGNING_IDENTITY") :automatic)
  :development-team #.(uiop:getenv "IOS_DEVELOPMENT_TEAM")
  :provisioning-profile #.(uiop:getenv "IOS_PROVISIONING_PROFILE"))

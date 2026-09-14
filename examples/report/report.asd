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
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "QuickLook"))

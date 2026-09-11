;;;; chart.asd -- Lisp writes the document, WebKit renders it.

(defsystem "chart"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "chart:start"
  :description "SVG generated in Lisp, shown in a WKWebView, with a remembered choice."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "chart"))

  :bundle-identifier "org.asdf-ios-app.chart"
  :bundle-name "Chart"
  :bundle-executable "chart"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait :landscape-left :landscape-right)

  ;; Shipped alongside the executable and read back at run time with
  ;; IOS-APP-RUNTIME:BUNDLE-RESOURCE. The bundle is read-only; anything the app
  ;; writes goes to Documents, which is where HOME points.
  :bundle-resources ("style.css")

  ;; WebKit is the point of the example: a framework beyond UIKit, added by
  ;; naming it here and nothing else.
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "WebKit"))

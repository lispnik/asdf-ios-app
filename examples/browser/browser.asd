;;;; browser.asd -- a UITableView whose data source is Lisp.

(defsystem "browser"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "browser:start"
  :description "Browse the running image: packages, symbols, and what they are."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "browser"))

  :bundle-identifier "org.asdf-ios-app.browser"
  :bundle-name "Browser"
  :bundle-executable "browser"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)

  ;; Again no trampolines. UITableViewDataSource is NSInteger and id all the
  ;; way down, and -[UITableView init] avoids -initWithFrame:style:, which
  ;; would have wanted a CGRect.
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

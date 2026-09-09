;;;; asdf-ios-app.asd

(defsystem "asdf-ios-app"
  :description "ASDF extension that builds iOS .app bundles from ECL."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ()
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "plist")
                             (:file "toolchain")
                             (:file "bootstrap")
                             (:file "bundle")
                             (:file "compile")
                             (:file "link")
                             (:file "sign")
                             (:file "deploy")
                             (:file "op"))))
  :in-order-to ((test-op (test-op "asdf-ios-app/tests"))))

(defsystem "asdf-ios-app/tests"
  :description "Test suite for asdf-ios-app."
  :depends-on ("asdf-ios-app")
  :serial t
  :components ((:module "tests"
                :components ((:file "framework")
                             (:file "unit"))))
  :perform (test-op (o c)
             (let ((failures (uiop:symbol-call :asdf-ios-app-tests '#:run-all)))
               (unless (zerop failures)
                 (error "~d test failure~:p." failures)))))

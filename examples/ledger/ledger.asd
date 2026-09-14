;;;; ledger.asd -- SQLite and a static C library of the app's own.

(defsystem "ledger"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "ledger:start"
  :description "A ledger kept in SQLite through the dynamic FFI, each entry fingerprinted by a C function linked in as a static library."
  :version "1.0.0"
  :serial t
  :depends-on ("objc/uikit")
  :components ((:file "ledger"))

  :bundle-identifier "org.asdf-ios-app.ledger"
  :bundle-name "Ledger"
  :bundle-executable "ledger"
  :bundle-platforms (:simulator)
  :bundle-orientations (:portrait)

  ;; SQLite ships with iOS; naming it is a linker flag.
  :bundle-link-flags ("-lsqlite3")

  ;; The app's own C, as an archive per platform from build.sh.
  :bundle-static-libraries ("build/~a/libfingerprint.a")
  :perform (asdf::ios-app-op :before (o c)
             (uiop:run-program (list "/bin/sh" (namestring (asdf:system-relative-pathname c "build.sh")))
                               :output t :error-output t)))

;;;; abi-probe.asd -- what ECL's dynamic FFI can and cannot do with a struct.

(defsystem "abi-probe"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "abi-probe:start"
  :description "Measures ECL's dynamic FFI against the C compiler on struct-by-value."
  :version "1.0.0"
  :serial t
  :components ((:file "glue-package")
               (:file "probe"))

  :bundle-identifier "org.asdf-ios-app.abi-probe"
  :bundle-name "AbiProbe"
  :bundle-executable "abi-probe"
  :bundle-platforms (:simulator)

  ;; The C side. Cross-compiled only, which is what lets it use FFI:C-INLINE
  ;; and so produce ground truth the dynamic FFI can be compared against.
  :bundle-trampolines ("glue.lisp")
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics"))

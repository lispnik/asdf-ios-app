;;;; glue-package.lisp -- declared apart from glue.lisp, which is never
;;;; compiled on the host. See the header of glue.lisp.

(defpackage #:abi-probe-glue
  (:use #:cl)
  (:export #:probe-address
           #:truth-take-hfa4 #:truth-take-hfa6
           #:truth-take-int2 #:truth-take-mixed
           #:truth-make-hfa4 #:truth-make-hfa6
           #:truth-make-int2 #:truth-make-mixed
           #:struct-sizes
           #:show-text))

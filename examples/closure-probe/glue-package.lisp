;;;; glue-package.lisp -- declared apart from glue.lisp, which is never
;;;; compiled on the host.

(defpackage #:closure-probe-glue
  (:use #:cl)
  (:export #:call-from-c #:show-text))

;;;; glue-package.lisp -- declared apart from glue.lisp, which is compiled for
;;;; the target only and so never runs its DEFPACKAGE on the host.

(defpackage #:physics-glue
  (:use #:cl)
  (:export #:location-in-view #:view-size))

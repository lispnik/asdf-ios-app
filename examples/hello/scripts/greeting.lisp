;;;; greeting.lisp -- interpreted, and therefore editable in place.

(defpackage #:hello-scripts
  (:use #:cl)
  (:export #:greeting))

(in-package #:hello-scripts)

(defun greeting ()
  "Change this line, rebuild nothing but the copy, and the app says something
else. That is the whole point of :BUNDLE-INTERPRETED."
  "edited without a rebuild")

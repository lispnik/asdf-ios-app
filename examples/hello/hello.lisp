;;;; hello.lisp

(defpackage #:hello-ios
  (:use #:cl)
  (:export #:start))

(in-package #:hello-ios)

(defun start ()
  "Called once, on the main thread, from the app delegate. Must RETURN: the
run loop has not started yet, and blocking here means an app that never draws."
  (format t "~&HELLO: ~a ~a on ~a~%"
          (lisp-implementation-type) (lisp-implementation-version)
          (machine-type))
  (format t "HELLO: compiled ahead of time, and still live: ~a~%"
          (eval '(let ((x 6) (y 7)) (* x y))))
  (finish-output))

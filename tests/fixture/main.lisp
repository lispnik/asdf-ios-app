;;;; main.lisp -- the smallest thing that proves Lisp is running on iOS.

(defpackage #:ios-app-fixture
  (:use #:cl)
  (:export #:start))

(in-package #:ios-app-fixture)

(defun start ()
  "Called from ECLBoot on the main thread. Must return: the run loop follows."
  (format t "~&FIXTURE: hello from Lisp on iOS~%")
  (format t "FIXTURE: ~a ~a on ~a~%"
          (lisp-implementation-type) (lisp-implementation-version)
          (machine-type))
  (format t "FIXTURE: (+ 40 2) = ~d~%" (+ 40 2))
  ;; The image is live even though this file was compiled ahead of time.
  (let ((f (eval '(defun defined-at-runtime (x) (* x 3)))))
    (declare (ignore f))
    (format t "FIXTURE: defined at runtime, (defined-at-runtime 14) = ~d~%"
            (funcall (read-from-string "ios-app-fixture::defined-at-runtime") 14)))
  ;; Proves the module init story: names pushed onto *MODULES* before the
  ;; inits ran, so this does not go hunting for a .fas under ECLDIR.
  (handler-case
      (progn (require :sockets)
             (format t "FIXTURE: sockets present: ~a~%"
                     (and (find-package "SB-BSD-SOCKETS") t)))
    (error (e) (format t "FIXTURE: sockets FAILED: ~a~%" e)))
  (finish-output))

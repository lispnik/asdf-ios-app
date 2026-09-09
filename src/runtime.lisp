;;;; runtime.lisp -- the half of the boot that runs on the phone.
;;;;
;;;; This file is compiled TWICE: once into the build image, where
;;;; ASDF-IOS-APP also lives, and once -- cross-compiled -- as module zero of
;;;; the application's own library, where nothing else does. So it defines its
;;;; own package and depends on nothing, not even UIOP.
;;;;
;;;; Keeping the logic here rather than in ECLBoot.m is deliberate. Objective-C
;;;; in this project should be a shim you can read in one sitting; anything
;;;; with a decision in it belongs in Lisp, where it can be exercised on the
;;;; host instead of only on a device.

(defpackage #:ios-app-runtime
  (:use #:cl)
  (:nicknames #:app-runtime)
  (:export #:%boot
           #:evaluate-to-string
           #:*bundle-path*
           #:bundle-resource
           #:root-view-controller-name
           #:set-root-view-controller
           #:*entry-point*))

(in-package #:ios-app-runtime)

(defvar *bundle-path* nil
  "The bundle's resource directory, as a string with a trailing slash.
Set from Objective-C before %BOOT runs; CL-USER is where it lands, because the
generated header cannot name a package that does not exist yet.")

(defvar *entry-point* nil
  "The symbol the application named with :ENTRY-POINT.")

(defvar *root-view-controller* nil
  "An Objective-C class NAME, set by the entry point if it wants one.")

(defun bundle-resource (name)
  "The full path of a file bundled with the application."
  (let ((root (or *bundle-path*
                  (symbol-value (find-symbol "*BUNDLE-PATH*" "CL-USER")))))
    (when root (concatenate 'string root name))))

(defun set-root-view-controller (class-name)
  "Ask the app delegate to install CLASS-NAME as the root view controller.

A name rather than a pointer: the delegate has to look the class up in the
Objective-C runtime anyway, and a string survives being read back out of a
freshly booted image with no bridging."
  (setf *root-view-controller* class-name))

(defun root-view-controller-name ()
  (or *root-view-controller* ""))

;;; ------------------------------------------------------------------
;;; evaluation

(defun evaluate-to-string (source)
  "Read, evaluate and print one form, returning a string no matter what.

Errors come back as text rather than being signalled, because the caller is
Objective-C: a condition unwinding through a UIKit frame corrupts it."
  (handler-case
      (let ((values (multiple-value-list (eval (read-from-string source)))))
        (if values
            (format nil "~{~s~^~%~}" values)
            ""))
    (error (e) (format nil "; ~a: ~a" (type-of e) e))))

;;; ------------------------------------------------------------------
;;; interpreted components

(defun load-bundled-sources (manifest)
  "LOAD the sources listed in MANIFEST, in order.

Written by the build for systems marked :BUNDLE-INTERPRETED. They are shipped
as source precisely so they can be edited without a rebuild, so a failure in
one is reported and skipped rather than being allowed to stop the launch."
  (let ((path (bundle-resource manifest)))
    (when (and path (probe-file path))
      (with-open-file (in path)
        (let ((*read-eval* nil))
          (dolist (name (read in))
            (let ((file (bundle-resource name)))
              (handler-case (load file :verbose nil :print nil)
                (error (e)
                  (format t "~&; ~a failed to load: ~a~%" name e)
                  (finish-output))))))))))

;;; ------------------------------------------------------------------
;;; boot

(defun guard-dynamic-callbacks ()
  "Make SI::MAKE-DYNAMIC-CALLBACK signal rather than kill the process.

FFI:DEFCALLBACK in interpreted code takes the libffi-closure path, and
ffi_closure_alloc needs writable-then-executable memory, which iOS refuses.
The process does not get an error: it dies, silently and uncatchably. Turning
that into a condition costs a redefinition of an internal and is worth it."
  (let ((symbol (find-symbol "MAKE-DYNAMIC-CALLBACK" "SI")))
    (when (and symbol (fboundp symbol))
      (setf (symbol-function symbol)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "FFI:DEFCALLBACK cannot work in interpreted code on iOS: ~
                      a libffi closure needs executable memory, which iOS does ~
                      not grant, and allocating one kills the process. ~
                      Compile this system ahead of time instead of listing it ~
                      in :BUNDLE-INTERPRETED."))))))

(defun %boot (&key entry-point manifest (guard-callbacks t))
  "Called from ECLBoot once the image is up. Returns; the run loop follows."
  (setf *bundle-path* (symbol-value (find-symbol "*BUNDLE-PATH*" "CL-USER")))
  (when guard-callbacks
    (guard-dynamic-callbacks))
  (when manifest
    (load-bundled-sources manifest))
  (when entry-point
    (let ((symbol (ignore-errors (read-from-string entry-point))))
      (setf *entry-point* symbol)
      (cond ((and symbol (fboundp symbol))
             (handler-case (funcall symbol)
               (error (e)
                 (format t "~&; entry point ~a signalled: ~a~%" entry-point e)
                 (finish-output))))
            (t
             (format t "~&; entry point ~a is not fbound~%" entry-point)
             (finish-output)))))
  t)

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
           #:*entry-point*
           #:on-main
           #:with-main-thread
           #:start-remote-repl
           #:*remote-repl-port*
           #:boot-failure))

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

(defvar *on-main-hook* nil
  "A function of one argument -- a thunk -- that runs it on the main thread.

Set from ECLBoot.m at boot, to a C function that does the real GCD dispatch.
A variable rather than a redefinable function on purpose: ECL compiles a call
to a function defined in the same file as a direct C call, so replacing
ON-MAIN's callee through its FDEFINITION does nothing at all -- the call never
consults the symbol. That failure is silent and it looks exactly like a
working bridge: the thunk still runs, just on the wrong thread.

NIL means no bridge, which is the right answer on the host: the test suite has
no main queue to dispatch to and no UIKit to protect.")

(defun on-main (thunk)
  "Run THUNK on the main thread, waiting for it, and return its value.

UIKit is main-thread only and almost nothing in a Lisp image is on the main
thread: a remote REPL evaluates on a slynk worker, and MP:PROCESS-RUN-FUNCTION
gives you a fresh thread. Touching a view from either is not slow or flaky, it
is undefined -- so every UI form typed at a remote REPL has to come back
through here."
  (cond
    ((null *on-main-hook*) (funcall thunk))
    (t
     ;; The hook calls its argument from inside an Objective-C block, and a
     ;; condition or a THROW unwinding through a GCD frame corrupts it. So
     ;; nothing is allowed to leave the function handed over: the outcome comes
     ;; back in a cons and is re-signalled here, on the thread that asked --
     ;; which is also where a REPL wants to see it.
     (let ((values nil)
           (condition nil))
       (funcall *on-main-hook*
                (lambda ()
                  (handler-case
                      (setf values (multiple-value-list (funcall thunk)))
                    (serious-condition (e) (setf condition e)))
                  nil))
       (if condition
           (error condition)
           (values-list values))))))

(defmacro with-main-thread (&body body)
  "Evaluate BODY on the main thread and return its value. See ON-MAIN."
  `(on-main (lambda () ,@body)))

;;; ------------------------------------------------------------------
;;; remote REPL

(defvar *remote-repl-port* nil
  "The port the slynk server is listening on, once it is up.")

(defun start-remote-repl (&key (port 4005) interface (style :spawn))
  "Start a slynk server so a SLY client can attach to this image.

Started before the entry point on purpose. An entry point that signals is
exactly when you most want a REPL, and if the server came up afterwards a
broken :ENTRY-POINT would leave you with no way in but a rebuild.

The connection is plain TCP on the loopback interface. On the simulator that
is the Mac's own loopback, so `sly-connect' to localhost just works; a device
needs a forwarder -- `iproxy 4005 4005'. Do not widen INTERFACE to 0.0.0.0
outside a network you control: this is an unauthenticated eval server."
  (let ((create (find-symbol "CREATE-SERVER" "SLYNK")))
    (cond
      ((not (and create (fboundp create)))
       (format t "~&; :REMOTE-REPL is on but SLYNK is not in the image.~%")
       (finish-output)
       nil)
      (t
       (handler-case
           (progn
             (funcall create :port port :dont-close t :style style
                            :interface interface)
             (setf *remote-repl-port* port)
             (format t "~&; slynk listening on port ~d~%" port)
             (finish-output)
             port)
         (error (e)
           (format t "~&; slynk failed to start on port ~d: ~a~%" port e)
           (finish-output)
           nil))))))

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

(defvar *boot-failure* nil
  "What the entry point signalled, as text, or NIL.

Kept so the delegate can put it on screen. An app whose entry point dies shows
a blank window and writes to a console nobody is reading -- on a phone there is
no terminal behind the app -- and the first thing you need is the condition,
not a rebuild with print statements in it.")

(defun boot-failure ()
  "The entry point's failure as a string, or \"\" if it succeeded."
  (or *boot-failure* ""))

(defun describe-boot-failure (entry-point condition)
  (format nil "~a signalled~%~%~a: ~a~%~%~a"
          entry-point (type-of condition) condition
          "The image is up; the interface is not. Fix and rebuild, or attach a
remote REPL with :REMOTE-REPL T and build it by hand."))

(defun %boot (&key entry-point manifest remote-repl (guard-callbacks t))
  "Called from ECLBoot once the image is up. Returns; the run loop follows."
  (setf *bundle-path* (symbol-value (find-symbol "*BUNDLE-PATH*" "CL-USER")))
  (when guard-callbacks
    (guard-dynamic-callbacks))
  (when manifest
    (load-bundled-sources manifest))
  (when remote-repl
    (apply #'start-remote-repl remote-repl))
  (when entry-point
    (let ((symbol (ignore-errors (read-from-string entry-point))))
      (setf *entry-point* symbol)
      (cond ((and symbol (fboundp symbol))
             (handler-case (funcall symbol)
               (serious-condition (e)
                 (setf *boot-failure* (describe-boot-failure entry-point e))
                 (format t "~&; entry point ~a signalled: ~a~%" entry-point e)
                 (finish-output))))
            (t
             (setf *boot-failure*
                   (format nil "~a is not fbound.~%~%The :ENTRY-POINT names a ~
                                function that does not exist in the built ~
                                image. Check the package and the spelling."
                           entry-point))
             (format t "~&; entry point ~a is not fbound~%" entry-point)
             (finish-output)))))
  t)

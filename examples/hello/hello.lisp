;;;; hello.lisp -- the least you can write that puts something on screen.
;;;;
;;;; Deliberately depends on nothing. examples/objc-lite is this with the
;;;; corners knocked off, and every other example uses it; here the point is
;;;; that the whole bridge fits in a screenful and needs no C compiler, no
;;;; trampoline file and no library.

(defpackage #:hello-ios
  (:use #:cl)
  (:export #:start))

(in-package #:hello-ios)

;;; ------------------------------------------------------------------
;;; talking to Objective-C
;;;
;;; objc_msgSend, sel_registerName and objc_getClass are the whole runtime as
;;; far as this file is concerned. SI:FIND-FOREIGN-SYMBOL resolves them out of
;;; the image the linker already produced -- libobjc is linked into every iOS
;;; app, so there is nothing to load.

(defvar *msg-send*
  (si:find-foreign-symbol "objc_msgSend" :default :pointer-void 0))

(defun sel (name)
  (si:call-cfun (si:find-foreign-symbol "sel_registerName" :default :pointer-void 0)
                :pointer-void '(:cstring) (list name)))

(defun cls (name)
  (si:call-cfun (si:find-foreign-symbol "objc_getClass" :default :pointer-void 0)
                :pointer-void '(:cstring) (list name)))

(defun argument-type (value)
  ;; :LONG for integers because that is what NSInteger is, and a BOOL read from
  ;; the low byte of a 64-bit register is still the right BOOL. :DOUBLE for
  ;; floats because CGFloat is a double here.
  (etypecase value
    (string :cstring)
    (integer :long)
    (float :double)
    (t :pointer-void)))

(defun send (object selector &rest arguments)
  "Send SELECTOR to OBJECT. Scalars and pointers only -- a message taking or
returning a struct by value cannot be spelled this way. See examples/abi-probe."
  (si:call-cfun *msg-send* :pointer-void
                (list* :pointer-void :pointer-void
                       (mapcar #'argument-type arguments))
                (list* object (sel selector)
                       (mapcar (lambda (a) (if (floatp a) (float a 1d0) a))
                               arguments))))

;;; ------------------------------------------------------------------
;;; a label

(defun show (text)
  "Centre TEXT in the window the app delegate already made."
  (let* ((application (send (cls "UIApplication") "sharedApplication"))
         (view (send (send (send application "keyWindow")
                           "rootViewController")
                     "view"))
         (label (send (send (cls "UILabel") "alloc") "init")))
    (send label "setText:" (send (cls "NSString") "stringWithUTF8String:" text))
    (send label "setFont:"
          (send (cls "UIFont") "monospacedSystemFontOfSize:weight:" 15d0 0d0))
    (send label "setNumberOfLines:" 0)
    (send label "setTextAlignment:" 1)     ; NSTextAlignmentCenter
    (send label "setTranslatesAutoresizingMaskIntoConstraints:" 0)
    (send view "addSubview:" label)
    ;; Two constraints and no rectangle anywhere: an anchor is an object and a
    ;; constant is a CGFloat, which is why Auto Layout is entirely reachable
    ;; from a bridge that cannot pass a CGRect.
    (dolist (anchor '("centerXAnchor" "centerYAnchor") label)
      (send (send (send label anchor) "constraintEqualToAnchor:" (send view anchor))
            "setActive:" 1))))

;;; ------------------------------------------------------------------

(defun start ()
  "Called once, on the main thread, from the app delegate. Must RETURN: the
run loop has not started yet, and blocking here means an app that never draws."
  (show (format nil "~a ~a on ~a~%~%~
                     compiled ahead of time,~%and still live: (* 6 7) = ~a~%~%~
                     from interpreted source:~%~a"
                (lisp-implementation-type) (lisp-implementation-version)
                (machine-type)
                (eval '(let ((x 6) (y 7)) (* x y)))
                ;; HELLO-SCRIPTS is shipped as source and loaded from the
                ;; bundle at boot, so this reaches a function that was never
                ;; compiled into the binary.
                (funcall (read-from-string "hello-scripts:greeting"))))
  (finish-output))

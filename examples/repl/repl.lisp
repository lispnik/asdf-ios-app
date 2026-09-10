;;;; repl.lisp -- a REPL on the phone, with no laptop attached.
;;;;
;;;; The interesting part is the delegate. UIKit tells a text field's delegate
;;;; that Return was pressed, and the delegate here is an Objective-C class
;;;; created at run time whose one method is a Lisp function.
;;;;
;;;; That needs no C compiler at build time and no trampoline file, because the
;;;; ECL compiler handles FFI:DEFCALLBACK itself and emits an ordinary C
;;;; function for it. The method's signature is what makes it possible: BOOL,
;;;; id, SEL, id -- every one a scalar or a pointer. A method that took a
;;;; CGRect could not be written this way. See examples/abi-probe.

(defpackage #:ios-repl
  (:use #:cl)
  (:local-nicknames (#:oc #:objc-lite))
  (:export #:start #:evaluate #:echo))

(in-package #:ios-repl)

(defvar *transcript* nil)
(defvar *input* nil)
(defvar *lines* '()
  "Newest first, and capped: a UITextView holding an unbounded string starts
to cost real time to lay out.")

;;; ------------------------------------------------------------------
;;; evaluating

(defun evaluate (source)
  "Read, evaluate and print SOURCE, returning a string whatever happens.

Everything printed during evaluation is captured too, so (ROOM) and friends
have somewhere to go -- there is no console behind this window."
  (let ((output (make-string-output-stream)))
    (handler-case
        (let* ((*standard-output* output)
               (values (multiple-value-list (eval (read-from-string source))))
               (printed (get-output-stream-string output)))
          (format nil "~@[~a~%~]~{~s~^~%~}"
                  (and (plusp (length printed))
                       (string-right-trim '(#\Newline) printed))
                  values))
      (error (condition)
        (format nil "; ~a: ~a" (type-of condition) condition)))))

;;; ------------------------------------------------------------------
;;; the transcript

(defun echo (text)
  (push text *lines*)
  (when (> (length *lines*) 200)
    (setf *lines* (subseq *lines* 0 200)))
  (when *transcript*
    (let ((all (format nil "~{~a~%~}" (reverse *lines*))))
      (oc:send *transcript* "setText:" (oc:nsstr all))
      ;; NSRange is two 64-bit integers, which AAPCS64 passes in x0 and x1 --
      ;; exactly where two :LONG arguments go. This is the rare struct that
      ;; needs no trampoline, and it is why the transcript can scroll.
      (oc:send *transcript* "scrollRangeToVisible:" (max 0 (1- (length all))) 1)))
  text)

(defun submit (field)
  (let ((source (oc:lisp-string (oc:send field "text"))))
    (when (plusp (length (string-trim " " source)))
      (echo (format nil "> ~a" source))
      (echo (evaluate source))
      (oc:send field "setText:" (oc:nsstr "")))))

;;; ------------------------------------------------------------------
;;; the delegate
;;;
;;; The Objective-C encoding "c@:@" reads: returns a char -- BOOL is a signed
;;; char -- taking self, _cmd and one object. Returning NO stops UIKit
;;; inserting a newline, which is what a single-line field wants.
;;;
;;; The Lisp return type is :BYTE and not :CHAR, which is the same width and
;;; not the same thing: ECL's :CHAR is a Lisp CHARACTER, so returning 0 from it
;;; fails inside CHAR-CODE. :BYTE is the 8-bit integer. Every BOOL callback
;;; wants :BYTE.

(ffi:defcallback should-return :byte
    ((self :pointer-void) (cmd :pointer-void) (field :pointer-void))
  (declare (ignore self cmd))
  ;; Nothing may be signalled out of here: this frame's caller is UIKit, and a
  ;; condition unwinding through it corrupts the frame.
  (handler-case (submit field)
    (error (condition)
      (ignore-errors (echo (format nil "; delegate: ~a" condition)))))
  0)

(defun install-delegate (field)
  (let ((class (oc:define-class "LispTextFieldDelegate" "NSObject"
                 (list (list "textFieldShouldReturn:"
                             (ffi:callback 'should-return)
                             "c@:@")))))
    ;; UIKit holds a delegate weakly and Lisp holds nothing it can see, so
    ;; without OC:RETAIN this is deallocated before the first Return.
    (let ((delegate (oc:retain (oc:send (oc:send class "alloc") "init"))))
      (oc:send field "setDelegate:" delegate)
      delegate)))

;;; ------------------------------------------------------------------
;;; buttons
;;;
;;; LispTarget ships with asdf-ios-app and covers everything in UIKit that
;;; uses target/action. It evaluates a form string, so the button's payload is
;;; just Lisp source.

(defparameter +buttons+
  '(("version" . "(lisp-implementation-version)")
    ("packages" . "(length (list-all-packages))")
    ("room" . "(room nil)")
    ("clear" . "(ios-repl::clear)")))

(defun clear ()
  (setf *lines* '())
  (when *transcript* (oc:send *transcript* "setText:" (oc:nsstr "")))
  (values))

(defun make-button (label form)
  (oc:on-tap (oc:system-button label)
             (format nil "(ios-repl::run-button ~s)" form)))

(defun run-button (source)
  (echo (format nil "> ~a" source))
  (echo (evaluate source))
  (values))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (oc:root-view))
         (safe (oc:send root "safeAreaLayoutGuide"))
         ;; iOS 15's keyboard layout guide: the keyboard as a set of anchors.
         ;; The alternative is observing UIKeyboardWillChangeFrameNotification
         ;; and reading a CGRect out of its userInfo -- a struct, by value, and
         ;; therefore out of reach without a trampoline.
         (keyboard (oc:send root "keyboardLayoutGuide"))
         (transcript (oc:new "UITextView"))
         (input (oc:new "UITextField"))
         (row (oc:new "UIStackView")))

    (oc:send root "setBackgroundColor:" (oc:system-color "systemBackground"))

    (oc:send transcript "setEditable:" 0)
    (oc:send transcript "setFont:" (oc:mono-font 12))
    (oc:send transcript "setBackgroundColor:" (oc:system-color "secondarySystemBackground"))
    (oc:send root "addSubview:" transcript)

    (oc:send row "setSpacing:" 8d0)
    (oc:send row "setDistribution:" 1)          ; UIStackViewDistributionFillEqually
    (loop for (label . form) in +buttons+
          do (oc:send row "addArrangedSubview:" (make-button label form)))
    (oc:send root "addSubview:" row)

    (oc:send input "setPlaceholder:" (oc:nsstr "(+ 1 2)"))
    (oc:send input "setBorderStyle:" 3)          ; RoundedRect
    (oc:send input "setFont:" (oc:mono-font 15))
    (oc:send input "setAutocorrectionType:" 1)   ; No
    (oc:send input "setAutocapitalizationType:" 0)
    (oc:send input "setSmartQuotesType:" 1)      ; No -- curly quotes do not read
    (oc:send input "setSmartDashesType:" 1)
    (oc:send input "setReturnKeyType:" 9)        ; Done
    (oc:send root "addSubview:" input)

    (oc:pin transcript "topAnchor" safe "topAnchor" 8)
    (oc:pin transcript "leadingAnchor" safe "leadingAnchor" 8)
    (oc:pin transcript "trailingAnchor" safe "trailingAnchor" -8)
    (oc:pin transcript "bottomAnchor" row "topAnchor" -8)

    (oc:pin row "leadingAnchor" safe "leadingAnchor" 8)
    (oc:pin row "trailingAnchor" safe "trailingAnchor" -8)
    (oc:fix row "heightAnchor" 34)
    (oc:pin row "bottomAnchor" input "topAnchor" -8)

    (oc:pin input "leadingAnchor" safe "leadingAnchor" 8)
    (oc:pin input "trailingAnchor" safe "trailingAnchor" -8)
    (oc:pin input "bottomAnchor" keyboard "topAnchor" -8)

    (setf *transcript* transcript
          *input* input)
    (install-delegate input)
    ;; Ready to type. It also makes the keyboard layout guide earn its keep
    ;; immediately: the input rises above the keyboard and the transcript
    ;; shortens, with no notification observer and no CGRect anywhere.
    (oc:send input "becomeFirstResponder")
    (values)))

(defun start ()
  "Runs on the main thread and returns; the run loop follows."
  (build-interface)
  (echo (format nil "~a ~a on ~a"
                (lisp-implementation-type) (lisp-implementation-version)
                (machine-type)))
  (echo "Type a form and press Done.")
  (echo "")
  (dolist (demo '("(+ 1 2)"
                  "(mapcar #'1+ '(1 2 3))"
                  "(format nil \"~r\" 1234)"
                  "(defclass point () ((x :initform 3)))"
                  "(class-of (make-instance 'point))"))
    (echo (format nil "> ~a" demo))
    (echo (evaluate demo)))
  (demonstrate-delegate)
  (values))

(defun demonstrate-delegate ()
  "Send the delegate its method the way UIKit will, and show the round trip.

Not a mock: this is objc_msgSend dispatching a selector on a class that did not
exist when the app was built, into a method whose body is Lisp. The only part
of the real path it leaves out is the finger."
  (let ((delegate (oc:send *input* "delegate")))
    (oc:send *input* "setText:" (oc:nsstr "(* 6 7)"))
    (echo "")
    (echo ";; objc_msgSend(delegate, @selector(textFieldShouldReturn:), field)")
    (let ((answer (oc:send-bool delegate "textFieldShouldReturn:" *input*)))
      (echo (format nil ";; -> ~:[NO~;YES~], which is what stops UIKit inserting a newline."
                    answer)))))

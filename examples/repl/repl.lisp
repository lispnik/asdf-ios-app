;;;; repl.lisp -- a REPL on the phone, with no laptop attached.
;;;;
;;;; The interesting part is the delegate. UIKit tells a text field's delegate
;;;; that Return was pressed, and the delegate here is an Objective-C class
;;;; created at run time whose one method is a Lisp function.
;;;;
;;;; That needs no C compiler at build time: the method is a libffi closure
;;;; that objc makes at run time, on the phone, and it could take a CGRect if
;;;; it wanted one.

(defpackage #:ios-repl
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
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
      (objc:invoke *transcript* "setText:" all)
      ;; An NSRange by value, as (location . length).
      (objc:invoke *transcript* "scrollRangeToVisible:" (cons (max 0 (1- (length all))) 1))))
  text)

(defun text-of (field)
  (let ((text (objc:invoke field "text")))
    (if (cffi:null-pointer-p text) "" (objc:ns-string-to-string text))))

(defun submit (field)
  (let ((source (text-of field)))
    (when (plusp (length (string-trim " " source)))
      (echo (format nil "> ~a" source))
      (echo (evaluate source))
      (objc:invoke field "setText:" ""))))

;;; ------------------------------------------------------------------
;;; the delegate
;;;
;;; An Objective-C class whose one method is Lisp. UIKit sends
;;; -textFieldShouldReturn: when Return is pressed; returning NO stops it
;;; inserting a newline, which is what a single-line field wants.

(objc:define-objc-class text-field-delegate ()
  ()
  (:objc-class-name "LispTextFieldDelegate"))

(objc:define-objc-method ("textFieldShouldReturn:" objc:objc-bool)
    ((self text-field-delegate) (field objc:objc-object-pointer))
  ;; Nothing may be signalled out of here: this frame's caller is UIKit.
  (handler-case (submit field)
    (error (condition)
      (ignore-errors (echo (format nil "; delegate: ~a" condition)))))
  nil)

(defun install-delegate (field)
  ;; UIKit holds a delegate weakly and Lisp holds nothing it can see, so
  ;; without UI:KEEP this is collected before the first Return.
  (let ((delegate (ui:keep (make-instance 'text-field-delegate))))
    (objc:invoke field "setDelegate:" (objc:objc-object-pointer delegate))
    delegate))

;;; ------------------------------------------------------------------
;;; buttons
;;;
;;; Each carries a form as its label's payload, so what a button does is
;;; readable in the transcript when it is pressed.

(defparameter +buttons+
  '(("version" . "(lisp-implementation-version)")
    ("packages" . "(length (list-all-packages))")
    ("room" . "(room nil)")
    ("clear" . "(ios-repl::clear)")))

(defun clear ()
  (setf *lines* '())
  (when *transcript* (objc:invoke *transcript* "setText:" ""))
  (values))

(defun make-button (label form)
  (ui:on-tap (ui:system-button label)
             (lambda (sender) (declare (ignore sender)) (run-button form))))

(defun run-button (source)
  (echo (format nil "> ~a" source))
  (echo (evaluate source))
  (values))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (ui:root-view))
         (safe (objc:invoke root "safeAreaLayoutGuide"))
         ;; iOS 15's keyboard layout guide: the keyboard as a set of anchors,
         ;; which is simpler than observing UIKeyboardWillChangeFrameNotification
         ;; and reading a CGRect out of its userInfo.
         (keyboard (objc:invoke root "keyboardLayoutGuide"))
         (transcript (ui:new "UITextView"))
         (input (ui:new "UITextField"))
         (row (ui:new "UIStackView")))

    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))

    (objc:invoke transcript "setEditable:" 0)
    (objc:invoke transcript "setFont:" (ui:mono-font 12))
    (objc:invoke transcript "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke root "addSubview:" transcript)

    (objc:invoke row "setSpacing:" 8d0)
    (objc:invoke row "setDistribution:" 1)          ; UIStackViewDistributionFillEqually
    (loop for (label . form) in +buttons+
          do (objc:invoke row "addArrangedSubview:" (make-button label form)))
    (objc:invoke root "addSubview:" row)

    (objc:invoke input "setPlaceholder:" "(+ 1 2)")
    (objc:invoke input "setBorderStyle:" 3)          ; RoundedRect
    (objc:invoke input "setFont:" (ui:mono-font 15))
    (objc:invoke input "setAutocorrectionType:" 1)   ; No
    (objc:invoke input "setAutocapitalizationType:" 0)
    (objc:invoke input "setSmartQuotesType:" 1)      ; No -- curly quotes do not read
    (objc:invoke input "setSmartDashesType:" 1)
    (objc:invoke input "setReturnKeyType:" 9)        ; Done
    (objc:invoke root "addSubview:" input)

    (ui:pin transcript "topAnchor" safe "topAnchor" 8)
    (ui:pin transcript "leadingAnchor" safe "leadingAnchor" 8)
    (ui:pin transcript "trailingAnchor" safe "trailingAnchor" -8)
    (ui:pin transcript "bottomAnchor" row "topAnchor" -8)

    (ui:pin row "leadingAnchor" safe "leadingAnchor" 8)
    (ui:pin row "trailingAnchor" safe "trailingAnchor" -8)
    (ui:fix row "heightAnchor" 34)
    (ui:pin row "bottomAnchor" input "topAnchor" -8)

    (ui:pin input "leadingAnchor" safe "leadingAnchor" 8)
    (ui:pin input "trailingAnchor" safe "trailingAnchor" -8)
    (ui:pin input "bottomAnchor" keyboard "topAnchor" -8)

    (setf *transcript* transcript
          *input* input)
    (install-delegate input)
    ;; Ready to type. It also makes the keyboard layout guide earn its keep
    ;; immediately: the input rises above the keyboard and the transcript
    ;; shortens, with no notification observer.
    (objc:invoke input "becomeFirstResponder")
    (values)))

(defun start ()
  "Runs on the main thread and returns; the run loop follows."
  (objc:ensure-objc-initialized)
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
                  "(class-of (make-instance 'point))"
                  ;; A variadic send: the arguments after the format go on the
                  ;; stack, and the dynamic FFI puts them there now.
                  "(objc:ns-string-to-string (objc:invoke \"NSString\" '(\"stringWithFormat:\" (objc:objc-object-pointer objc:objc-object-pointer :int) :result-type objc:objc-object-pointer :variadic-num-of-fixed 1) \"%@ and %d\" \"objc\" 42))"))
    (echo (format nil "> ~a" demo))
    (echo (evaluate demo)))
  (demonstrate-delegate)
  (values))

(defun demonstrate-delegate ()
  "Send the delegate its method the way UIKit will, and show the round trip.

Not a mock: this is objc_msgSend dispatching a selector on a class that did not
exist when the app was built, into a method whose body is Lisp. The only part
of the real path it leaves out is the finger."
  (let ((delegate (objc:invoke *input* "delegate")))
    (objc:invoke *input* "setText:" "(* 6 7)")
    (echo "")
    (echo ";; objc_msgSend(delegate, @selector(textFieldShouldReturn:), field)")
    (let ((answer (objc:invoke-bool delegate "textFieldShouldReturn:" *input*)))
      (echo (format nil ";; -> ~:[NO~;YES~], which is what stops UIKit inserting a newline."
                    answer)))))

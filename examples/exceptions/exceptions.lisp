;;;; exceptions.lisp -- three failures earned on purpose, on a phone.
;;;;
;;;; The objc library's macOS example of the same name, on iOS: an
;;;; NSException raised inside a send used to take the app down, and on a
;;;; device that is a static ECL image with libffi callbacks and no C
;;;; compiler, which is the build the mechanism was least sure of.  So this
;;;; earns the same three failures -- an array past its end, a selector
;;;; nothing implements, a file that is not there -- catches each as the
;;;; condition it becomes, prints what it carried to the kept console, and
;;;; puts it on screen.  The line that matters is the last one: the send
;;;; after the exceptions still works.

(defpackage #:exceptions
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:earn))

(in-package #:exceptions)

(defun out-of-range ()
  (handler-case (progn (objc:invoke (objc:invoke "NSArray" "array") "objectAtIndex:" 3) nil)
    (objc:objc-exception (e) e)))

(defun unrecognized-selector ()
  (handler-case (progn (objc:invoke (objc:invoke "NSString" "stringWithUTF8String:" "a string")
                                    "performSelector:" (objc:coerce-to-selector "fly"))
                       nil)
    (objc:objc-exception (e) e)))

(defun missing-file ()
  (handler-case (progn (objc:invoke-with-error "NSString" "stringWithContentsOfFile:encoding:error:"
                                               "/nonexistent/exceptions-example" 4)
                       nil)
    (objc:ns-error (e) e)))

(defun earn ()
  "Earn the three failures and return the lines that describe them."
  (let* ((range (out-of-range))
         (selector (unrecognized-selector))
         (file (missing-file))
         (lines (list (if range
                          (format nil "objectAtIndex: raised ~a: ~a"
                                  (objc:objc-exception-name range) (objc:objc-exception-reason range))
                          "objectAtIndex: raised nothing")
                      (if selector
                          (format nil "an unrecognized selector raised ~a" (objc:objc-exception-name selector))
                          "an unrecognized selector raised nothing")
                      (if file
                          (format nil "a missing file is ~a ~d: ~a"
                                  (objc:ns-error-domain file) (objc:ns-error-code file)
                                  (objc:ns-error-description file))
                          "a missing file signalled nothing")
                      (format nil "the next send works: ~a"
                              (= 8 (objc:invoke (objc:invoke "NSString" "stringWithUTF8String:" "survived")
                                                "length"))))))
    (dolist (line lines) (format t "EXCEPTIONS: ~a~%" line))
    (finish-output)
    lines))

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setNumberOfLines:" lines)
    (objc:invoke label "setFont:" (ui:font size))
    label))

(defun start ()
  (objc:ensure-objc-initialized)
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 12)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Exceptions, caught in Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "Three failures earned on purpose: an NSRangeException, an NSInvalidArgumentException and an NSError. Each used to end the app; each is a condition now." :size 13))
    (dolist (line (earn))
      (objc:invoke column "addArrangedSubview:" (label line :size 13)))
    (values)))

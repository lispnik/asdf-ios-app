;;;; opener.lisp -- URLs and documents, delivered to Lisp.
;;;;
;;;; Two declarations in opener.asd make this app a target: a URL scheme,
;;;; so that lisp://... links anywhere on the phone open it, and a document
;;;; type, so that .lisp files in Files and share sheets offer it. Either
;;;; way the delegate in OpenerDelegate.m calls OPEN-URL here, with the
;;;; document's contents already read on the Objective-C side, where the
;;;; security scope lives.
;;;;
;;;; What a link may ask for is small on purpose. lisp://eval?form=... is
;;;; evaluated under a whitelist of arithmetic, and lisp://show?text=... is
;;;; shown. A URL is untrusted input, and an app that evaluates whatever a
;;;; link says is an app that any web page can drive.

(defpackage #:opener
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:open-url #:*opened*))

(in-package #:opener)

;;; ------------------------------------------------------------------
;;; a small, safe evaluator

(defparameter +arithmetic+
  '(+ - * / expt sqrt isqrt mod rem gcd lcm floor ceiling round truncate
    abs max min list length reverse))

(defun check-form (form)
  (cond ((or (numberp form) (stringp form)) form)
        ((and (consp form) (member (car form) +arithmetic+))
         (mapc #'check-form (cdr form)) form)
        (t (error "not allowed from a URL: ~s" form))))

(defun evaluate (text)
  (handler-case
      (let* ((*read-eval* nil)
             (*package* (find-package '#:opener))
             (form (read-from-string text)))
        (check-form form)
        (princ-to-string (eval form)))
    (error (condition) (format nil "error: ~a" condition))))

;;; ------------------------------------------------------------------
;;; the URL

(defun ns (string) (objc:invoke "NSString" "stringWithString:" string))

(defun url-parts (string)
  "(VALUES SCHEME HOST QUERY-ALIST PATH) of STRING, decoded, by NSURLComponents."
  (let* ((components (objc:invoke "NSURLComponents" "componentsWithString:" string))
         (items (objc:invoke components "queryItems"))
         (query '()))
    (unless (cffi:null-pointer-p items)
      (dotimes (i (objc:invoke items "count"))
        (let ((item (objc:invoke items "objectAtIndex:" i)))
          (push (cons (objc:ns-string-to-string (objc:invoke item "name"))
                      (let ((value (objc:invoke item "value")))
                        (if (cffi:null-pointer-p value) "" (objc:ns-string-to-string value))))
                query))))
    (flet ((part (selector)
             (let ((value (objc:invoke components selector)))
               (if (cffi:null-pointer-p value) "" (objc:ns-string-to-string value)))))
      (values (part "scheme") (part "host") (nreverse query) (part "path")))))

(defvar *opened* '() "Every URL received, newest first, with what was done.")
(defvar *log* nil)
(defvar *count* nil)

(defun open-url (url contents)
  "Called by the delegate for each URL. CONTENTS is a document's text, or \"\"."
  (multiple-value-bind (scheme host query path) (url-parts url)
    (let ((outcome
            (cond ((string-equal scheme "file")
                   (format nil "document ~a: ~d characters~@[, first line ~s~]"
                           (file-namestring path) (length contents)
                           (let ((end (position #\Newline contents)))
                             (and (plusp (length contents)) (subseq contents 0 end)))))
                  ((string-equal host "eval")
                   (let ((form (or (cdr (assoc "form" query :test #'string=)) "")))
                     (format nil "~a => ~a" form (evaluate form))))
                  ((string-equal host "show")
                   (or (cdr (assoc "text" query :test #'string=)) ""))
                  (t (format nil "nothing to do for ~a" url)))))
      (push (cons url outcome) *opened*)
      (format t "OPENER: ~a~%OPENER:   ~a~%" url outcome)
      (finish-output)
      (when *log*
        (objc:invoke *log* "setText:"
                     (format nil "~{~a~%~}"
                             (loop for (u . o) in *opened*
                                   collect (format nil "~a~%   ~a~%" u o))))
        (objc:invoke *count* "setText:" (format nil "~d URL~:p received" (length *opened*))))
      outcome)))

;;; ------------------------------------------------------------------
;;; opening a link from inside
;;;
;;; The same delivery path as a link from Safari or a shortcut, minus the
;;; "Open in Opener?" confirmation the system puts in front of a link from
;;; another app -- an app opening its own scheme is not asked.  It is what
;;; the buttons do, and what OPENER_OPEN=1 does at launch, for the picture.

(defparameter +samples+
  '("lisp://eval?form=(expt%202%2064)"
    "lisp://eval?form=(*%2012345678901234567890%2098765432109876543210)"
    "lisp://show?text=hello%20from%20a%20link"))

(defun open-link (string)
  (objc:invoke (objc:invoke "UIApplication" "sharedApplication")
               "openURL:options:completionHandler:"
               (objc:invoke "NSURL" "URLWithString:" string)
               (objc:invoke "NSDictionary" "dictionary")
               nil)
  string)

;;; ------------------------------------------------------------------
;;; the interface

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font size))
    (objc:invoke label "setNumberOfLines:" lines)
    label))

(defun start ()
  (objc:ensure-objc-initialized)
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Links and documents, opened by Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "This app owns the lisp:// scheme and the .lisp document type. Open a link such as lisp://eval?form=(expt 2 64) anywhere on the phone, or a .lisp file from Files, and it lands here." :size 13))
    (setf *count* (label "no URL yet" :size 13))
    (objc:invoke column "addArrangedSubview:" *count*)
    (setf *log* (ui:new "UITextView"))
    (objc:invoke *log* "setEditable:" nil)
    (objc:invoke *log* "setFont:" (ui:mono-font 12))
    (objc:invoke *log* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *log* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *log*)
    ;; A button per sample link.
    (dolist (sample +samples+)
      (let ((button (ui:system-button (objc:ns-string-to-string
                                       (objc:invoke (ns sample) "stringByRemovingPercentEncoding")))))
        (objc:invoke button "setContentHorizontalAlignment:" 1)
        (objc:invoke (objc:invoke button "titleLabel") "setFont:" (ui:mono-font 12))
        (ui:on-tap button (let ((sample sample)) (lambda (sender) (declare (ignore sender)) (open-link sample))))
        (objc:invoke column "addArrangedSubview:" button)))
    (when (ext:getenv "OPENER_OPEN")
      ;; Once the scene is active, one link after another.
      (let ((remaining (copy-list +samples+)))
        (ui:after-every 1.5 (lambda (timer)
                              (if remaining
                                  (open-link (pop remaining))
                                  (objc:invoke timer "invalidate"))))))
    (values)))

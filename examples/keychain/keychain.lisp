;;;; keychain.lisp -- a secret kept by the system, from Lisp.
;;;;
;;;; The Security framework is C, and its API is four functions that take
;;;; a dictionary: SecItemAdd, SecItemCopyMatching, SecItemUpdate and
;;;; SecItemDelete. The dictionary's keys are exported constants,
;;;; CFStringRefs that have to be read out of the symbols by name, and the
;;;; dictionary itself is an NSMutableDictionary, since CFDictionary and
;;;; NSDictionary are the same object. The item is a generic password: a
;;;; token this app made, kept across relaunches, encrypted at rest, and
;;;; readable by nothing else on the phone.

(defpackage #:keychain
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:secret #:store-secret #:forget-secret))

(in-package #:keychain)

(defvar *status* nil)
(defvar *shown* nil)

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "KEYCHAIN: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

;;; ------------------------------------------------------------------
;;; the constants, by name

(defun constant (name)
  "The CFStringRef the Security framework exports as NAME."
  (cffi:mem-ref (cffi:foreign-symbol-pointer name) :pointer))

(defun call (name result-type argument-types arguments)
  (si:call-cfun (cffi:foreign-symbol-pointer name) result-type argument-types arguments))

(defparameter +service+ "org.asdf-ios-app.keychain")
(defparameter +account+ "lisp")

(defun query ()
  "The dictionary that names our one item: a generic password for the
service and account."
  (let ((dictionary (objc:invoke "NSMutableDictionary" "dictionary")))
    (objc:invoke dictionary "setObject:forKey:" (constant "kSecClassGenericPassword") (constant "kSecClass"))
    (objc:invoke dictionary "setObject:forKey:" +service+ (constant "kSecAttrService"))
    (objc:invoke dictionary "setObject:forKey:" +account+ (constant "kSecAttrAccount"))
    dictionary))

(defun data-of (string)
  (objc:invoke (objc:invoke "NSString" "stringWithString:" string) "dataUsingEncoding:" 4)) ; UTF-8

(defun string-of (data)
  (objc:ns-string-to-string
   (objc:invoke (objc:invoke (objc:invoke "NSString" "alloc") "initWithData:encoding:" data 4) "autorelease")))

;;; ------------------------------------------------------------------
;;; the four calls

(defconstant +err-sec-success+ 0)
(defconstant +err-sec-item-not-found+ -25300)

(defun secret ()
  "The stored secret as a string, or NIL."
  (let ((query (query)))
    (objc:invoke query "setObject:forKey:" (objc:invoke "NSNumber" "numberWithBool:" t) (constant "kSecReturnData"))
    (objc:invoke query "setObject:forKey:" (constant "kSecMatchLimitOne") (constant "kSecMatchLimit"))
    (cffi:with-foreign-object (result :pointer)
      (setf (cffi:mem-ref result :pointer) (cffi:null-pointer))
      (let ((status (call "SecItemCopyMatching" :int '(:pointer-void :pointer-void) (list query result))))
        (cond ((= status +err-sec-success+)
               (let ((data (cffi:mem-ref result :pointer)))
                 (prog1 (string-of data)
                   (objc:invoke data "release"))))
              ((= status +err-sec-item-not-found+) nil)
              (t (error "SecItemCopyMatching: ~d" status)))))))

(defun store-secret (string)
  "Add the item, or update it if it is there."
  (let ((query (query)))
    (objc:invoke query "setObject:forKey:" (data-of string) (constant "kSecValueData"))
    (objc:invoke query "setObject:forKey:" (constant "kSecAttrAccessibleAfterFirstUnlock") (constant "kSecAttrAccessible"))
    (let ((status (call "SecItemAdd" :int '(:pointer-void :pointer-void) (list query (cffi:null-pointer)))))
      (when (= status -25299)                        ; errSecDuplicateItem
        (let ((update (objc:invoke "NSMutableDictionary" "dictionary")))
          (objc:invoke update "setObject:forKey:" (data-of string) (constant "kSecValueData"))
          (setf status (call "SecItemUpdate" :int '(:pointer-void :pointer-void) (list (query) update)))))
      (unless (= status +err-sec-success+) (error "SecItemAdd/Update: ~d" status))
      string)))

(defun forget-secret ()
  (let ((status (call "SecItemDelete" :int '(:pointer-void) (list (query)))))
    (unless (member status (list +err-sec-success+ +err-sec-item-not-found+))
      (error "SecItemDelete: ~d" status))
    (= status +err-sec-success+)))

;;; ------------------------------------------------------------------
;;; a token, and a launch count kept inside it

(defun fresh-token ()
  (format nil "~36r" (random (expt 36 12) (make-random-state t))))

(defun launch ()
  "Read the item; make it on the first launch; count the launch in it."
  (let* ((stored (secret))
         (token (if stored (subseq stored 0 (position #\Space stored)) (fresh-token)))
         (launches (if stored (1+ (parse-integer stored :start (1+ (position #\Space stored)))) 1)))
    (store-secret (format nil "~a ~d" token launches))
    (objc:invoke *shown* "setText:" (format nil "token ~a~%launch ~d of this install" token launches))
    (say (if stored
             (format nil "read back from the Keychain: launch ~d" launches)
             "no item yet; made one, and stored it"))))

;;; ------------------------------------------------------------------
;;; the screen

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
         (column (ui:new "UIStackView"))
         (row (ui:new "UIStackView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 12)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "A secret kept by the system" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "SecItemAdd, SecItemCopyMatching, SecItemUpdate and SecItemDelete from Lisp: a token this app made, encrypted at rest, back after every relaunch, readable by no other app." :size 13))
    (setf *shown* (label "" :size 15 :lines 2))
    (objc:invoke *shown* "setFont:" (ui:mono-font 14))
    (objc:invoke column "addArrangedSubview:" *shown*)
    (setf *status* (label "" :size 12))
    (objc:invoke column "addArrangedSubview:" *status*)
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 16)
    (let ((again (ui:system-button "Read again"))
          (forget (ui:system-button "Forget it")))
      (ui:on-tap again (lambda (sender) (declare (ignore sender)) (launch)))
      (ui:on-tap forget (lambda (sender) (declare (ignore sender))
                          (forget-secret)
                          (objc:invoke *shown* "setText:" "")
                          (say "deleted; the next launch makes a new one")))
      (objc:invoke row "addArrangedSubview:" again)
      (objc:invoke row "addArrangedSubview:" forget))
    (objc:invoke column "addArrangedSubview:" row)
    (launch)
    (values)))

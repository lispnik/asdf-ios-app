;;;; notify.lisp -- a notification scheduled by Lisp, and received by it.
;;;;
;;;; UNUserNotificationCenter in three parts, each a different shape of
;;;; bridge traffic. Authorisation is asked for with a completion block, a
;;;; Lisp closure called with a BOOL and an error. A notification is built
;;;; from content and a trigger and handed over. And the centre's delegate
;;;; is a Lisp class: it is asked how to present a notification that
;;;; arrives while the app is in front, and answers by calling the block
;;;; UIKit passed it -- a block Cocoa made, called from Lisp -- and hears
;;;; the tap when the user opens one.
;;;;
;;;; Authorisation is provisional: no prompt, and notifications go quietly
;;;; to Notification Center, which is what a test on a simulator can live
;;;; with. A real app would ask for the full kind, and the alert.

(defpackage #:notify-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:notify-in))

(in-package #:notify-ios)

(defvar *log* nil)
(defvar *lines* '())

(defun say (format &rest arguments)
  (let ((line (apply #'format nil format arguments)))
    (format t "NOTIFY: ~a~%" line)
    (finish-output)
    (setf *lines* (append *lines* (list line)))
    (when *log* (objc:invoke *log* "setText:" (format nil "~{~a~%~}" *lines*)))))

(defun center ()
  (objc:invoke "UNUserNotificationCenter" "currentNotificationCenter"))

;;; ------------------------------------------------------------------
;;; authorisation: a block with a BOOL

(objc:define-objc-block-type authorization-reply :void (objc:objc-c++-bool objc:objc-object-pointer))

(defconstant +option-badge+ 1)
(defconstant +option-sound+ 2)
(defconstant +option-alert+ 4)
(defconstant +option-provisional+ 64)

(defun request-authorization ()
  (objc:with-objc-block (reply 'authorization-reply
                               (lambda (granted error)
                                 (ios-app-runtime:on-main
                                  (lambda ()
                                    (say "authorisation ~a~@[: ~a~]"
                                         (if granted "granted" "refused")
                                         (unless (cffi:null-pointer-p error)
                                           (objc:ns-string-to-string
                                            (objc:invoke error "localizedDescription"))))))))
    (objc:invoke (center) "requestAuthorizationWithOptions:completionHandler:"
                 (+ +option-alert+ +option-sound+ +option-badge+ +option-provisional+)
                 reply)))

;;; ------------------------------------------------------------------
;;; scheduling

(defvar *scheduled* 0)

(objc:define-objc-block-type add-reply :void (objc:objc-object-pointer))

(defun notify-in (seconds &key (title "From Lisp") body)
  "Schedule a notification SECONDS from now."
  (let ((content (objc:alloc-init-object "UNMutableNotificationContent"))
        (identifier (format nil "lisp-~d" (incf *scheduled*))))
    (objc:invoke content "setTitle:" title)
    (objc:invoke content "setBody:"
                 (or body (format nil "Scheduled ~d s ago by (notify-in ~d); the ~:r one."
                                  seconds seconds *scheduled*)))
    (objc:invoke content "setSound:" (objc:invoke "UNNotificationSound" "defaultSound"))
    (let* ((trigger (objc:invoke "UNTimeIntervalNotificationTrigger"
                                 "triggerWithTimeInterval:repeats:" (float seconds 1d0) nil))
           (request (objc:invoke "UNNotificationRequest" "requestWithIdentifier:content:trigger:"
                                 identifier content trigger)))
      (objc:with-objc-block (reply 'add-reply
                                   (lambda (error)
                                     (ios-app-runtime:on-main
                                      (lambda ()
                                        (if (cffi:null-pointer-p error)
                                            (say "scheduled ~a for ~d s from now" identifier seconds)
                                            (say "could not schedule: ~a"
                                                 (objc:ns-string-to-string
                                                  (objc:invoke error "localizedDescription"))))))))
        (objc:invoke (center) "addNotificationRequest:withCompletionHandler:" request reply)))
    identifier))

;;; ------------------------------------------------------------------
;;; the delegate: a Lisp class UIKit calls, that calls UIKit's blocks

(objc:define-objc-class notify-delegate () ()
  (:objc-class-name "LispNotifyDelegate")
  ;; Declared, not just implemented: the centre asks whether its delegate
  ;; conforms, and a class that merely has the methods is not asked to
  ;; present anything.
  (:objc-protocols "UNUserNotificationCenterDelegate"))

(defconstant +present-list+ 8)
(defconstant +present-banner+ 16)

(objc:define-objc-method ("userNotificationCenter:willPresentNotification:withCompletionHandler:" :void)
    ((self notify-delegate) (center objc:objc-object-pointer)
     (notification objc:objc-object-pointer) (handler objc:objc-object-pointer))
  (declare (ignore center))
  (let ((content (objc:invoke (objc:invoke notification "request") "content")))
    (say "presenting: ~a" (objc:ns-string-to-string (objc:invoke content "body"))))
  ;; The block UIKit handed us, called from Lisp: show it as a banner and
  ;; in the list, even though the app is in front.
  (objc:call-objc-block '(:void ((:unsigned :long-long))) handler
                        (+ +present-banner+ +present-list+)))

(objc:define-objc-method ("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:" :void)
    ((self notify-delegate) (center objc:objc-object-pointer)
     (response objc:objc-object-pointer) (handler objc:objc-object-pointer))
  (declare (ignore center))
  (say "tapped: ~a"
       (objc:ns-string-to-string (objc:invoke (objc:invoke (objc:invoke response "notification") "request") "identifier")))
  (objc:call-objc-block '(:void ()) handler))

(defvar *delegate* nil)

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
  (setf *delegate* (ui:keep (make-instance 'notify-delegate)))
  (objc:invoke (center) "setDelegate:" (objc:objc-object-pointer *delegate*))
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView"))
         (row (ui:new "UIStackView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Notifications, from Lisp and back" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "Authorisation through a block; a notification scheduled here; a delegate written in Lisp that presents it by calling UIKit's block, and hears the tap." :size 13))
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 12)
    (dolist (seconds '(3 10 30))
      (let ((button (ui:system-button (format nil "In ~d s" seconds))))
        (ui:on-tap button (let ((seconds seconds)) (lambda (sender) (declare (ignore sender)) (notify-in seconds))))
        (objc:invoke row "addArrangedSubview:" button)))
    (objc:invoke column "addArrangedSubview:" row)
    (setf *log* (ui:new "UITextView"))
    (objc:invoke *log* "setEditable:" nil)
    (objc:invoke *log* "setFont:" (ui:mono-font 12))
    (objc:invoke *log* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *log* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *log*)
    (request-authorization)
    ;; NOTIFY_AT_LAUNCH=seconds schedules one straight away, for the picture.
    (let ((at (ext:getenv "NOTIFY_AT_LAUNCH")))
      (when at (notify-in (parse-integer at))))
    (values)))

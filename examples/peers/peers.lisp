;;;; peers.lisp -- a distributed REPL between phones, with no server.
;;;;
;;;; MultipeerConnectivity finds nearby devices over Wi-Fi and Bluetooth
;;;; and connects them, with no infrastructure. Each phone here both
;;;; advertises and browses for the same service; a browser that finds a
;;;; peer invites it, an advertiser that is invited accepts by calling the
;;;; block the framework handed its delegate -- a block Cocoa made, called
;;;; from Lisp -- and then a session carries bytes both ways. The bytes are
;;;; Lisp forms: whatever one phone sends, the other evaluates and answers.
;;;; Every delegate is a Lisp class, and every callback arrives on the
;;;; framework's own queue.

(defpackage #:peers
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:send-form #:*peers*))

(in-package #:peers)

(defparameter +service+ "lisp-peers" "Up to 15 characters, letters, digits and hyphens.")

(defvar *log* nil)
(defvar *status* nil)
(defvar *field* nil)
(defvar *lines* '())
(defvar *me* nil)
(defvar *session* nil)
(defvar *advertiser* nil)
(defvar *browser* nil)
(defvar *peers* '() "Display names of the peers connected now.")

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "PEERS: ~a~%" text)
    (finish-output)
    (ios-app-runtime:on-main
     (lambda ()
       (setf *lines* (append *lines* (list text)))
       (when *log* (objc:invoke *log* "setText:" (format nil "~{~a~%~}" *lines*)))))))

(defun show-status ()
  (ios-app-runtime:on-main
   (lambda ()
     (objc:invoke *status* "setText:"
                  (format nil "I am ~a; ~d peer~:p connected~@[: ~{~a~^, ~}~]"
                          (my-name) (length *peers*) *peers*)))))

(defun my-name ()
  (or (ext:getenv "PEERS_NAME")
      (objc:ns-string-to-string (objc:invoke (objc:invoke "UIDevice" "currentDevice") "name"))))

;;; ------------------------------------------------------------------
;;; what a peer may ask: arithmetic, and a few questions about the image

(defparameter +allowed+ '(+ - * / expt sqrt mod gcd lcm max min list length
                          lisp-implementation-version machine-type list-all-packages))

(defun check-form (form)
  (cond ((or (numberp form) (stringp form)) form)
        ((and (consp form) (member (car form) +allowed+)) (mapc #'check-form (cdr form)) form)
        (t (error "not allowed from a peer: ~s" form))))

(defun evaluate (text)
  (handler-case
      (let* ((*read-eval* nil) (*package* (find-package '#:peers)) (form (read-from-string text)))
        (check-form form)
        (let ((value (eval form)))
          (if (listp value) (format nil "~d items" (length value)) (princ-to-string value))))
    (error (condition) (format nil "error: ~a" condition))))

;;; ------------------------------------------------------------------
;;; bytes in, bytes out

(defun send-text (text)
  (let ((data (objc:invoke (objc:invoke "NSString" "stringWithString:" text) "dataUsingEncoding:" 4))
        (peers (objc:invoke *session* "connectedPeers")))
    (when (plusp (objc:invoke peers "count"))
      ;; Reliable delivery, to every connected peer.
      (objc:invoke-bool *session* "sendData:toPeers:withMode:error:" data peers 0 nil))))

(defun send-form (text)
  "Ask every peer to evaluate TEXT."
  (say "→ ~a" text)
  (send-text (format nil "?~a" text)))

(defun receive (text from)
  "A ? line is a form to evaluate and answer; a = line is an answer."
  (case (char text 0)
    (#\? (let ((answer (evaluate (subseq text 1))))
           (say "~a asks ~a; I say ~a" from (subseq text 1) answer)
           (send-text (format nil "=~a" answer))))
    (#\= (say "~a says ~a" from (subseq text 1)))
    (t (say "~a sent ~s" from text))))

;;; ------------------------------------------------------------------
;;; the delegates: session, advertiser, browser

(objc:define-objc-class peer-delegate () ()
  (:objc-class-name "LispPeerDelegate")
  (:objc-protocols "MCSessionDelegate" "MCNearbyServiceAdvertiserDelegate" "MCNearbyServiceBrowserDelegate"))

(defun peer-name (peer) (objc:ns-string-to-string (objc:invoke peer "displayName")))

(objc:define-objc-method ("session:peer:didChangeState:" :void)
    ((self peer-delegate) (session objc:objc-object-pointer) (peer objc:objc-object-pointer) (state (:signed :long-long)))
  (declare (ignore session))
  (let ((name (peer-name peer)))
    (case state
      (2 (pushnew name *peers* :test #'string=)
         (say "connected to ~a" name)
         (let ((form (ext:getenv "PEERS_SEND")))
           (when form (send-form form))))
      (0 (setf *peers* (remove name *peers* :test #'string=))
         (say "~a left" name))
      (t (say "~a: connecting" name)))
    (show-status)))

(objc:define-objc-method ("session:didReceiveData:fromPeer:" :void)
    ((self peer-delegate) (session objc:objc-object-pointer) (data objc:objc-object-pointer) (peer objc:objc-object-pointer))
  (declare (ignore session))
  (receive (objc:ns-string-to-string
            (objc:invoke (objc:invoke (objc:invoke "NSString" "alloc") "initWithData:encoding:" data 4) "autorelease"))
           (peer-name peer)))

;; The three the protocol requires and this example has no use for.
(objc:define-objc-method ("session:didReceiveStream:withName:fromPeer:" :void)
    ((self peer-delegate) (session objc:objc-object-pointer) (stream objc:objc-object-pointer)
     (name objc:objc-object-pointer) (peer objc:objc-object-pointer))
  (declare (ignore session stream name peer)))
(objc:define-objc-method ("session:didStartReceivingResourceWithName:fromPeer:withProgress:" :void)
    ((self peer-delegate) (session objc:objc-object-pointer) (name objc:objc-object-pointer)
     (peer objc:objc-object-pointer) (progress objc:objc-object-pointer))
  (declare (ignore session name peer progress)))
(objc:define-objc-method ("session:didFinishReceivingResourceWithName:fromPeer:atURL:withError:" :void)
    ((self peer-delegate) (session objc:objc-object-pointer) (name objc:objc-object-pointer)
     (peer objc:objc-object-pointer) (url objc:objc-object-pointer) (error objc:objc-object-pointer))
  (declare (ignore session name peer url error)))

;; Invited: accept, by calling the block the framework passed in.
(objc:define-objc-method ("advertiser:didReceiveInvitationFromPeer:withContext:invitationHandler:" :void)
    ((self peer-delegate) (advertiser objc:objc-object-pointer) (peer objc:objc-object-pointer)
     (context objc:objc-object-pointer) (handler objc:objc-object-pointer))
  (declare (ignore advertiser context))
  (say "invited by ~a; accepting" (peer-name peer))
  (objc:call-objc-block '(:void (objc:objc-c++-bool objc:objc-object-pointer)) handler t *session*))

;; Found: invite.  Both phones do both, so one invitation wins and the
;; other is refused by the framework as already connected.
(objc:define-objc-method ("browser:foundPeer:withDiscoveryInfo:" :void)
    ((self peer-delegate) (browser objc:objc-object-pointer) (peer objc:objc-object-pointer) (info objc:objc-object-pointer))
  (declare (ignore info))
  (say "found ~a; inviting" (peer-name peer))
  (objc:invoke browser "invitePeer:toSession:withContext:timeout:" peer *session* nil 15d0))

(objc:define-objc-method ("browser:lostPeer:" :void)
    ((self peer-delegate) (browser objc:objc-object-pointer) (peer objc:objc-object-pointer))
  (declare (ignore browser))
  (say "lost sight of ~a" (peer-name peer)))

;;; ------------------------------------------------------------------
;;; starting

(defvar *delegate* nil)

(defun start-networking ()
  (setf *delegate* (ui:keep (make-instance 'peer-delegate))
        *me* (ui:keep (objc:invoke (objc:invoke (objc:invoke "MCPeerID" "alloc") "initWithDisplayName:" (my-name)) "autorelease"))
        *session* (ui:keep (objc:invoke (objc:invoke (objc:invoke "MCSession" "alloc")
                                                     "initWithPeer:securityIdentity:encryptionPreference:" *me* nil 0)
                                        "autorelease"))
        *advertiser* (ui:keep (objc:invoke (objc:invoke (objc:invoke "MCNearbyServiceAdvertiser" "alloc")
                                                        "initWithPeer:discoveryInfo:serviceType:" *me* nil +service+)
                                           "autorelease"))
        *browser* (ui:keep (objc:invoke (objc:invoke (objc:invoke "MCNearbyServiceBrowser" "alloc")
                                                     "initWithPeer:serviceType:" *me* +service+)
                                        "autorelease")))
  (let ((delegate (objc:objc-object-pointer *delegate*)))
    (objc:invoke *session* "setDelegate:" delegate)
    (objc:invoke *advertiser* "setDelegate:" delegate)
    (objc:invoke *browser* "setDelegate:" delegate))
  (objc:invoke *advertiser* "startAdvertisingPeer")
  (objc:invoke *browser* "startBrowsingForPeers")
  (say "advertising and browsing for ~a" +service+))

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
         (row (ui:new "UIStackView"))
         (button (ui:system-button "Ask peers")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Lisp images, finding each other" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "MultipeerConnectivity, no server: every phone advertises and browses, invitations are answered through the framework's own block, and connected peers evaluate each other's forms." :size 13))
    (setf *status* (label "" :size 12 :lines 2))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *log* (ui:new "UITextView"))
    (objc:invoke *log* "setEditable:" nil)
    (objc:invoke *log* "setFont:" (ui:mono-font 12))
    (objc:invoke *log* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *log* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *log*)
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 8)
    (setf *field* (ui:new "UITextField"))
    (objc:invoke *field* "setBorderStyle:" 3)
    (objc:invoke *field* "setText:" "(expt 2 100)")
    (objc:invoke *field* "setFont:" (ui:mono-font 14))
    (objc:invoke *field* "setAutocorrectionType:" 1)
    (ui:on-tap button (lambda (sender) (declare (ignore sender))
                        (send-form (objc:ns-string-to-string (objc:invoke *field* "text")))))
    (objc:invoke row "addArrangedSubview:" *field*)
    (objc:invoke row "addArrangedSubview:" button)
    (objc:invoke column "addArrangedSubview:" row)
    (start-networking)
    (show-status)
    (values)))

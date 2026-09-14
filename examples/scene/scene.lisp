;;;; scene.lisp -- the UIScene lifecycle, reported to Lisp.
;;;;
;;;; The application delegate this example ships, SceneAppDelegate.m, is the
;;;; scene-based one UIKit has asked for since iOS 13 and now warns about at
;;;; every launch of the shipped delegate. Its scene delegate makes the
;;;; window, boots the image, and calls LIFECYCLE here for each event. This
;;;; file keeps the log and shows it, and counts how long the app spent in
;;;; the background -- which is what a real app does with these events:
;;;; pause, save, and on return, refresh.

(defpackage #:scene-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:lifecycle #:*events*))

(in-package #:scene-ios)

(defvar *events* '() "Every lifecycle event, newest first, with its time.")
(defvar *log* nil "The text view.")
(defvar *summary* nil)
(defvar *background-since* nil)
(defvar *background-seconds* 0)
(defvar *foregrounds* 0)

(defun clock ()
  (multiple-value-bind (s m h) (get-decoded-time)
    (format nil "~2,'0d:~2,'0d:~2,'0d" h m s)))

(defun lifecycle (event)
  "Called from the scene delegate, on the main thread, for each event."
  (push (cons event (clock)) *events*)
  (format t "SCENE: ~a~%" event)
  (finish-output)
  (case event
    (:did-enter-background (setf *background-since* (get-universal-time)))
    (:will-enter-foreground
     (when *background-since*
       (incf *background-seconds* (- (get-universal-time) *background-since*))
       (setf *background-since* nil))
     (incf *foregrounds*)))
  (when *log*
    (objc:invoke *log* "setText:"
                 (format nil "~{~a~%~}"
                         (loop for (name . time) in (reverse *events*)
                               collect (format nil "~a  ~(~a~)" time name))))
    (objc:invoke *summary* "setText:"
                 (format nil "~d return~:p to the foreground; ~d s in the background"
                         *foregrounds* *background-seconds*)))
  event)

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font size))
    (objc:invoke label "setNumberOfLines:" lines)
    label))

(defun start ()
  "The entry point, called by the scene delegate once the window exists."
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
    (objc:invoke column "addArrangedSubview:" (label "The scene lifecycle, in Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "A scene-based delegate of the app's own, through :bundle-app-delegate and :bundle-objc-sources. Switch away and back to see the events." :size 13))
    (setf *summary* (label "" :size 13))
    (objc:invoke column "addArrangedSubview:" *summary*)
    (setf *log* (ui:new "UITextView"))
    (objc:invoke *log* "setEditable:" nil)
    (objc:invoke *log* "setFont:" (ui:mono-font 13))
    (objc:invoke *log* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *log* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *log*)
    ;; The events that arrived before the log existed.
    (lifecycle :interface-built)
    (values)))

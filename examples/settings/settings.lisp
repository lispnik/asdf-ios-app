;;;; settings.lisp -- Swift edits Lisp's variables.
;;;;
;;;; The other Swift examples let Lisp build the interface and Swift report
;;;; back. Here the traffic runs the other way: a SwiftUI Form of sliders,
;;;; toggles and pickers edits three variables in this file, and every
;;;; change arrives through one block made from a lambda, which redraws
;;;; the pattern underneath. The pattern is plain UIKit, laid out by Lisp
;;;; from those variables: how many marks, what hue, and whether they are
;;;; circles or squares.

(defpackage #:settings-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:show-settings #:setting-changed #:*count* #:*hue* #:*shape*))

(in-package #:settings-ios)

;;; ------------------------------------------------------------------
;;; the state, and what it draws

(defvar *count* 12)
(defvar *hue* 210 "Degrees around the colour wheel.")
(defvar *shape* "circle")
(defvar *ring* t "Ring or grid.")

(defvar *canvas* nil)
(defvar *caption* nil)
(defvar *marks* '())

(defun redraw ()
  "Lay out *COUNT* marks on the canvas from the variables. Main thread."
  (dolist (mark *marks*) (objc:invoke mark "removeFromSuperview"))
  (setf *marks* '())
  (let* ((bounds (objc:invoke *canvas* "bounds"))
         (width (aref bounds 2))
         (height (aref bounds 3))
         (size (max 12 (min 44 (/ (* 3 (min width height)) (max 6 *count*))))))
    (dotimes (i *count*)
      (let* ((mark (ui:new "UIView"))
             (hue (/ (mod (+ *hue* (* i (/ 120 (max 1 *count*)))) 360) 360d0))
             (angle (* 2 pi (/ i (max 1 *count*))))
             (x (if *ring*
                    (+ (/ width 2) (* (- (/ (min width height) 2) size) (cos angle)) (- (/ size 2)))
                    (+ 8 (* (mod i 6) (/ (- width 16) 6)))))
             (y (if *ring*
                    (+ (/ height 2) (* (- (/ (min width height) 2) size) (sin angle)) (- (/ size 2)))
                    (+ 8 (* (floor i 6) (+ size 10))))))
        (objc:invoke mark "setTranslatesAutoresizingMaskIntoConstraints:" t)
        (objc:invoke mark "setFrame:" (vector (float x 1d0) (float y 1d0) (float size 1d0) (float size 1d0)))
        (objc:invoke mark "setBackgroundColor:"
                     (objc:invoke "UIColor" "colorWithHue:saturation:brightness:alpha:" hue 0.7 0.95 1.0))
        (objc:invoke (objc:invoke mark "layer") "setCornerRadius:"
                     (if (string= *shape* "circle") (/ size 2) 4))
        (objc:invoke *canvas* "addSubview:" mark)
        (push mark *marks*))))
  (objc:invoke *caption* "setText:"
               (format nil "~d ~a~:p, hue ~d°, ~a" *count* *shape* *hue* (if *ring* "in a ring" "in a grid")))
  (values))

;;; ------------------------------------------------------------------
;;; the sheet

(objc:define-objc-block-type setting-changed :void (objc:objc-object-pointer objc:objc-object-pointer))

(defvar *changed-block* nil "Kept: the sheet holds it.")

(defun setting-changed (name value)
  "Called from SwiftUI, on the main thread, for every control change."
  (format t "SETTINGS: ~a = ~a~%" name value)
  (finish-output)
  (cond ((string= name "count") (setf *count* (parse-integer value)))
        ((string= name "hue") (setf *hue* (parse-integer value)))
        ((string= name "shape") (setf *shape* value))
        ((string= name "ring") (setf *ring* (string= value "on"))))
  (redraw))

(defun specs ()
  "The settings, as the strings LispSettings.swift reads: kind, name, and
the current value from this file's variables."
  (vector (format nil "slider:count:1:36:~d" *count*)
          (format nil "slider:hue:0:359:~d" *hue*)
          (format nil "picker:shape:~a:circle|square" *shape*)
          (format nil "toggle:ring:~a" (if *ring* "on" "off"))))

(defun show-settings ()
  "Present the SwiftUI sheet over the pattern, half height."
  (unless *changed-block*
    (setf *changed-block*
          (objc:make-objc-block 'setting-changed
                                (lambda (name value)
                                  (setting-changed (objc:ns-string-to-string name)
                                                   (objc:ns-string-to-string value))))))
  (let ((sheet (objc:invoke "LispSettings" "settingsControllerWithTitle:specs:changed:"
                            "Pattern" (specs) *changed-block*)))
    ;; A medium detent: the pattern stays visible while it is edited.
    (let ((presentation (objc:invoke sheet "sheetPresentationController")))
      (unless (cffi:null-pointer-p presentation)
        (objc:invoke presentation "setDetents:"
                     (vector (objc:invoke "UISheetPresentationControllerDetent" "mediumDetent")))))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" sheet t nil)
    sheet))

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
         (button (ui:system-button "Settings…")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Swift edits Lisp's variables" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "The sheet is a SwiftUI Form; the values it edits are three Lisp variables, and every change redraws this pattern." :size 13))
    (setf *canvas* (ui:new "UIView"))
    (objc:invoke *canvas* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *canvas* "layer") "setCornerRadius:" 12)
    (objc:invoke column "addArrangedSubview:" *canvas*)
    (ui:fix *canvas* "heightAnchor" 340)
    (ui:pin *canvas* "widthAnchor" column "widthAnchor")
    (setf *caption* (label "" :size 13))
    (objc:invoke column "addArrangedSubview:" *caption*)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (show-settings)))
    (objc:invoke column "addArrangedSubview:" button)
    ;; Lay out once the canvas has its size: after this returns and the
    ;; first layout pass has run.
    (ui:after-every 0.3 (lambda (timer) (objc:invoke timer "invalidate") (redraw)
                          ;; SETTINGS_SHEET=1 opens the sheet at once, for the picture.
                          (when (ext:getenv "SETTINGS_SHEET") (show-settings)))
                    :repeats nil)
    (values)))

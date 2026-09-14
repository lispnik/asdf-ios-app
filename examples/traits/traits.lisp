;;;; traits.lisp -- what the system tells an app about its surroundings.
;;;;
;;;; The trait collection carries dark mode, the user's text size, the size
;;;; class and the display scale, and UIKit tells a view when they change.
;;;; Since iOS 17 that is a block: registerForTraitChanges:withHandler:, no
;;;; subclass needed. The block is a Lisp closure, and everything it lays
;;;; out follows from the traits: the palette, the type size, the columns.
;;;; The simulator flips them from the command line, which is how the two
;;;; pictures were taken.

(defpackage #:traits
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:relayout #:describe-traits))

(in-package #:traits)

(defvar *canvas* nil)
(defvar *report* nil)
(defvar *swatches* '())
(defvar *changes* 0)

(defun traits ()
  (objc:invoke (ui:root-view) "traitCollection"))

(defparameter +content-sizes+
  '(("UICTContentSizeCategoryXS" . 0.8) ("UICTContentSizeCategoryS" . 0.9) ("UICTContentSizeCategoryM" . 1.0)
    ("UICTContentSizeCategoryL" . 1.0) ("UICTContentSizeCategoryXL" . 1.15) ("UICTContentSizeCategoryXXL" . 1.3)
    ("UICTContentSizeCategoryXXXL" . 1.5) ("UICTContentSizeCategoryAccessibilityM" . 1.8)
    ("UICTContentSizeCategoryAccessibilityL" . 2.1) ("UICTContentSizeCategoryAccessibilityXL" . 2.4)
    ("UICTContentSizeCategoryAccessibilityXXL" . 2.7) ("UICTContentSizeCategoryAccessibilityXXXL" . 3.0)))

(defun describe-traits ()
  "(:dark BOOL :size-category NAME :factor N :compact BOOL :scale N)"
  (let* ((t* (traits))
         (style (objc:invoke t* "userInterfaceStyle"))       ; 1 light, 2 dark
         (category (objc:ns-string-to-string (objc:invoke t* "preferredContentSizeCategory")))
         (horizontal (objc:invoke t* "horizontalSizeClass"))  ; 1 compact, 2 regular
         (scale (objc:invoke t* "displayScale")))
    (list :dark (= style 2)
          :size-category (string-left-trim "UICTContentSizeCategory" category)
          :factor (or (cdr (assoc category +content-sizes+ :test #'string=)) 1.0)
          :compact (= horizontal 1)
          :scale scale)))

(defun relayout ()
  "Lay the screen out from the traits, as read now."
  (destructuring-bind (&key dark size-category factor compact scale) (describe-traits)
    (objc:invoke *report* "setText:"
                 (format nil "~a · text ~a (×~,2f) · ~a width · ~ax · ~d change~:p"
                         (if dark "dark" "light") size-category factor
                         (if compact "compact" "regular") (round scale) *changes*))
    (objc:invoke *report* "setFont:" (ui:font (* 13 factor)))
    (dolist (view *swatches*) (objc:invoke view "removeFromSuperview"))
    (setf *swatches* '())
    ;; Fewer, larger tiles when the type is large; a palette per appearance.
    (let* ((bounds (objc:invoke *canvas* "bounds"))
           (width (aref bounds 2))
           (columns (max 2 (round (/ 5 (max 1 factor)))))
           (side (/ (- width (* 8 (1- columns))) columns))
           (palette (if dark
                        '((0.95 0.55 0.25) (0.35 0.75 0.95) (0.65 0.85 0.45) (0.95 0.45 0.65) (0.75 0.65 0.95))
                        '((0.85 0.35 0.10) (0.10 0.45 0.75) (0.25 0.60 0.20) (0.80 0.15 0.45) (0.45 0.30 0.80)))))
      (dotimes (i (* columns 2))
        (let ((tile (ui:new "UIView"))
              (label (ui:new "UILabel")))
          (objc:invoke tile "setTranslatesAutoresizingMaskIntoConstraints:" t)
          (objc:invoke tile "setFrame:" (vector (float (* (mod i columns) (+ side 8)) 1d0)
                                                (float (* (floor i columns) (+ side 8)) 1d0)
                                                (float side 1d0) (float side 1d0)))
          (objc:invoke tile "setBackgroundColor:" (apply #'ui:color (nth (mod i (length palette)) palette)))
          (objc:invoke (objc:invoke tile "layer") "setCornerRadius:" 10)
          (objc:invoke label "setTranslatesAutoresizingMaskIntoConstraints:" t)
          (objc:invoke label "setFrame:" (vector 0d0 0d0 (float side 1d0) (float side 1d0)))
          (objc:invoke label "setTextAlignment:" 1)
          (objc:invoke label "setFont:" (ui:font (* 15 factor) 0.4))
          (objc:invoke label "setTextColor:" (ui:color 1 1 1))
          (objc:invoke label "setText:" (format nil "~d" (1+ i)))
          (objc:invoke tile "addSubview:" label)
          (objc:invoke *canvas* "addSubview:" tile)
          (push tile *swatches*))))
    (format t "TRAITS: ~a~%" (objc:ns-string-to-string (objc:invoke *report* "text")))
    (finish-output)))

;;; ------------------------------------------------------------------
;;; the change handler: a block, registered once

(objc:define-objc-block-type trait-change :void (objc:objc-object-pointer objc:objc-object-pointer))

(defvar *handler* nil "Kept: UIKit holds it for the view's life.")

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
    (objc:invoke column "addArrangedSubview:" (label "Traits, answered from Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "Dark mode, the text size, the size class and the scale, read here; a block registered for their changes re-lays the tiles." :size 13))
    (setf *report* (label "" :size 13 :lines 2))
    (objc:invoke column "addArrangedSubview:" *report*)
    (setf *canvas* (ui:new "UIView"))
    (objc:invoke column "addArrangedSubview:" *canvas*)
    (ui:fix *canvas* "heightAnchor" 360)
    (ui:pin *canvas* "widthAnchor" column "widthAnchor")
    ;; The traits the system may change under us, and what to do then.
    (setf *handler* (objc:make-objc-block 'trait-change
                                          (lambda (environment previous)
                                            (declare (ignore environment previous))
                                            (incf *changes*)
                                            (relayout))))
    (objc:invoke root "registerForTraitChanges:withHandler:"
                 (vector (objc:invoke "UITraitUserInterfaceStyle" "class")
                         (objc:invoke "UITraitPreferredContentSizeCategory" "class")
                         (objc:invoke "UITraitHorizontalSizeClass" "class"))
                 *handler*)
    ;; After the first layout pass, so the canvas has its width.
    (ui:after-every 0.3 (lambda (timer) (objc:invoke timer "invalidate") (relayout)) :repeats nil)
    (values)))

;;;; surface.lisp -- a 3D surface, where the surface is a Lisp function.
;;;;
;;;; Chart3D, new in iOS 26's Swift Charts, draws z = f(x, y) as a lit,
;;;; rotatable surface and asks for nothing but f. Here f is a Lisp lambda:
;;;; OBJC:MAKE-OBJC-BLOCK turns it into a block, Swift stores the block as
;;;; a closure, and Chart3D calls it for every vertex of the mesh -- a few
;;;; thousand round trips from SwiftUI into this image for each surface,
;;;; on whatever thread SwiftUI samples on.
;;;;
;;;; So the buttons below are not choosing between surfaces the Swift side
;;;; knows. They are handing it a different lambda.

(defpackage #:surface-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:show #:*surfaces*))

(in-package #:surface-ios)

;;; ------------------------------------------------------------------
;;; the surfaces
;;;
;;; Each takes the two floor coordinates, both over [-2, 2], and returns the
;;; height, which should stay within about [-1.5, 1.5]: the chart's fixed
;;; vertical scale. Ordinary Lisp, and the part worth editing.

(defun radius (x y) (sqrt (+ (* x x) (* y y))))

(defparameter *surfaces*
  (list
   (cons "ripple" (lambda (x y)
                    (let ((r (radius x y)))
                      (/ (sin (* 3 r)) (+ 1 r)))))
   (cons "saddle" (lambda (x y)
                    (/ (- (* x x) (* y y)) 2.7)))
   (cons "peaks" (lambda (x y)
                   ;; MATLAB's peaks, scaled down.
                   (* 0.18
                      (- (* 3 (expt (- 1 x) 2) (exp (- (- (* x x)) (expt (+ y 1) 2))))
                         (* 10 (- (/ x 5) (expt x 3) (expt y 5)) (exp (- (- (* x x)) (* y y))))
                         (* 1/3 (exp (- (- (expt (+ x 1) 2)) (* y y))))))))
   (cons "waves" (lambda (x y)
                   (* 0.9 (sin (* 2 x)) (cos (* 2 y)))))
   (cons "monkey" (lambda (x y)
                    ;; The monkey saddle: a saddle with a third dip.
                    (/ (- (expt x 3) (* 3 x y y)) 5.5)))))

;;; ------------------------------------------------------------------
;;; handing one to Swift

(objc:define-objc-block-type surface-function :double (:double :double))

(defvar *blocks* '()
  "Every block ever handed over, kept. Chart3D may still be sampling the
last one while the next is being shown; a few hundred bytes a switch.")

(defvar *slot* nil "The view the chart lives in.")
(defvar *controller* nil "The hosting controller on screen now.")
(defvar *caption* nil)
(defvar *current* nil)

(defun show (name)
  "Show the surface called NAME."
  (let ((function (cdr (assoc name *surfaces* :test #'string-equal))))
    (unless function
      (error "no surface called ~a; there are ~{~a~^, ~}" name (mapcar #'car *surfaces*)))
    (when *controller*
      (objc:invoke *controller* "willMoveToParentViewController:" nil)
      (objc:invoke (objc:invoke *controller* "view") "removeFromSuperview")
      (objc:invoke *controller* "removeFromParentViewController")
      (ui:unkeep *controller*)
      (setf *controller* nil))
    (let* ((block (objc:make-objc-block
                   'surface-function
                   (lambda (x y) (float (funcall function x y) 1d0))))
           (root (ui:root-controller))
           (controller (ui:keep (objc:invoke "LispSurface" "surfaceControllerWithTitle:function:"
                                             (format nil "~a: a Lisp lambda of two variables" name)
                                             block)))
           (view (objc:invoke controller "view")))
      (push block *blocks*)
      (objc:invoke root "addChildViewController:" controller)
      (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
      (objc:invoke *slot* "addSubview:" view)
      (ui:pin view "topAnchor" *slot* "topAnchor")
      (ui:pin view "bottomAnchor" *slot* "bottomAnchor")
      (ui:pin view "leadingAnchor" *slot* "leadingAnchor")
      (ui:pin view "trailingAnchor" *slot* "trailingAnchor")
      (objc:invoke controller "didMoveToParentViewController:" root)
      (setf *controller* controller
            *current* name)
      (format t "SURFACE: showing ~a~%" name)
      (finish-output)
      name)))

(defun evaluations ()
  (objc:invoke "LispSurface" "evaluations"))

(defun update-caption ()
  (objc:invoke *caption* "setText:"
               (format nil "~a: Chart3D has called into Lisp ~:d times" *current* (evaluations))))

;;; ------------------------------------------------------------------
;;; the interface

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font size))
    (objc:invoke label "setNumberOfLines:" lines)
    label))

(defun start ()
  "The entry point: build the screen and show the first surface. Must
return; the run loop follows."
  (objc:ensure-objc-initialized)
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
    (objc:invoke column "addArrangedSubview:" (label "A surface that is a Lisp function" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "Chart3D samples the height by calling a block made from a lambda. Drag to turn it." :size 13))
    (setf *slot* (ui:new "UIView"))
    (objc:invoke column "addArrangedSubview:" *slot*)
    (ui:fix *slot* "heightAnchor" 440)
    (ui:pin *slot* "widthAnchor" column "widthAnchor")
    (setf *caption* (label "" :size 12))
    (objc:invoke column "addArrangedSubview:" *caption*)
    ;; One button per surface, in a row that wraps its titles.
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 6)
    (objc:invoke row "setDistribution:" 1)             ; fill equally
    (dolist (entry *surfaces*)
      (let ((button (ui:system-button (car entry))))
        (objc:invoke (objc:invoke button "titleLabel") "setFont:" (ui:font 14))
        (ui:on-tap button (let ((name (car entry)))
                            (lambda (sender) (declare (ignore sender)) (show name) (update-caption))))
        (objc:invoke row "addArrangedSubview:" button)))
    (objc:invoke column "addArrangedSubview:" row)
    (ui:pin row "widthAnchor" column "widthAnchor")
    ;; The caption follows the sampling as it happens.
    (ui:after-every 0.5 (lambda (timer) (declare (ignore timer)) (update-caption)))
    ;; SURFACE_SHOW names the first surface, for a screenshot; ripple otherwise.
    (show (or (ext:getenv "SURFACE_SHOW") "ripple"))
    (values)))

;;;; layers.lisp -- Core Animation, with the path computed in Lisp.
;;;;
;;;; Core Animation is the layer underneath UIKit: everything on an iOS screen
;;;; is a CALayer, and animating one is a matter of describing the change
;;;; rather than driving a loop. This draws a rose curve by handing a CGPath to
;;;; a CAShapeLayer, animates its strokeEnd so the curve draws itself, and runs
;;;; a dot along the same path with a keyframe animation.
;;;;
;;;; Core Graphics' path functions are plain C, called through the dynamic
;;;; FFI; the layers are Objective-C, through objc. Nothing here is compiled
;;;; by a C compiler.

(defpackage #:layers
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:restart-animations))

(in-package #:layers)

(defparameter +side+ 320 "The canvas is constrained to this, so its size is
known without asking.")

(defvar *canvas* nil)
(defvar *shape* nil)
(defvar *dot* nil)
(defvar *path* nil)

;;; ------------------------------------------------------------------
;;; Core Graphics paths

(defvar *functions* (make-hash-table :test #'equal))

(defun foreign (name)
  "The C function NAME, looked up once and remembered.

Looked up *lazily*, which matters: a DEFVAR whose initialiser resolves a
CoreGraphics symbol runs at load time -- including during the child's native
pass on the Mac, where the app's frameworks are not linked -- and fails the
build before it reaches the phone."
  (or (gethash name *functions*)
      (setf (gethash name *functions*) (cffi:foreign-symbol-pointer name))))

(defun make-path (points &key close)
  "A CGPath through POINTS, a list of (X . Y).

The second argument to each of these is `const CGAffineTransform *': a null
pointer means the identity transform."
  (let ((path (si:call-cfun (foreign "CGPathCreateMutable") :pointer-void '() '()))
        (identity (cffi:null-pointer)))
    (loop for (x . y) in points
          for first = t then nil
          do (si:call-cfun (foreign (if first "CGPathMoveToPoint" "CGPathAddLineToPoint"))
                           :void
                           '(:pointer-void :pointer-void :double :double)
                           (list path identity (float x 1d0) (float y 1d0))))
    (when close
      (si:call-cfun (foreign "CGPathCloseSubpath") :void '(:pointer-void) (list path)))
    path))

(defun rose (&key (petals 5/2) (samples 1600) (radius 148))
  "A rose curve, r = cos(k*theta), as points in the canvas.

Five halves gives a ten-petalled figure that closes after four turns, which is
long enough for the drawing animation to be worth watching."
  (let ((centre (/ +side+ 2d0)))
    (loop for i to samples
          for theta = (* 4 pi (/ i (float samples 1d0)))
          for r = (* radius (cos (* petals theta)))
          collect (cons (+ centre (* r (cos theta)))
                        (+ centre (* r (sin theta)))))))

;;; ------------------------------------------------------------------
;;; layers

(defun make-gradient ()
  (let ((layer (objc:invoke "CAGradientLayer" "layer"))
        (colors (objc:invoke "NSMutableArray" "array")))
    ;; An NSArray of CGColorRef. CGColorRef is not an NSObject, but it is a
    ;; CFType and NSArray holds those perfectly well.
    (dolist (color (list (ui:color 0.06 0.05 0.12)
                         (ui:color 0.10 0.06 0.24)
                         (ui:color 0.03 0.09 0.20)))
      (objc:invoke colors "addObject:" (objc:invoke color "CGColor")))
    (objc:invoke layer "setColors:" colors)
    ;; CGPoints and a CGRect, by value.
    (objc:invoke layer "setStartPoint:" #(0 0))
    (objc:invoke layer "setEndPoint:" #(1 1))
    (objc:invoke layer "setFrame:" (vector 0 0 +side+ +side+))
    (objc:invoke layer "setCornerRadius:" 22)
    layer))

(defun make-shape (path)
  (let ((layer (objc:invoke "CAShapeLayer" "layer")))
    (objc:invoke layer "setFrame:" (vector 0 0 +side+ +side+))
    (objc:invoke layer "setPath:" path)
    (objc:invoke layer "setStrokeColor:"
                 (objc:invoke (ui:color 0.45 0.92 0.85) "CGColor"))
    (objc:invoke layer "setFillColor:" nil)      ; nil is a null CGColorRef
    (objc:invoke layer "setLineWidth:" 1.6)
    (objc:invoke layer "setLineJoin:" "round")
    layer))

(defun make-dot ()
  (let ((layer (objc:invoke "CALayer" "layer")))
    (objc:invoke layer "setFrame:" #(0 0 13 13))
    (objc:invoke layer "setCornerRadius:" 6.5)
    (objc:invoke layer "setBackgroundColor:"
                 (objc:invoke (ui:color 1.0 0.85 0.35) "CGColor"))
    (objc:invoke layer "setShadowColor:"
                 (objc:invoke (ui:color 1.0 0.85 0.35) "CGColor"))
    (objc:invoke layer "setShadowRadius:" 8)
    (objc:invoke layer "setShadowOpacity:" 0.9)
    (objc:invoke layer "setShadowOffset:" #(0 0))
    layer))

;;; ------------------------------------------------------------------
;;; animations
;;;
;;; repeatCount is a C `float' rather than a CGFloat. INVOKE reads the
;;; method's signature and sends a single where a single is expected, so it is
;;; nothing special here.

(defun number-of (value)
  (objc:invoke "NSNumber" "numberWithDouble:" value))

(defun repeat-forever (animation)
  (objc:invoke animation "setRepeatCount:" 1e9)
  animation)

(defun stroke-animation (duration)
  (let ((animation (objc:invoke "CABasicAnimation" "animationWithKeyPath:" "strokeEnd")))
    (objc:invoke animation "setFromValue:" (number-of 0))
    (objc:invoke animation "setToValue:" (number-of 1))
    (objc:invoke animation "setDuration:" duration)
    ;; Linear, and that is what makes the two animations agree. strokeEnd is a
    ;; fraction of the path's LENGTH, and the dot's calculationMode is "paced",
    ;; which also advances by arc length -- so with the same duration and no
    ;; easing the dot sits exactly on the tip of the line as it is drawn. Any
    ;; easing here and the two drift apart immediately.
    (objc:invoke animation "setTimingFunction:"
                 (objc:invoke "CAMediaTimingFunction" "functionWithName:" "linear"))
    (repeat-forever animation)))

(defun travel-animation (path duration)
  "A keyframe animation that moves a layer along PATH.

CAKeyframeAnimation takes the CGPath directly, which is the whole trick: the
same path Lisp computed both draws the figure and drives the dot around it."
  (let ((animation (objc:invoke "CAKeyframeAnimation" "animationWithKeyPath:" "position")))
    (objc:invoke animation "setPath:" path)
    (objc:invoke animation "setDuration:" duration)
    (objc:invoke animation "setCalculationMode:" "paced")
    (objc:invoke animation "setRotationMode:" nil)
    (repeat-forever animation)))

(defun restart-animations ()
  (objc:invoke *shape* "removeAllAnimations")
  (objc:invoke *dot* "removeAllAnimations")
  (objc:invoke *shape* "addAnimation:forKey:" (stroke-animation 6) "draw")
  (objc:invoke *dot* "addAnimation:forKey:" (travel-animation *path* 6) "travel")
  (values))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (ui:root-view))
         (safe (objc:invoke root "safeAreaLayoutGuide"))
         (title (ui:new "UILabel"))
         (canvas (ui:new "UIView"))
         (row (ui:new "UIStackView")))

    (objc:invoke root "setBackgroundColor:" (ui:color 0.04 0.04 0.06))

    (objc:invoke title "setText:" "r = cos 5θ/2")
    (objc:invoke title "setTextColor:" (ui:color 0.55 0.95 0.9))
    (objc:invoke title "setFont:" (ui:mono-font 17))
    (objc:invoke root "addSubview:" title)

    ;; Constrained to a known size.
    (objc:invoke root "addSubview:" canvas)
    (ui:fix canvas "widthAnchor" +side+)
    (ui:fix canvas "heightAnchor" +side+)

    (objc:invoke row "setSpacing:" 8d0)
    (objc:invoke row "setDistribution:" 1)
    (flet ((button (label function)
             (ui:on-tap (ui:system-button label)
                        (lambda (sender) (declare (ignore sender)) (funcall function)))))
      (objc:invoke row "addArrangedSubview:" (button "again" #'restart-animations))
      (objc:invoke row "addArrangedSubview:" (button "3 petals" (lambda () (reshape 3/2))))
      (objc:invoke row "addArrangedSubview:" (button "10 petals" (lambda () (reshape 5/2)))))
    (objc:invoke root "addSubview:" row)

    (ui:pin title "topAnchor" safe "topAnchor" 14)
    (ui:pin title "centerXAnchor" safe "centerXAnchor")
    (ui:pin canvas "centerXAnchor" safe "centerXAnchor")
    (ui:pin canvas "centerYAnchor" safe "centerYAnchor")
    (ui:pin row "leadingAnchor" safe "leadingAnchor" 12)
    (ui:pin row "trailingAnchor" safe "trailingAnchor" -12)
    (ui:pin row "bottomAnchor" safe "bottomAnchor" -10)
    (ui:fix row "heightAnchor" 34)

    (setf *canvas* canvas)
    (values)))

(defun reshape (petals)
  "Rebuild the path, and with it both animations."
  (setf *path* (make-path (rose :petals petals)))
  (objc:invoke *shape* "setPath:" *path*)
  (restart-animations)
  (values))

(defun start ()
  (objc:ensure-objc-initialized)
  (build-interface)
  (setf *path* (make-path (rose)))
  (setf *shape* (make-shape *path*))
  (setf *dot* (make-dot))
  (let ((host (objc:invoke *canvas* "layer")))
    (objc:invoke host "addSublayer:" (make-gradient))
    (objc:invoke host "addSublayer:" *shape*)
    (objc:invoke host "addSublayer:" *dot*))
  (restart-animations)
  (values))

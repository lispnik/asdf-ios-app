;;;; layers.lisp -- Core Animation, with the path computed in Lisp.
;;;;
;;;; Core Animation is the layer underneath UIKit: everything on an iOS screen
;;;; is a CALayer, and animating one is a matter of describing the change
;;;; rather than driving a loop. This draws a rose curve by handing a CGPath to
;;;; a CAShapeLayer, animates its strokeEnd so the curve draws itself, and runs
;;;; a dot along the same path with a keyframe animation.
;;;;
;;;; It needs no trampoline, which is worth a moment. Core Graphics' path
;;;; functions look like they should be a problem and are not:
;;;;
;;;;   CGPathAddLineToPoint(path, transform, x, y)
;;;;
;;;; the CGAffineTransform is a POINTER to a struct, and x and y are CGFloats.
;;;; A pointer to an aggregate has never been the difficulty; passing one BY
;;;; VALUE is. So the whole of Core Graphics' path API is reachable from a
;;;; bridge with no C in it.

(defpackage #:layers
  (:use #:cl)
  (:local-nicknames (#:oc #:objc-lite))
  (:export #:start #:restart-animations))

(in-package #:layers)

(defparameter +side+ 320 "The canvas is constrained to this, so its size is
known without asking -- and asking would mean reading a CGRect.")

(defvar *canvas* nil)
(defvar *shape* nil)
(defvar *dot* nil)
(defvar *path* nil)

;;; ------------------------------------------------------------------
;;; Core Graphics paths

;;; Through OC:FOREIGN, which defers the lookup until the function is called.
;;; Resolving a CoreGraphics symbol at load time fails the build on the Mac,
;;; where the app's frameworks are not linked -- see OBJC-LITE:FOREIGN.

(defun make-path (points &key close)
  "A CGPath through POINTS, a list of (X . Y).

The second argument to each of these is `const CGAffineTransform *' -- a
pointer, and therefore fine. NIL becomes a null pointer, which means the
identity transform."
  (let ((path (si:call-cfun (oc:foreign "CGPathCreateMutable") :pointer-void '() '())))
    (loop for (x . y) in points
          for first = t then nil
          do (si:call-cfun (oc:foreign (if first "CGPathMoveToPoint" "CGPathAddLineToPoint"))
                           :void
                           '(:pointer-void :pointer-void :double :double)
                           (list path oc:*null* (float x 1d0) (float y 1d0))))
    (when close
      (si:call-cfun (oc:foreign "CGPathCloseSubpath") :void '(:pointer-void) (list path)))
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
  (let ((layer (oc:send (oc:cls "CAGradientLayer") "layer"))
        (colors (oc:send (oc:cls "NSMutableArray") "array")))
    ;; An NSArray of CGColorRef. CGColorRef is not an NSObject, but it is a
    ;; CFType and NSArray holds those perfectly well.
    (dolist (color (list (oc:color 0.06 0.05 0.12)
                         (oc:color 0.10 0.06 0.24)
                         (oc:color 0.03 0.09 0.20)))
      (oc:send colors "addObject:" (oc:send color "CGColor")))
    (oc:send layer "setColors:" colors)
    ;; CGPoint arguments, as two doubles each. A CGPoint is an HFA of two
    ;; doubles: v0 and v1, which is where two separate doubles go.
    (oc:send layer "setStartPoint:" 0d0 0d0)
    (oc:send layer "setEndPoint:" 1d0 1d0)
    (oc:send layer "setFrame:" 0d0 0d0 (float +side+ 1d0) (float +side+ 1d0))
    (oc:send layer "setCornerRadius:" 22d0)
    layer))

(defun make-shape (path)
  (let ((layer (oc:send (oc:cls "CAShapeLayer") "layer")))
    (oc:send layer "setFrame:" 0d0 0d0 (float +side+ 1d0) (float +side+ 1d0))
    (oc:send layer "setPath:" path)
    (oc:send layer "setStrokeColor:"
             (oc:send (oc:color 0.45 0.92 0.85) "CGColor"))
    (oc:send layer "setFillColor:" nil)          ; nil is a null CGColorRef
    (oc:send layer "setLineWidth:" 1.6d0)
    (oc:send layer "setLineJoin:" (oc:nsstr "round"))
    layer))

(defun make-dot ()
  (let ((layer (oc:send (oc:cls "CALayer") "layer")))
    (oc:send layer "setFrame:" 0d0 0d0 13d0 13d0)
    (oc:send layer "setCornerRadius:" 6.5d0)
    (oc:send layer "setBackgroundColor:"
             (oc:send (oc:color 1.0 0.85 0.35) "CGColor"))
    (oc:send layer "setShadowColor:"
             (oc:send (oc:color 1.0 0.85 0.35) "CGColor"))
    (oc:send layer "setShadowRadius:" 8d0)
    (oc:send layer "setShadowOpacity:" 0.9d0)
    ;; A CGSize, as two doubles.
    (oc:send layer "setShadowOffset:" 0d0 0d0)
    layer))

;;; ------------------------------------------------------------------
;;; animations
;;;
;;; One property here is a C `float' rather than a CGFloat -- repeatCount --
;;; and sending a double where a float is expected puts the right value in the
;;; right register in the wrong format. KVC is the way out: -setValue:forKey:
;;; takes an NSNumber and converts to whatever the property actually is, which
;;; makes it a general escape hatch for any scalar type this bridge cannot
;;; name.

(defun number-of (value)
  (oc:send (oc:cls "NSNumber") "numberWithDouble:" (float value 1d0)))

(defun repeat-forever (animation)
  (oc:send animation "setValue:forKey:" (number-of 1e9) (oc:nsstr "repeatCount"))
  animation)

(defun stroke-animation (duration)
  (let ((animation (oc:send (oc:cls "CABasicAnimation") "animationWithKeyPath:"
                            (oc:nsstr "strokeEnd"))))
    (oc:send animation "setFromValue:" (number-of 0))
    (oc:send animation "setToValue:" (number-of 1))
    (oc:send animation "setDuration:" (float duration 1d0))
    ;; Linear, and that is what makes the two animations agree. strokeEnd is a
    ;; fraction of the path's LENGTH, and the dot's calculationMode is "paced",
    ;; which also advances by arc length -- so with the same duration and no
    ;; easing the dot sits exactly on the tip of the line as it is drawn. Any
    ;; easing here and the two drift apart immediately.
    (oc:send animation "setTimingFunction:"
             (oc:send (oc:cls "CAMediaTimingFunction")
                      "functionWithName:" (oc:nsstr "linear")))
    (repeat-forever animation)))

(defun travel-animation (path duration)
  "A keyframe animation that moves a layer along PATH.

CAKeyframeAnimation takes the CGPath directly, which is the whole trick: the
same path Lisp computed both draws the figure and drives the dot around it."
  (let ((animation (oc:send (oc:cls "CAKeyframeAnimation") "animationWithKeyPath:"
                            (oc:nsstr "position"))))
    (oc:send animation "setPath:" path)
    (oc:send animation "setDuration:" (float duration 1d0))
    (oc:send animation "setCalculationMode:" (oc:nsstr "paced"))
    (oc:send animation "setRotationMode:" nil)
    (repeat-forever animation)))

(defun restart-animations ()
  (oc:send *shape* "removeAllAnimations")
  (oc:send *dot* "removeAllAnimations")
  (oc:send *shape* "addAnimation:forKey:" (stroke-animation 6) (oc:nsstr "draw"))
  (oc:send *dot* "addAnimation:forKey:" (travel-animation *path* 6) (oc:nsstr "travel"))
  (values))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (oc:root-view))
         (safe (oc:send root "safeAreaLayoutGuide"))
         (title (oc:new "UILabel"))
         (canvas (oc:new "UIView"))
         (row (oc:new "UIStackView")))

    (oc:send root "setBackgroundColor:" (oc:color 0.04 0.04 0.06))

    (oc:send title "setText:" (oc:nsstr "r = cos 5θ/2"))
    (oc:send title "setTextColor:" (oc:color 0.55 0.95 0.9))
    (oc:send title "setFont:" (oc:mono-font 17))
    (oc:send root "addSubview:" title)

    ;; Constrained to a known size, so nothing has to read a CGRect back.
    (oc:send root "addSubview:" canvas)
    (oc:fix canvas "widthAnchor" +side+)
    (oc:fix canvas "heightAnchor" +side+)

    (oc:send row "setSpacing:" 8d0)
    (oc:send row "setDistribution:" 1)
    (oc:send row "addArrangedSubview:"
             (oc:on-tap (oc:system-button "again") "(layers:restart-animations)"))
    (oc:send row "addArrangedSubview:"
             (oc:on-tap (oc:system-button "3 petals") "(layers::reshape 3/2)"))
    (oc:send row "addArrangedSubview:"
             (oc:on-tap (oc:system-button "10 petals") "(layers::reshape 5/2)"))
    (oc:send root "addSubview:" row)

    (oc:pin title "topAnchor" safe "topAnchor" 14)
    (oc:pin title "centerXAnchor" safe "centerXAnchor")
    (oc:pin canvas "centerXAnchor" safe "centerXAnchor")
    (oc:pin canvas "centerYAnchor" safe "centerYAnchor")
    (oc:pin row "leadingAnchor" safe "leadingAnchor" 12)
    (oc:pin row "trailingAnchor" safe "trailingAnchor" -12)
    (oc:pin row "bottomAnchor" safe "bottomAnchor" -10)
    (oc:fix row "heightAnchor" 34)

    (setf *canvas* canvas)
    (values)))

(defun reshape (petals)
  "Rebuild the path, and with it both animations."
  (setf *path* (make-path (rose :petals petals)))
  (oc:send *shape* "setPath:" *path*)
  (restart-animations)
  (values))

(defun start ()
  (build-interface)
  (setf *path* (make-path (rose)))
  (setf *shape* (make-shape *path*))
  (setf *dot* (make-dot))
  (let ((host (oc:send *canvas* "layer")))
    (oc:send host "addSublayer:" (make-gradient))
    (oc:send host "addSublayer:" *shape*)
    (oc:send host "addSublayer:" *dot*))
  (restart-animations)
  (values))

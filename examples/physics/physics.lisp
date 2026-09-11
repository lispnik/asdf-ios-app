;;;; physics.lisp -- UIKit Dynamics, driven from Lisp.
;;;;
;;;; UIDynamicAnimator is a rigid-body simulator built into UIKit: you hand it
;;;; views and behaviours -- gravity, collision, elasticity -- and it moves
;;;; them. All of that is objects and CGFloats, so the whole simulation is
;;;; reachable from a bridge with no C in it.
;;;;
;;;; Structures go by value in both directions -- -initWithFrame: takes a
;;;; CGRect, -locationInView: returns a CGPoint -- and objc's dynamic FFI
;;;; carries them, so there is no C anywhere in this app.

(defpackage #:physics
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:drop #:reset))

(in-package #:physics)

(defvar *animator* nil)
(defvar *gravity* nil)
(defvar *collision* nil)
(defvar *elasticity* nil)
(defvar *tap* nil)
(defvar *field* nil "The view the simulation happens in.")
(defvar *shapes* '())

(defparameter +palette+
  '((0.98 0.45 0.35) (0.99 0.73 0.29) (0.43 0.82 0.55)
    (0.36 0.68 0.96) (0.65 0.55 0.95) (0.95 0.52 0.72))
  "Six colours, so a heap of twenty shapes still reads as separate objects.")

;;; ------------------------------------------------------------------
;;; shapes
;;;
;;; A dynamic item needs a frame -- UIKit Dynamics moves views by setting
;;; their centres and transforms, so Auto Layout is not involved and must not
;;; be, or the two would fight.

(defun make-shape (x y size roundness)
  "A coloured view at X,Y. ROUNDNESS of 0.5 is a circle."
  (let ((view (objc:invoke (objc:invoke "UIView" "alloc")
                           "initWithFrame:" (vector x y size size))))
    (destructuring-bind (red green blue) (nth (random (length +palette+)) +palette+)
      (objc:invoke view "setBackgroundColor:" (ui:color red green blue)))
    (objc:invoke (objc:invoke view "layer") "setCornerRadius:" (* size roundness))
    view))

(defun add-shape (view)
  "Put VIEW on screen and hand it to every behaviour that is already running."
  (objc:invoke *field* "addSubview:" view)
  (push view *shapes*)
  (dolist (behaviour (list *gravity* *collision* *elasticity*) view)
    (objc:invoke behaviour "addItem:" view)))

(defun field-width ()
  ;; -bounds is a CGRect, as #(x y width height).
  (aref (objc:invoke *field* "bounds") 2))

(defparameter +crowd-limit+ 40
  "Shapes are cheap but not free, and a heap this deep already looks like a
heap.")

(defun drop (&optional x)
  "Drop a shape from just inside the top edge, at X, or somewhere random.

Just INSIDE. An item that starts outside the collision boundary is not simply
dropped in: the solver pushes it back inside, and a dozen of them arriving at
once push each other, jam against the top edge and stay there. Spawning inside
the bounds -- and one at a time, see RAIN -- is the difference between a
simulation and a stuck pile."
  (when (< (length *shapes*) +crowd-limit+)
    (let* ((width (field-width))
           (size (+ 34 (random 30)))
           (left (or x (+ 10 (random (max 1 (floor (- width 20))))))))
      (add-shape (make-shape (min (- width size 2) (max 2 (- left (/ size 2))))
                             6 size
                             (if (zerop (random 2)) 0.5 0.22)))))
  (values))

;;; ------------------------------------------------------------------
;;; the simulation

(defun array-of (objects)
  "An NSArray. Built one addObject: at a time, since +arrayWithObjects: is
variadic and nil-terminated, which is not something to send blind."
  (let ((array (objc:invoke "NSMutableArray" "array")))
    (dolist (object objects array)
      (objc:invoke array "addObject:" object))))

(defun build-simulation ()
  (let ((items (array-of '())))
    (setf *animator*
          (ui:keep (objc:invoke (objc:invoke "UIDynamicAnimator" "alloc")
                                "initWithReferenceView:" *field*)))
    (setf *gravity*
          (objc:invoke (objc:invoke "UIGravityBehavior" "alloc")
                       "initWithItems:" items))
    (objc:invoke *gravity* "setMagnitude:" 1.4d0)

    (setf *collision*
          (objc:invoke (objc:invoke "UICollisionBehavior" "alloc")
                       "initWithItems:" items))
    ;; The reference view's edges become walls, which is what stops everything
    ;; falling out of the bottom of the world.
    (objc:invoke *collision* "setTranslatesReferenceBoundsIntoBoundary:" 1)

    (setf *elasticity*
          (objc:invoke (objc:invoke "UIDynamicItemBehavior" "alloc")
                       "initWithItems:" items))
    (objc:invoke *elasticity* "setElasticity:" 0.55d0)
    (objc:invoke *elasticity* "setFriction:" 0.45d0)
    (objc:invoke *elasticity* "setResistance:" 0.05d0)
    (objc:invoke *elasticity* "setAllowsRotation:" 1)

    (dolist (behaviour (list *gravity* *collision* *elasticity*))
      (objc:invoke *animator* "addBehavior:" behaviour))))

(defun reset ()
  (stop-rain)
  (dolist (view *shapes*)
    (dolist (behaviour (list *gravity* *collision* *elasticity*))
      (objc:invoke behaviour "removeItem:" view))
    (objc:invoke view "removeFromSuperview"))
  (setf *shapes* '())
  (values))

;;; ------------------------------------------------------------------
;;; touching it
;;;
;;; A tap drops a shape where you touched.

(defun tapped (recognizer)
  ;; -locationInView: returns a CGPoint, as #(x y).
  (let ((point (objc:invoke recognizer "locationInView:" *field*)))
    (drop (aref point 0))
    ;; The taptic engine. Nothing happens on the simulator, and on a phone this
    ;; is the difference between a demo and something that feels made.
    (let ((haptics (objc:invoke (objc:invoke "UIImpactFeedbackGenerator" "alloc")
                                "initWithStyle:" 1)))   ; medium
      (objc:invoke haptics "impactOccurred")))
  (values))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (ui:root-view))
         (safe (objc:invoke root "safeAreaLayoutGuide"))
         (field (ui:new "UIView"))
         (row (ui:new "UIStackView")))

    (objc:invoke root "setBackgroundColor:" (ui:color 0.07 0.07 0.09))

    (objc:invoke root "addSubview:" field)
    (ui:pin field "topAnchor" safe "topAnchor")
    (ui:pin field "leadingAnchor" safe "leadingAnchor")
    (ui:pin field "trailingAnchor" safe "trailingAnchor")

    (objc:invoke row "setSpacing:" 8d0)
    (objc:invoke row "setDistribution:" 1)
    (flet ((button (label function)
             (ui:on-tap (ui:system-button label)
                        (lambda (sender) (declare (ignore sender)) (funcall function)))))
      (objc:invoke row "addArrangedSubview:" (button "drop" #'drop))
      (objc:invoke row "addArrangedSubview:" (button "rain" (lambda () (rain 12))))
      (objc:invoke row "addArrangedSubview:" (button "reset" #'reset)))
    (objc:invoke root "addSubview:" row)

    (ui:pin row "topAnchor" field "bottomAnchor" 6)
    (ui:pin row "leadingAnchor" safe "leadingAnchor" 12)
    (ui:pin row "trailingAnchor" safe "trailingAnchor" -12)
    (ui:pin row "bottomAnchor" safe "bottomAnchor" -8)
    (ui:fix row "heightAnchor" 34)

    (setf *field* field)

    ;; A tap anywhere in the field drops a shape there.
    (setf *tap* (ui:keep
                 (objc:invoke (objc:invoke "UITapGestureRecognizer" "alloc")
                              "initWithTarget:action:"
                              (ui:action-target #'tapped) "fire:")))
    (objc:invoke field "addGestureRecognizer:" *tap*)
    (values)))

(defvar *timer* nil)
(defvar *pending* 0)

(defun rain (count)
  "Drop COUNT shapes, one every fifth of a second.

Spread over time rather than space: a shape needs room to fall before the next
one lands on it, and fourteen arriving in the same frame is a jam rather than
weather. An NSTimer, through the same target/action machinery the buttons
use."
  (incf *pending* count)
  (unless *timer*
    (setf *timer* (ui:after-every 0.2 (lambda (timer) (declare (ignore timer)) (rain-tick)))))
  (values))

(defun stop-rain ()
  (when *timer*
    (objc:invoke *timer* "invalidate")
    (ui:unkeep *timer*)
    (setf *timer* nil))
  (setf *pending* 0)
  (values))

(defun rain-tick ()
  (if (plusp *pending*)
      (progn (decf *pending*) (drop))
      (stop-rain))
  (values))

(defun start ()
  (objc:ensure-objc-initialized)
  (build-interface)
  (build-simulation)
  (rain 14)
  (values))

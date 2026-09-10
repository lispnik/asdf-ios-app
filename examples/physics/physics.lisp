;;;; physics.lisp -- UIKit Dynamics, driven from Lisp.
;;;;
;;;; UIDynamicAnimator is a rigid-body simulator built into UIKit: you hand it
;;;; views and behaviours -- gravity, collision, elasticity -- and it moves
;;;; them. All of that is objects and CGFloats, so the whole simulation is
;;;; reachable from a bridge with no C in it.
;;;;
;;;; Two places the struct boundary shows up, and they land on opposite sides:
;;;;
;;;;   -initWithFrame:   takes a CGRect BY VALUE and works anyway, sent as four
;;;;                     doubles. A CGRect is an HFA of four doubles, which
;;;;                     AAPCS64 puts in v0-v3 -- exactly where four separate
;;;;                     doubles go. It is a coincidence, and examples/abi-probe
;;;;                     measures precisely how far it extends.
;;;;
;;;;   -locationInView:  RETURNS a CGPoint by value, and no coincidence saves
;;;;                     that: a scalar return type names one register. Hence
;;;;                     glue.lisp, which is four lines long.

(defpackage #:physics
  (:use #:cl)
  (:local-nicknames (#:oc #:objc-lite))
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
  (let ((view (oc:send (oc:send (oc:cls "UIView") "alloc")
                       ;; The CGRect, as four doubles. See the header.
                       "initWithFrame:"
                       (float x 1d0) (float y 1d0)
                       (float size 1d0) (float size 1d0))))
    (destructuring-bind (red green blue) (nth (random (length +palette+)) +palette+)
      (oc:send view "setBackgroundColor:" (oc:color red green blue)))
    (oc:send (oc:send view "layer") "setCornerRadius:" (float (* size roundness) 1d0))
    view))

(defun add-shape (view)
  "Put VIEW on screen and hand it to every behaviour that is already running."
  (oc:send *field* "addSubview:" view)
  (push view *shapes*)
  (dolist (behaviour (list *gravity* *collision* *elasticity*) view)
    (oc:send behaviour "addItem:" view)))

(defun field-width ()
  (car (physics-glue:view-size *field*)))

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
  (let ((array (oc:send (oc:cls "NSMutableArray") "array")))
    (dolist (object objects array)
      (oc:send array "addObject:" object))))

(defun build-simulation ()
  (let ((items (array-of '())))
    (setf *animator*
          (oc:retain (oc:send (oc:send (oc:cls "UIDynamicAnimator") "alloc")
                              "initWithReferenceView:" *field*)))
    (setf *gravity*
          (oc:send (oc:send (oc:cls "UIGravityBehavior") "alloc")
                   "initWithItems:" items))
    (oc:send *gravity* "setMagnitude:" 1.4d0)

    (setf *collision*
          (oc:send (oc:send (oc:cls "UICollisionBehavior") "alloc")
                   "initWithItems:" items))
    ;; The reference view's edges become walls, which is what stops everything
    ;; falling out of the bottom of the world.
    (oc:send *collision* "setTranslatesReferenceBoundsIntoBoundary:" 1)

    (setf *elasticity*
          (oc:send (oc:send (oc:cls "UIDynamicItemBehavior") "alloc")
                   "initWithItems:" items))
    (oc:send *elasticity* "setElasticity:" 0.55d0)
    (oc:send *elasticity* "setFriction:" 0.45d0)
    (oc:send *elasticity* "setResistance:" 0.05d0)
    (oc:send *elasticity* "setAllowsRotation:" 1)

    (dolist (behaviour (list *gravity* *collision* *elasticity*))
      (oc:send *animator* "addBehavior:" behaviour))))

(defun reset ()
  (stop-rain)
  (dolist (view *shapes*)
    (dolist (behaviour (list *gravity* *collision* *elasticity*))
      (oc:send behaviour "removeItem:" view))
    (oc:send view "removeFromSuperview"))
  (setf *shapes* '())
  (values))

;;; ------------------------------------------------------------------
;;; touching it
;;;
;;; A tap drops a shape where you touched. LispTarget carries the callback --
;;; it ignores the sender, which is why the recognizer is kept in a variable
;;; here rather than read back out of the gesture.

(defun on-tap ()
  (let ((point (physics-glue:location-in-view *tap* *field*)))
    (drop (car point))
    ;; The taptic engine. Nothing happens on the simulator, and on a phone this
    ;; is the difference between a demo and something that feels made.
    (let ((haptics (oc:send (oc:send (oc:cls "UIImpactFeedbackGenerator") "alloc")
                            "initWithStyle:" 1)))   ; medium
      (oc:send haptics "impactOccurred")))
  (values))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (oc:root-view))
         (safe (oc:send root "safeAreaLayoutGuide"))
         (field (oc:new "UIView"))
         (row (oc:new "UIStackView")))

    (oc:send root "setBackgroundColor:" (oc:color 0.07 0.07 0.09))

    (oc:send root "addSubview:" field)
    (oc:pin field "topAnchor" safe "topAnchor")
    (oc:pin field "leadingAnchor" safe "leadingAnchor")
    (oc:pin field "trailingAnchor" safe "trailingAnchor")

    (oc:send row "setSpacing:" 8d0)
    (oc:send row "setDistribution:" 1)
    (oc:send row "addArrangedSubview:"
             (oc:on-tap (oc:system-button "drop") "(physics:drop)"))
    (oc:send row "addArrangedSubview:"
             (oc:on-tap (oc:system-button "rain") "(physics::rain 12)"))
    (oc:send row "addArrangedSubview:"
             (oc:on-tap (oc:system-button "reset") "(physics:reset)"))
    (oc:send root "addSubview:" row)

    (oc:pin row "topAnchor" field "bottomAnchor" 6)
    (oc:pin row "leadingAnchor" safe "leadingAnchor" 12)
    (oc:pin row "trailingAnchor" safe "trailingAnchor" -12)
    (oc:pin row "bottomAnchor" safe "bottomAnchor" -8)
    (oc:fix row "heightAnchor" 34)

    (setf *field* field)

    ;; A tap anywhere in the field drops a shape there.
    (setf *tap* (oc:retain
                 (oc:send (oc:send (oc:cls "UITapGestureRecognizer") "alloc")
                          "initWithTarget:action:"
                          (oc:retain (oc:send (oc:cls "LispTarget") "targetWithForm:"
                                              (oc:nsstr "(physics::on-tap)")))
                          (oc:sel "fire:"))))
    (oc:send field "addGestureRecognizer:" *tap*)
    (values)))

(defvar *timer* nil)
(defvar *pending* 0)

(defun rain (count)
  "Drop COUNT shapes, one every fifth of a second.

Spread over time rather than space: a shape needs room to fall before the next
one lands on it, and fourteen arriving in the same frame is a jam rather than
weather. NSTimer through LispTarget, which is the same target/action machinery
the buttons use."
  (incf *pending* count)
  (unless *timer*
    (setf *timer*
          (oc:retain
           (oc:send (oc:cls "NSTimer")
                    "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"
                    0.2d0
                    (oc:retain (oc:send (oc:cls "LispTarget") "targetWithForm:"
                                        (oc:nsstr "(physics::rain-tick)")))
                    (oc:sel "fire:")
                    nil
                    1))))
  (values))

(defun stop-rain ()
  (when *timer*
    (oc:send *timer* "invalidate")
    (setf *timer* nil))
  (setf *pending* 0)
  (values))

(defun rain-tick ()
  (if (plusp *pending*)
      (progn (decf *pending*) (drop))
      (stop-rain))
  (values))

(defun start ()
  (build-interface)
  (build-simulation)
  (rain 14)
  (values))

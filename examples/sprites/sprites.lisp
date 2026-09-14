;;;; sprites.lisp -- a game engine, steered from Lisp.
;;;;
;;;; SpriteKit draws and simulates; GameplayKit decides. A scene here holds
;;;; a flock of agents, each a GKAgent2D with behaviours -- wander, cohere,
;;;; separate, seek the leader -- whose goals and weights are Lisp's choice,
;;;; and a leader that follows a path GameplayKit found through a graph of
;;;; obstacles Lisp laid out. The scene is a Lisp subclass of SKScene: its
;;;; update: method runs every frame, on SpriteKit's schedule, and moves
;;;; each sprite to where its agent went.

(defpackage #:sprites
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:*flock-size*))

(in-package #:sprites)

(defparameter *flock-size* 14)
(defparameter +width+ 360d0)
(defparameter +height+ 460d0)

(defvar *status* nil)
(defvar *agents* '() "(agent . sprite), the leader first.")
(defvar *frames* 0)
(defvar *last-time* nil)
(defvar *path* '() "The leader's waypoints, from the pathfinder, as (x . y).")
(defvar *waypoint* 0)

;;; ------------------------------------------------------------------
;;; GameplayKit's structures: a vector of two floats

(objc:define-objc-struct (vector-float2 (:foreign-name "vector_float2"))
  (:x :float)
  (:y :float))

;;; ------------------------------------------------------------------
;;; obstacles, a graph, and a path through it

(defparameter +obstacles+
  '((120 120 34) (250 200 40) (110 300 36) (260 360 30))
  "(x y radius): what the leader must go around.")

(defun find-path ()
  "GKObstacleGraph around the obstacles, then the path from one corner to
the opposite one: GameplayKit's pathfinder, over a graph Lisp built."
  (let* ((obstacles (coerce (loop for (x y r) in +obstacles+
                                  collect (objc:invoke (objc:invoke (objc:invoke "GKCircleObstacle" "alloc")
                                                                    "initWithRadius:" (float r 1.0))
                                                       "autorelease")
                                    into list
                                  finally (return (loop for obstacle in list
                                                        for (x y) in +obstacles+
                                                        do (objc:invoke obstacle "setPosition:" (vector x y))
                                                        collect obstacle)))
                            'vector))
         (graph (objc:invoke "GKObstacleGraph" "graphWithObstacles:bufferRadius:" obstacles 24.0))
         (from (objc:invoke "GKGraphNode2D" "nodeWithPoint:" (vector 30.0 30.0)))
         (to (objc:invoke "GKGraphNode2D" "nodeWithPoint:" (vector (- +width+ 30) (- +height+ 30)))))
    (objc:invoke graph "connectNodeUsingObstacles:" from)
    (objc:invoke graph "connectNodeUsingObstacles:" to)
    (let ((nodes (objc:invoke graph "findPathFromNode:toNode:" from to)))
      (loop for i below (objc:invoke nodes "count")
            for node = (objc:invoke nodes "objectAtIndex:" i)
            for point = (objc:invoke node "position")
            collect (cons (aref point 0) (aref point 1))))))

;;; ------------------------------------------------------------------
;;; the scene: a Lisp subclass of SKScene, updated every frame

(objc:define-objc-class flock-scene () ()
  (:objc-class-name "LispFlockScene")
  (:objc-superclass-name "SKScene"))

(defun agent-position (agent)
  (let ((p (objc:invoke agent "position"))) (cons (aref p 0) (aref p 1))))

(objc:define-objc-method ("update:" :void)
    ((self flock-scene) (time :double))
  ;; The leader walks the path; everyone else's agent follows its behaviour.
  (let ((delta (if *last-time* (min 0.05 (- time *last-time*)) 0.016)))
    (setf *last-time* time)
    (incf *frames*)
    (let* ((leader (car (first *agents*)))
           (target (nth *waypoint* *path*)))
      (when target
        (destructuring-bind (lx . ly) (agent-position leader)
          (when (< (sqrt (+ (expt (- (car target) lx) 2) (expt (- (cdr target) ly) 2))) 12)
            (setf *waypoint* (mod (1+ *waypoint*) (length *path*)))))))
    (loop for (agent . sprite) in *agents*
          do (objc:invoke agent "updateWithDeltaTime:" delta)
             (destructuring-bind (x . y) (agent-position agent)
               (objc:invoke sprite "setPosition:" (vector x y))
               (objc:invoke sprite "setZRotation:" (float (objc:invoke agent "rotation") 1d0))))
    (when (zerop (mod *frames* 60))
      (ios-app-runtime:on-main
       (lambda ()
         (objc:invoke *status* "setText:"
                      (format nil "~d agents, ~d frames; leader at waypoint ~d of ~d"
                              (length *agents*) *frames* *waypoint* (length *path*))))))))

;;; ------------------------------------------------------------------
;;; agents and their behaviours, chosen here

(defun make-agent (x y &key leader)
  (let ((agent (objc:alloc-init-object "GKAgent2D")))
    (objc:invoke agent "setPosition:" (vector (float x 1.0) (float y 1.0)))
    (objc:invoke agent "setMaxSpeed:" (if leader 70.0 90.0))
    (objc:invoke agent "setMaxAcceleration:" (if leader 40.0 60.0))
    (objc:invoke agent "setRadius:" 8.0)
    (objc:invoke agent "setMass:" 0.2)
    agent))

(defun goal (name &rest arguments)
  (apply #'objc:invoke "GKGoal" name arguments))

(defun set-behaviours (leader others)
  "The leader seeks its next waypoint; the flock coheres, separates, aligns,
and seeks the leader: GameplayKit's goals, Lisp's weights."
  (let* ((others-vector (coerce others 'vector))
         (leader-goal (goal "goalToSeekAgent:" leader))
         (behaviour (objc:invoke "GKBehavior" "behaviorWithGoals:andWeights:"
                                 (vector (goal "goalToCohereWithAgents:maxDistance:maxAngle:" others-vector 80.0 (float pi 1.0))
                                         (goal "goalToSeparateFromAgents:maxDistance:maxAngle:" others-vector 24.0 (float pi 1.0))
                                         (goal "goalToAlignWithAgents:maxDistance:maxAngle:" others-vector 60.0 (float pi 1.0))
                                         leader-goal
                                         (goal "goalToWander:" 20.0))
                                 (vector 1.0 3.0 1.0 2.0 0.5))))
    (dolist (agent others) (objc:invoke agent "setBehavior:" behaviour))))

(defvar *leader-tracker* nil)

(defun steer-leader-along-path (leader)
  "A tracking agent stands on the current waypoint; the leader seeks it."
  (setf *leader-tracker* (ui:keep (objc:alloc-init-object "GKAgent2D")))
  (objc:invoke leader "setBehavior:"
               (objc:invoke "GKBehavior" "behaviorWithGoal:weight:" (goal "goalToSeekAgent:" *leader-tracker*) 1.0)))

(defun move-tracker ()
  (let ((target (nth *waypoint* *path*)))
    (when target (objc:invoke *leader-tracker* "setPosition:" (vector (float (car target) 1.0) (float (cdr target) 1.0))))))

;;; ------------------------------------------------------------------
;;; the scene, built

(defun sprite (colour &key (size 14))
  (let ((node (objc:invoke "SKSpriteNode" "spriteNodeWithColor:size:" colour (vector size size))))
    (objc:invoke node "setAnchorPoint:" (vector 0.5 0.5))
    node))

(defun build-scene (view)
  (let ((scene (objc:invoke (objc:invoke (make-instance 'flock-scene) "initWithSize:" (vector +width+ +height+)) "autorelease")))
    (objc:invoke scene "setBackgroundColor:" (ui:color 0.06 0.07 0.12))
    ;; Obstacles, drawn.
    (loop for (x y r) in +obstacles+
          do (let ((circle (objc:invoke "SKShapeNode" "shapeNodeWithCircleOfRadius:" (float r 1d0))))
               (objc:invoke circle "setPosition:" (vector x y))
               (objc:invoke circle "setFillColor:" (ui:color 0.25 0.25 0.35))
               (objc:invoke circle "setStrokeColor:" (ui:color 0.4 0.4 0.55))
               (objc:invoke scene "addChild:" circle)))
    ;; The path, drawn.
    (setf *path* (find-path))
    (let ((path (objc:invoke "UIBezierPath" "bezierPath")))
      (loop for (x . y) in *path* for first = t then nil
            do (objc:invoke path (if first "moveToPoint:" "addLineToPoint:") (vector x y)))
      (let ((line (objc:invoke "SKShapeNode" "shapeNodeWithPath:" (objc:invoke path "CGPath"))))
        (objc:invoke line "setStrokeColor:" (ui:color 0.3 0.6 0.9 0.5))
        (objc:invoke line "setLineWidth:" 2d0)
        (objc:invoke scene "addChild:" line)))
    ;; Agents and sprites.
    (let* ((leader (make-agent 30 30 :leader t))
           (others (loop for i below *flock-size*
                         collect (make-agent (+ 40 (random 60)) (+ 40 (random 60))))))
      (setf *agents*
            (cons (cons leader (sprite (ui:color 1.0 0.75 0.2) :size 18))
                  (loop for agent in others
                        for i from 0
                        collect (cons agent (sprite (objc:invoke "UIColor" "colorWithHue:saturation:brightness:alpha:"
                                                                 (/ (mod (* i 37) 360) 360d0) 0.7 0.95 1.0))))))
      (loop for (nil . node) in *agents* do (objc:invoke scene "addChild:" node))
      (steer-leader-along-path leader)
      (set-behaviours leader others)
      (dolist (entry *agents*) (ui:keep (car entry)) (ui:keep (cdr entry))))
    (objc:invoke scene "setScaleMode:" 1)                ; aspect fit
    (objc:invoke view "presentScene:" scene)
    ;; Keep the tracker on the current waypoint as the leader advances.
    (ui:after-every 0.1 (lambda (timer) (declare (ignore timer)) (move-tracker)))
    scene))

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
         (view (ui:new "SKView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "A flock, steered from Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "GameplayKit agents with goals and weights chosen in Lisp; a leader on a path GameplayKit found through obstacles Lisp laid out; a Lisp subclass of SKScene updating every frame." :size 13))
    (objc:invoke (objc:invoke view "layer") "setCornerRadius:" 12)
    (objc:invoke view "setClipsToBounds:" t)
    (objc:invoke column "addArrangedSubview:" view)
    (ui:fix view "heightAnchor" 460)
    (ui:pin view "widthAnchor" column "widthAnchor")
    (setf *status* (label "" :size 12))
    (objc:invoke column "addArrangedSubview:" *status*)
    (build-scene view)
    (format t "SPRITES: ~d agents; path of ~d waypoints~%" (length *agents*) (length *path*))
    (finish-output)
    (values)))

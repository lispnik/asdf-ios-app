;;;; sensors.lisp -- three things a simulator cannot do.
;;;;
;;;; The accelerometer, haptics and Face ID exist only on a device, and
;;;; each is reached the same way: an Objective-C object asked to start,
;;;; with a block made from a Lisp lambda for it to call back through.
;;;; CoreMotion calls on an operation queue of its own, sixty times a
;;;; second; LocalAuthentication replies once, on a thread of its choice;
;;;; UIKit's feedback generator needs no reply at all.
;;;;
;;;; On the simulator the accelerometer says it is absent, the feedback
;;;; generator does nothing, and Face ID is available only if enrolled from
;;;; the simulator's menu -- which is enough to see the interface and check
;;;; the three code paths run. The device is where it means something.

(defpackage #:sensors
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:start-motion #:haptic #:authenticate))

(in-package #:sensors)

(defvar *status* nil)
(defvar *bubble* nil)
(defvar *level* nil)
(defvar *reading* nil)

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "SENSORS: ~a~%" text)
    (finish-output)
    (when *status* (objc:invoke *status* "setText:" text))))

;;; ------------------------------------------------------------------
;;; motion: a block called sixty times a second, off the main thread

(objc:define-objc-block-type accelerometer-handler :void (objc:objc-object-pointer objc:objc-object-pointer))

(defvar *motion* nil)
(defvar *handler* nil "Kept: the motion manager holds it for as long as updates run.")
(defvar *samples* 0)

(defun start-motion ()
  (setf *motion* (ui:keep (objc:alloc-init-object "CMMotionManager")))
  (if (not (objc:invoke-bool *motion* "isAccelerometerAvailable"))
      (progn (say "no accelerometer here: a simulator, or a Mac")
             (objc:invoke *reading* "setText:" "accelerometer: not available"))
      (progn
        (objc:invoke *motion* "setAccelerometerUpdateInterval:" (/ 1d0 30))
        (setf *handler*
              (objc:make-objc-block
               'accelerometer-handler
               (lambda (data error)
                 (declare (ignore error))
                 (unless (cffi:null-pointer-p data)
                   ;; CMAcceleration is three doubles, returned by value.
                   (let* ((acceleration (objc:invoke data "acceleration"))
                          (x (aref acceleration 0))
                          (y (aref acceleration 1))
                          (z (aref acceleration 2)))
                     (incf *samples*)
                     ;; UIKit is main-thread only; this is CoreMotion's queue.
                     (ios-app-runtime:on-main
                      (lambda () (move-bubble x y z))))))))
        (objc:invoke *motion* "startAccelerometerUpdatesToQueue:withHandler:"
                     (objc:alloc-init-object "NSOperationQueue") *handler*)
        (say "accelerometer running at 30 Hz, on CoreMotion's queue"))))

(defun move-bubble (x y z)
  "Put the bubble where gravity says: tilt right, bubble goes left."
  (let* ((bounds (objc:invoke *level* "bounds"))
         (width (aref bounds 2))
         (height (aref bounds 3))
         (radius 22)
         (cx (- (/ width 2) (* x (- (/ width 2) radius))))
         (cy (- (/ height 2) (* (- y) (- (/ height 2) radius)))))
    (objc:invoke *bubble* "setCenter:" (vector (float cx 1d0) (float cy 1d0)))
    (objc:invoke *reading* "setText:"
                 (format nil "x ~,2f  y ~,2f  z ~,2f   (~d samples)" x y z *samples*))))

;;; ------------------------------------------------------------------
;;; haptics: nothing to wait for

(defun haptic (&optional (style 2))
  "A tap you can feel. STYLE: 0 light, 1 medium, 2 heavy."
  (let ((generator (objc:invoke (objc:invoke (objc:invoke "UIImpactFeedbackGenerator" "alloc")
                                             "initWithStyle:" style)
                                "autorelease")))
    (objc:invoke generator "prepare")
    (objc:invoke generator "impactOccurred")
    (say "haptic impact, style ~d" style)))

;;; ------------------------------------------------------------------
;;; Face ID: one reply, on a thread of the framework's choosing

(objc:define-objc-block-type authentication-reply :void (objc:objc-c++-bool objc:objc-object-pointer))

(defconstant +policy-biometrics+ 1 "LAPolicyDeviceOwnerAuthenticationWithBiometrics")

(defun authenticate ()
  (let ((context (objc:alloc-init-object "LAContext")))
    (ui:keep context)
    (cffi:with-foreign-object (error :pointer)
      (setf (cffi:mem-ref error :pointer) (cffi:null-pointer))
      (if (not (objc:invoke-bool context "canEvaluatePolicy:error:" +policy-biometrics+ error))
          (say "biometrics unavailable: ~a"
               (let ((e (cffi:mem-ref error :pointer)))
                 (if (cffi:null-pointer-p e) "no reason given"
                     (objc:ns-string-to-string (objc:invoke e "localizedDescription")))))
          (objc:with-objc-block (reply 'authentication-reply
                                       (lambda (success error)
                                         (ios-app-runtime:on-main
                                          (lambda ()
                                            (say "Face ID: ~a"
                                                 (if success "recognised"
                                                     (objc:ns-string-to-string
                                                      (objc:invoke error "localizedDescription"))))
                                            (ui:unkeep context)))))
            (say "asking Face ID…")
            (objc:invoke context "evaluatePolicy:localizedReason:reply:"
                         +policy-biometrics+ "Lisp would like to know it is you" reply))))))

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
         (row (ui:new "UIStackView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 12)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "What only a device has" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "A bubble level from the accelerometer, a haptic tap, and Face ID: each an Objective-C object calling a Lisp block back, from its own thread." :size 13))
    ;; The level.
    (setf *level* (ui:new "UIView"))
    (objc:invoke *level* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *level* "layer") "setCornerRadius:" 150)
    (objc:invoke column "addArrangedSubview:" *level*)
    (ui:fix *level* "heightAnchor" 300)
    (ui:fix *level* "widthAnchor" 300)
    (objc:invoke column "setAlignment:" 3)             ; center
    (setf *bubble* (ui:new "UIView"))
    (objc:invoke *bubble* "setTranslatesAutoresizingMaskIntoConstraints:" t)
    (objc:invoke *bubble* "setFrame:" (vector 128d0 128d0 44d0 44d0))
    (objc:invoke *bubble* "setBackgroundColor:" (ui:color 0.2 0.7 1.0))
    (objc:invoke (objc:invoke *bubble* "layer") "setCornerRadius:" 22)
    (objc:invoke *level* "addSubview:" *bubble*)
    (setf *reading* (label "" :size 12))
    (objc:invoke *reading* "setFont:" (ui:mono-font 12))
    (objc:invoke column "addArrangedSubview:" *reading*)
    ;; Buttons.
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 16)
    (let ((tap (ui:system-button "Haptic tap"))
          (face (ui:system-button "Face ID")))
      (ui:on-tap tap (lambda (sender) (declare (ignore sender)) (haptic)))
      (ui:on-tap face (lambda (sender) (declare (ignore sender)) (authenticate)))
      (objc:invoke row "addArrangedSubview:" tap)
      (objc:invoke row "addArrangedSubview:" face))
    (objc:invoke column "addArrangedSubview:" row)
    (setf *status* (label "" :size 12 :lines 2))
    (objc:invoke column "addArrangedSubview:" *status*)
    (start-motion)
    (values)))

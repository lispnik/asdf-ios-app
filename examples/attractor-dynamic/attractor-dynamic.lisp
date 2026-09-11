;;;; attractor-dynamic.lisp -- the de Jong attractor, with no C anywhere.
;;;;
;;;; The sibling example, attractor-aot, keeps a C file: its drawRect: IMP and the
;;;; loop that issues two million CGContextFillRect calls. It was written when
;;;; a method taking a CGRect by value was out of reach of ECL's dynamic FFI,
;;;; and it keeps the C by choice, because that loop is a reasonable thing to
;;;; have in C.
;;;;
;;;; This one does without, and does the loop differently rather than slowly.
;;;; The map is iterated in Lisp into a density buffer -- an ordinary
;;;; (UNSIGNED-BYTE 8) array -- and CoreGraphics is handed that buffer as one
;;;; image, in one call. drawRect: is a Lisp method on a UIView subclass
;;;; defined here, receiving its CGRect by value; the CoreGraphics functions are
;;;; called by name through SI:CALL-CFUN, the rectangle they take going by
;;;; value too; the gestures reach Lisp through a target whose fire: is a
;;;; closure. Nothing in the app is compiled by a C compiler.
;;;;
;;;; It is also the better way round. A frame costs a few million array writes
;;;; in compiled Lisp and six foreign calls, where the C version costs two
;;;; million foreign calls' worth of fill rectangles.

(defpackage #:attractor-dynamic
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:redraw #:step-point #:parameters
           #:*a* #:*b* #:*c* #:*d* #:*points*))

(in-package #:attractor-dynamic)

(defparameter *a* 1.4d0)
(defparameter *b* -2.3d0)
(defparameter *c* 2.4d0)
(defparameter *d* -2.1d0)

(defparameter *points* 600000
  "Points per frame. The loop is compiled Lisp doing two sines and two cosines
per point; this many keeps a drag responsive on a simulator.")

(defparameter *scale* 2
  "Pixels per point of the view. The screen is 3; 2 halves the buffer and the
figure does not need the difference.")

(defvar *view* nil "The view, as a pointer.")

;;; ------------------------------------------------------------------
;;; the mathematics

(declaim (notinline step-point))
(defun step-point (x y a b c d)
  "One iteration of the de Jong map. NOTINLINE so that a redefinition takes:
ECL compiles a call to a function in the same file as a direct C call."
  (declare (optimize (speed 3) (safety 0) (debug 0))
           (double-float x y a b c d))
  (values (- (sin (* a y)) (cos (* b x)))
          (- (sin (* c x)) (cos (* d y)))))

;;; ------------------------------------------------------------------
;;; density, then colour
;;;
;;; Two arrays, reused between frames: how often each pixel was visited, and
;;; the RGBX bytes CoreGraphics will be shown.

(defvar *counts* nil)
(defvar *pixels* nil)

(defun ensure-buffers (width height)
  (let ((n (* width height)))
    (unless (and *counts* (= (length (the (simple-array (unsigned-byte 16) (*)) *counts*)) n))
      (setf *counts* (make-array n :element-type '(unsigned-byte 16))))
    (unless (and *pixels* (= (length (the (simple-array (unsigned-byte 8) (*)) *pixels*)) (* 4 n)))
      (setf *pixels* (make-array (* 4 n) :element-type '(unsigned-byte 8))))
    (fill *counts* 0)
    (values *counts* *pixels*)))

(defun accumulate (counts width height)
  "Iterate the map *POINTS* times, counting visits per pixel."
  (declare (optimize (speed 3) (safety 0) (debug 0))
           (type (simple-array (unsigned-byte 16) (*)) counts)
           (fixnum width height))
  (let* ((n *points*)
         (a *a*) (b *b*) (c *c*) (d *d*)
         ;; The map's range is [-2,2] in both axes.
         (sx (/ (float width 1d0) 4.2d0))
         (sy (/ (float height 1d0) 4.2d0))
         (cx (/ (float width 1d0) 2d0))
         (cy (/ (float height 1d0) 2d0))
         (x 0.1d0) (y 0.1d0))
    (declare (fixnum n) (double-float a b c d sx sy cx cy x y))
    (dotimes (i n)
      (multiple-value-setq (x y) (step-point x y a b c d))
      ;; Row 0 of the image is drawn at the BOTTOM of a UIKit view --
      ;; CGContextDrawImage works in CoreGraphics' upward coordinates -- so
      ;; the row is flipped here to keep the figure the way attractor-aot
      ;; draws it.
      (let ((px (floor (+ cx (* x sx))))
            (py (- (1- height) (floor (+ cy (* y sy))))))
        (declare (fixnum px py))
        (when (and (<= 0 px) (< px width) (<= 0 py) (< py height))
          (let* ((i (+ px (* py width)))
                 (v (aref counts i)))
            (when (< v 65535)
              (setf (aref counts i) (1+ v)))))))))

(defparameter +ramp+
  (let ((ramp (make-array 256 :element-type '(unsigned-byte 8))))
    ;; Density to brightness, saturating: the structure is in how often a
    ;; region is visited, and a linear ramp burns out the dense parts.
    (dotimes (i 256 ramp)
      (setf (aref ramp i) (round (* 255 (- 1 (exp (/ i -12d0)))))))))

(defun colour (counts pixels)
  "Counts to RGBX bytes: a cold blue-white on a dark ground."
  (declare (optimize (speed 3) (safety 0) (debug 0))
           (type (simple-array (unsigned-byte 16) (*)) counts)
           (type (simple-array (unsigned-byte 8) (*)) pixels))
  (let ((ramp +ramp+))
    (declare (type (simple-array (unsigned-byte 8) (*)) ramp))
    (dotimes (i (length counts))
      (let* ((c (aref counts i))
             (v (aref ramp (min c 255)))
             (j (* 4 i)))
        (declare (fixnum c v j))
        (setf (aref pixels j)       (ash (* v 90) -8)     ; red    0.35
              (aref pixels (+ j 1)) (ash (* v 218) -8)    ; green  0.85
              (aref pixels (+ j 2)) v                     ; blue   1.0
              (aref pixels (+ j 3)) 255)))))

(defun render (width height)
  "The frame, as RGBX bytes."
  (multiple-value-bind (counts pixels) (ensure-buffers width height)
    (accumulate counts width height)
    (colour counts pixels)
    pixels))

;;; ------------------------------------------------------------------
;;; CoreGraphics, by name
;;;
;;; Each function is looked up once, lazily -- at load time on the Mac the
;;; app's frameworks are not linked, and an eager lookup fails the build.

(defvar *functions* (make-hash-table :test #'equal))

(defun cg (name)
  (or (gethash name *functions*)
      (setf (gethash name *functions*)
            (si:find-foreign-symbol name :default :pointer-void 0))))

(defparameter +cgrect+ '(:struct (:m :double) (:m :double) (:m :double) (:m :double))
  "A CGRect as SI:CALL-CFUN wants it described.")

(defun rect (x y width height)
  "A CGRect in foreign memory, for passing by value."
  (let ((r (si::allocate-foreign-data :void 32)))
    (si:foreign-data-set-elt r 0 :double (float x 1d0))
    (si:foreign-data-set-elt r 8 :double (float y 1d0))
    (si:foreign-data-set-elt r 16 :double (float width 1d0))
    (si:foreign-data-set-elt r 24 :double (float height 1d0))
    r))

(defun null-pointer () (ffi:make-null-pointer :pointer-void))

(defun current-context ()
  (si:call-cfun (cg "UIGraphicsGetCurrentContext") :pointer-void '() '()))

(defun fill-rect (context x y width height red green blue)
  (si:call-cfun (cg "CGContextSetRGBFillColor") :void
                '(:pointer-void :double :double :double :double)
                (list context (float red 1d0) (float green 1d0) (float blue 1d0) 1d0))
  (si:call-cfun (cg "CGContextFillRect") :void
                (list :pointer-void +cgrect+)
                (list context (rect x y width height))))

(defun draw-pixels (context pixels width height x y view-width view-height)
  "Show PIXELS, WIDTH by HEIGHT of RGBX, scaled into the view's rectangle.

The image is made over the Lisp array's own storage: ECL's specialised arrays
are contiguous and the collector does not move them, so the pointer holds for
as long as the array does -- and *PIXELS* holds it."
  (let* ((data (si:make-foreign-data-from-array pixels))
         (space (si:call-cfun (cg "CGColorSpaceCreateDeviceRGB") :pointer-void '() '()))
         (provider (si:call-cfun (cg "CGDataProviderCreateWithData") :pointer-void
                                 '(:pointer-void :pointer-void :unsigned-long :pointer-void)
                                 (list (null-pointer) data (* 4 width height) (null-pointer))))
         (image (si:call-cfun (cg "CGImageCreate") :pointer-void
                              '(:unsigned-long :unsigned-long :unsigned-long :unsigned-long
                                :unsigned-long :pointer-void :unsigned-int :pointer-void
                                :pointer-void :byte :int)
                              (list width height 8 32 (* 4 width) space
                                    5                 ; kCGImageAlphaNoneSkipLast
                                    provider (null-pointer)
                                    0                 ; no interpolation
                                    0))))             ; kCGRenderingIntentDefault
    (si:call-cfun (cg "CGContextDrawImage") :void
                  (list :pointer-void +cgrect+ :pointer-void)
                  (list context (rect x y view-width view-height) image))
    (si:call-cfun (cg "CGImageRelease") :void '(:pointer-void) (list image))
    (si:call-cfun (cg "CGDataProviderRelease") :void '(:pointer-void) (list provider))
    (si:call-cfun (cg "CGColorSpaceRelease") :void '(:pointer-void) (list space))))

;;; ------------------------------------------------------------------
;;; the view
;;;
;;; A UIView subclass whose drawRect: is a Lisp method. The CGRect arrives by
;;; value as #(x y width height); the body must not signal, because its caller
;;; is UIKit and there is no handler on that side.

(objc:define-objc-class attractor-view ()
  ()
  (:objc-class-name "AttractorDynamicView")
  (:objc-superclass-name "UIView"))

(objc:define-objc-method ("drawRect:" :void)
    ((self attractor-view) (dirty cocoa:ns-rect))
  (declare (ignore dirty))
  (handler-case (draw self)
    (error (condition)
      (format t "~&ATTRACTOR: draw failed: ~a~%" condition)
      (finish-output))))

(defun draw (view)
  (let* ((bounds (objc:invoke view "bounds"))
         (width (aref bounds 2))
         (height (aref bounds 3))
         (context (current-context))
         (pixel-width (max 1 (round (* width *scale*))))
         (pixel-height (max 1 (round (* height *scale*)))))
    (fill-rect context 0 0 width height 0.02 0.02 0.04)
    (draw-pixels context (render pixel-width pixel-height)
                 pixel-width pixel-height 0 0 width height)))

(defun redraw ()
  (when *view*
    (objc:invoke *view* "setNeedsDisplay")))

(defun parameters ()
  (list :a *a* :b *b* :c *c* :d *d*))

;;; ------------------------------------------------------------------
;;; gestures
;;;
;;; The recognizer is the sender, so its state is read from it.

(defun on-pan (recognizer)
  "Drag to move A and B. The translation is a CGPoint by value, and is zeroed
after reading so each call sees a delta."
  (let ((delta (objc:invoke recognizer "translationInView:" *view*)))
    (objc:invoke recognizer "setTranslation:inView:" #(0 0) *view*)
    (incf *a* (* (aref delta 0) 0.004d0))
    (incf *b* (* (aref delta 1) 0.004d0))
    (redraw)))

(defun on-pinch (recognizer)
  "Pinch to move C and D in opposite directions, which opens the figure out."
  (let ((delta (- (objc:invoke recognizer "scale") 1d0)))
    (objc:invoke recognizer "setScale:" 1d0)
    (incf *c* (* delta 1.5d0))
    (decf *d* (* delta 1.5d0))
    (redraw)))

(defun install-gestures (view)
  (loop for (class-name function) in (list (list "UIPanGestureRecognizer" #'on-pan)
                                           (list "UIPinchGestureRecognizer" #'on-pinch))
        do (objc:invoke view "addGestureRecognizer:"
                        (ui:keep (objc:invoke (objc:invoke class-name "alloc")
                                              "initWithTarget:action:"
                                              (ui:action-target function) "fire:")))))

;;; ------------------------------------------------------------------

(defun start ()
  "Entry point. Runs on the main thread and returns; the run loop follows."
  (objc:ensure-objc-initialized)
  (let* ((root (ui:root-view))
         (view (ui:keep (make-instance 'attractor-view)))
         (pointer (objc:objc-object-pointer view)))
    (objc:invoke pointer "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke pointer "setContentMode:" 3)    ; UIViewContentModeRedraw: a new frame on rotation
    (objc:invoke pointer "setBackgroundColor:" (ui:color 0.02 0.02 0.04))
    (objc:invoke root "addSubview:" pointer)
    (ui:pin pointer "topAnchor" root "topAnchor")
    (ui:pin pointer "bottomAnchor" root "bottomAnchor")
    (ui:pin pointer "leadingAnchor" root "leadingAnchor")
    (ui:pin pointer "trailingAnchor" root "trailingAnchor")
    (setf *view* pointer)
    (install-gestures pointer))
  (format t "~&ATTRACTOR: ~a ~a, ~d points per frame, no C~%"
          (lisp-implementation-type) (lisp-implementation-version) *points*)
  (format t "ATTRACTOR: drag for A and B, pinch for C and D.~%")
  (finish-output))

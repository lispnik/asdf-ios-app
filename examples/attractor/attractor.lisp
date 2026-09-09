;;;; attractor.lisp -- the mathematics, and where it stays editable.
;;;;
;;;; Everything here is ordinary Lisp, cross-compiled to native arm64. None of
;;;; it needs a C compiler at run time, and all of it can be redefined at run
;;;; time -- boot installs the bytecodes compiler, so a new DEFUN replaces a
;;;; compiled one with bytecode and the next redraw picks it up.

(defpackage #:attractor
  (:use #:cl)
  (:export #:start #:draw #:step-point #:redraw #:parameters
           #:*a* #:*b* #:*c* #:*d* #:*points*))

(in-package #:attractor)

(defparameter *a* 1.4d0)
(defparameter *b* -2.3d0)
(defparameter *c* 2.4d0)
(defparameter *d* -2.1d0)

;;; Not every set of parameters gives an attractor. Most collapse to a short
;;; periodic cycle, and the failure is invisible from the outside: the draw
;;; loop still issues every point, they just land on the same twenty pixels.
;;; (-2.0 -2.4 1.1 -0.9) gives 30 distinct positions in 100,000 iterations;
;;; these give about 97,000.

(defparameter *points* 300000
  "Points per frame. Two million is prettier and takes about a second; this is
chosen so a redraw stays responsive on a simulator.")

(defvar *buffer* nil
  "Interleaved x,y pairs in screen coordinates. Reused between frames: the
allocation is the expensive part, not the arithmetic.")

(defvar *view* nil)

(declaim (notinline step-point))
(defun step-point (x y a b c d)
  "One iteration of the de Jong map.

Redefine this over a REPL and the next redraw shows different mathematics.
That is the whole demonstration: the function is native code compiled on a Mac,
and replacing it on the phone costs nothing but a DEFUN.

NOTINLINE, and not by accident. ECL compiles a call to a function defined in
the same file as a direct C call to it -- INLINE would only make that worse --
so FILL-BUFFER would keep running the version that was compiled on the Mac and
a redefinition would appear to do nothing at all. NOTINLINE sends the call
through the FDEFINITION, which is what a new DEFUN replaces. It costs a funcall
per iteration; the demo is still interactive, and a demo that quietly cannot do
the thing it claims is worth less than the cycles."
  (declare (optimize (speed 3) (safety 0) (debug 0))
           (double-float x y a b c d))
  (values (- (sin (* a y)) (cos (* b x)))
          (- (sin (* c x)) (cos (* d y)))))

(defun fill-buffer (width height)
  "Iterate the map and scale into WIDTH by HEIGHT."
  (declare (optimize (speed 3) (safety 0) (debug 0))
           (double-float width height))
  (let* ((n *points*)
         ;; Re-allocated when *POINTS* grows, and not merely when it is NIL:
         ;; FILL-BUFFER runs at (safety 0), so a stale short buffer is not an
         ;; error, it is a heap overwrite -- and raising *POINTS* from a REPL is
         ;; the first thing anyone tries.
         (buffer (if (and *buffer* (>= (length (the (simple-array double-float (*))
                                                    *buffer*))
                                       (* 2 n)))
                     *buffer*
                     (setf *buffer* (make-array (* 2 n)
                                                :element-type 'double-float))))
         (a *a*) (b *b*) (c *c*) (d *d*)
         ;; The map's range is [-2,2] in both axes.
         (sx (/ width 4.2d0))
         (sy (/ height 4.2d0))
         (cx (/ width 2d0))
         (cy (/ height 2d0))
         (x 0.1d0) (y 0.1d0))
    (declare (type (simple-array double-float (*)) buffer)
             (double-float a b c d sx sy cx cy x y)
             (fixnum n))
    (dotimes (i n buffer)
      (multiple-value-setq (x y) (step-point x y a b c d))
      (setf (aref buffer (* 2 i)) (+ cx (* x sx))
            (aref buffer (1+ (* 2 i))) (+ cy (* y sy))))))

(defun draw (width height)
  "Called from the drawRect: IMP, on the main thread, with the view's size.

It must not signal. A Lisp condition unwinding through a UIKit frame corrupts
it, and cl_funcall offers no protection, so the handler is here."
  (handler-case
      (let ((buffer (fill-buffer width height)))
        ;; Alpha well below 1 so density accumulates: the attractor's structure
        ;; is in how often a region is visited, not in any single point.
        (attractor-glue:draw-points buffer *points*
                                    0.35d0 0.85d0 1.0d0   ; a cold blue-white
                                    0.30d0                 ; alpha
                                    1.0d0))                ; point size
    (error (e)
      (format t "~&ATTRACTOR: draw failed: ~a~%" e)
      (finish-output)
      0)))

(defvar *pan* nil)
(defvar *pinch* nil)

(defun redraw ()
  "Ask for a new frame. Safe to call from a REPL through ON-MAIN."
  (when *view*
    (attractor-glue:set-needs-display *view*)))

(defun parameters ()
  (list :a *a* :b *b* :c *c* :d *d*))

;;; The two handlers below are reached from LispTarget, which evaluates a form
;;; through si_safe_eval on the main thread. They read the recognizer's state
;;; from the variable the recognizer was stashed in rather than from the sender:
;;; UIKit's sender is an Objective-C argument, and not passing it is what keeps
;;; LispTarget's contract to a single string.

(defun on-pan ()
  "Drag to move A and B. Reported as a delta: the translation is zeroed here."
  (when *pan*
    (let ((delta (attractor-glue:pan-translation *pan* *view*)))
      (attractor-glue:reset-pan-translation *pan* *view*)
      ;; Small enough that a full swipe is a tour of the parameter space rather
      ;; than a jump across it.
      (incf *a* (* (car delta) 0.004d0))
      (incf *b* (* (cdr delta) 0.004d0))
      (redraw))))

(defun on-pinch ()
  "Pinch to move C and D, in opposite directions -- it makes the figure open
out rather than merely swell."
  (when *pinch*
    (let ((delta (- (attractor-glue:pinch-scale *pinch*) 1.0d0)))
      (attractor-glue:reset-pinch-scale *pinch*)
      (incf *c* (* delta 1.5d0))
      (decf *d* (* delta 1.5d0))
      (redraw))))

(defun install-gestures ()
  (setf *pan* (attractor-glue:add-recognizer
               *view* "UIPanGestureRecognizer" "(attractor::on-pan)"))
  (setf *pinch* (attractor-glue:add-recognizer
                 *view* "UIPinchGestureRecognizer" "(attractor::on-pinch)"))
  (attractor-glue:attach-recognizer *view* *pan*)
  (attractor-glue:attach-recognizer *view* *pinch*))

(defun start ()
  "Entry point. Runs on the main thread and must return: the run loop follows."
  (format t "~&ATTRACTOR: ~a ~a~%"
          (lisp-implementation-type) (lisp-implementation-version))
  ;; "returns void; self, _cmd, CGRect". The @ has to live here rather than in
  ;; the C, because C-INLINE reads @ as the start of its own syntax.
  (attractor-glue:install-view-class "v@:{CGRect={CGPoint=dd}{CGSize=dd}}")
  (setf *view* (attractor-glue:make-view))
  (attractor-glue:set-root-view *view*)
  (install-gestures)
  (let ((bounds (attractor-glue:view-bounds *view*)))
    (format t "ATTRACTOR: view is ~ax~a, ~d points~%"
            (round (car bounds)) (round (cdr bounds)) *points*))
  (format t "ATTRACTOR: drag for A and B, pinch for C and D.~%")
  (format t "ATTRACTOR: sly-connect to localhost 4005 and redefine STEP-POINT.~%")
  (finish-output))

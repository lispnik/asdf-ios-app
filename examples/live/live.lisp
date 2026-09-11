;;;; live.lisp -- what is on the screen, and what you are meant to replace.
;;;;
;;;; Three things are drawn: a caption, a canvas and a button. Each is backed
;;;; by one function -- CAPTION-TEXT, PAINT, ON-TAP -- declared NOTINLINE so
;;;; that a DEFUN sent from Emacs replaces what the phone runs. The rest is the
;;;; plumbing that makes that safe: everything exported dispatches itself onto
;;;; the main thread, because a SLY REPL evaluates on a slynk worker and UIKit
;;;; will not be touched from there.

(defpackage #:live
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit)
                    (#:rt #:ios-app-runtime))
  (:export #:start
           ;; the three functions to redefine
           #:paint #:on-tap #:caption-text
           ;; the API those redefinitions have to hand
           #:redraw #:say #:add-view #:remove-added-views
           #:fill-rect #:fill-ellipse #:stroke-line #:set-fill #:set-stroke
           #:main #:*canvas* #:*width* #:*height* #:*taps* #:*added*))

(in-package #:live)

(defvar *canvas* nil "The canvas view; drawRect: is PAINT.")
(defvar *caption* nil "The label above the canvas.")
(defvar *status* nil "The label at the bottom: slynk's state, and what SAY says.")
(defvar *button* nil)
(defvar *width* 0d0 "The canvas size, as of the last drawRect:.")
(defvar *height* 0d0)
(defvar *taps* 0 "How many times the button has been pressed.")
(defvar *added* '() "Views added from Emacs by ADD-VIEW, so they can be taken away again.")

;;; ------------------------------------------------------------------
;;; the main thread
;;;
;;; slynk evaluates on its own thread. Every exported function that touches
;;; UIKit goes through MAIN so that a redefinition typed into Emacs need not
;;; remember to. On the main thread already, it just calls.

(defmacro main (&body body)
  "Evaluate BODY on the main thread and return its values."
  `(rt:with-main-thread ,@body))

;;; ------------------------------------------------------------------
;;; the three functions
;;;
;;; NOTINLINE is not decoration. ECL compiles a call to a function in the same
;;; file as a direct C call; without the declamation a DEFUN from Emacs would
;;; replace the fdefinition and the view would keep calling the version that
;;; was compiled on the Mac, silently.

(declaim (notinline paint on-tap caption-text))

(defun caption-text ()
  "The caption. Redefine, then (LIVE:REDRAW)."
  "redefine LIVE:PAINT from Emacs")

(defun paint (width height)
  "Draw the canvas, WIDTH by HEIGHT, into the current context. Redefine, then
\(LIVE:REDRAW). The primitives below are all it takes: FILL-RECT, FILL-ELLIPSE,
STROKE-LINE, SET-FILL, SET-STROKE. Origin top-left, y down."
  (let ((step 36))
    (loop for y from 0 below height by step
          for row from 0
          do (loop for x from 0 below width by step
                   for column from 0
                   do (let ((phase (/ (+ row column) 14)))
                        (set-fill (+ 0.15 (* 0.35 (abs (sin phase))))
                                  (+ 0.20 (* 0.50 (abs (cos (* 1.3 phase)))))
                                  0.85)
                        (fill-ellipse (+ x 4) (+ y 4) (- step 8) (- step 8)))))))

(defun on-tap ()
  "What the button does. Redefine at will; it runs on the main thread."
  (incf *taps*)
  (say "tapped ~d time~:p -- now redefine LIVE:ON-TAP" *taps*))

;;; ------------------------------------------------------------------
;;; the API redefinitions have to hand

(defun redraw ()
  "Ask for a new frame: drawRect: calls PAINT again."
  (main
    (when *canvas*
      (objc:invoke *caption* "setText:" (caption-text))
      (objc:invoke *canvas* "setNeedsDisplay")))
  (values))

(defun say (control &rest args)
  "Show a line at the bottom of the screen, FORMAT-style."
  (let ((text (apply #'format nil control args)))
    (main (when *status* (objc:invoke *status* "setText:" text)))
    text))

(defun add-view (view &key (below *canvas*) (height 40))
  "Put VIEW on screen under BELOW, full width, HEIGHT tall. Returns VIEW.
Remembered, so REMOVE-ADDED-VIEWS can clear the experiment away."
  (main
    (let* ((root (ui:root-view))
           (safe (objc:invoke root "safeAreaLayoutGuide")))
      (objc:invoke root "addSubview:" view)
      (ui:pin view "topAnchor" below "bottomAnchor" 10)
      (ui:pin view "leadingAnchor" safe "leadingAnchor" 16)
      (ui:pin view "trailingAnchor" safe "trailingAnchor" -16)
      (ui:fix view "heightAnchor" height)
      (push view *added*)
      view)))

(defun remove-added-views ()
  (main
    (dolist (view *added*) (objc:invoke view "removeFromSuperview"))
    (setf *added* '()))
  (values))

;;; ------------------------------------------------------------------
;;; CoreGraphics, by name
;;;
;;; Looked up lazily: at load time on the Mac the app's frameworks are not
;;; linked, and an eager lookup would fail the build.

(defvar *functions* (make-hash-table :test #'equal))

(defun cg (name)
  (or (gethash name *functions*)
      (setf (gethash name *functions*)
            (si:find-foreign-symbol name :default :pointer-void 0))))

(defparameter +cgrect+ '(:struct (:m :double) (:m :double) (:m :double) (:m :double)))

(defun rect (x y width height)
  "A CGRect in foreign memory, for passing by value."
  (let ((r (si::allocate-foreign-data :void 32)))
    (si:foreign-data-set-elt r 0 :double (float x 1d0))
    (si:foreign-data-set-elt r 8 :double (float y 1d0))
    (si:foreign-data-set-elt r 16 :double (float width 1d0))
    (si:foreign-data-set-elt r 24 :double (float height 1d0))
    r))

(defvar *context* nil "The CGContext, for the duration of one drawRect:.")

(defun set-fill (red green blue &optional (alpha 1))
  (si:call-cfun (cg "CGContextSetRGBFillColor") :void
                '(:pointer-void :double :double :double :double)
                (list *context* (float red 1d0) (float green 1d0) (float blue 1d0) (float alpha 1d0))))

(defun set-stroke (red green blue &optional (alpha 1) (width 2))
  (si:call-cfun (cg "CGContextSetRGBStrokeColor") :void
                '(:pointer-void :double :double :double :double)
                (list *context* (float red 1d0) (float green 1d0) (float blue 1d0) (float alpha 1d0)))
  (si:call-cfun (cg "CGContextSetLineWidth") :void
                '(:pointer-void :double) (list *context* (float width 1d0))))

(defun fill-rect (x y width height)
  (si:call-cfun (cg "CGContextFillRect") :void
                (list :pointer-void +cgrect+) (list *context* (rect x y width height))))

(defun fill-ellipse (x y width height)
  "The ellipse inscribed in the rectangle."
  (si:call-cfun (cg "CGContextFillEllipseInRect") :void
                (list :pointer-void +cgrect+) (list *context* (rect x y width height))))

(defun stroke-line (x1 y1 x2 y2)
  (si:call-cfun (cg "CGContextMoveToPoint") :void '(:pointer-void :double :double)
                (list *context* (float x1 1d0) (float y1 1d0)))
  (si:call-cfun (cg "CGContextAddLineToPoint") :void '(:pointer-void :double :double)
                (list *context* (float x2 1d0) (float y2 1d0)))
  (si:call-cfun (cg "CGContextStrokePath") :void '(:pointer-void) (list *context*)))

;;; ------------------------------------------------------------------
;;; the canvas
;;;
;;; A UIView subclass whose drawRect: is Lisp. The CGRect arrives by value
;;; through a libffi closure ECL made at run time; no C was compiled for it.

(objc:define-objc-class canvas-view ()
  ()
  (:objc-class-name "LiveCanvasView")
  (:objc-superclass-name "UIView"))

(objc:define-objc-method ("drawRect:" :void)
    ((self canvas-view) (dirty cocoa:ns-rect))
  (declare (ignore dirty))
  ;; Nothing may unwind into UIKit. A PAINT that signals -- half-typed in
  ;; Emacs, sent early -- is reported at the bottom of the screen instead,
  ;; and the next REDRAW tries again.
  (handler-case
      (let* ((bounds (objc:invoke (objc:objc-object-pointer self) "bounds"))
             (*context* (si:call-cfun (cg "UIGraphicsGetCurrentContext") :pointer-void '() '())))
        (setf *width* (aref bounds 2)
              *height* (aref bounds 3))
        (paint *width* *height*))
    (serious-condition (condition)
      (say "PAINT signalled: ~a" condition))))

;;; ------------------------------------------------------------------
;;; the screen

(defun slynk-connections ()
  (let ((symbol (find-symbol "*CONNECTIONS*" "SLYNK")))
    (if (and symbol (boundp symbol)) (length (symbol-value symbol)) 0)))

(defun status-line ()
  (let ((port rt:*remote-repl-port*)
        (connections (slynk-connections)))
    (cond ((null port) "slynk did not start")
          ((zerop connections)
           (format nil "slynk on :~d -- iproxy ~d:~d, then M-x sly-connect" port port port))
          (t (format nil "Emacs is connected (~d)" connections)))))

(defun build-interface ()
  (let* ((root (ui:root-view))
         (safe (objc:invoke root "safeAreaLayoutGuide"))
         (caption (ui:new "UILabel"))
         (canvas (objc:alloc-init-object "LiveCanvasView"))
         (status (ui:new "UILabel"))
         (button (ui:system-button "tap")))
    (objc:invoke root "setBackgroundColor:" (ui:color 0.05 0.05 0.08))

    (objc:invoke caption "setText:" (caption-text))
    (objc:invoke caption "setTextColor:" (ui:color 0.9 0.9 0.95))
    (objc:invoke caption "setFont:" (ui:mono-font 15))
    (objc:invoke caption "setTextAlignment:" 1) ; NSTextAlignmentCenter
    (objc:invoke root "addSubview:" caption)

    (objc:invoke canvas "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke canvas "setBackgroundColor:" (ui:color 0.02 0.02 0.03))
    (objc:invoke (objc:invoke canvas "layer") "setCornerRadius:" 12d0)
    (objc:invoke canvas "setClipsToBounds:" t)
    (objc:invoke root "addSubview:" canvas)

    (objc:invoke status "setTextColor:" (ui:color 0.55 0.95 0.9))
    (objc:invoke status "setFont:" (ui:mono-font 12))
    (objc:invoke status "setNumberOfLines:" 3)
    (objc:invoke status "setTextAlignment:" 1)
    (objc:invoke root "addSubview:" status)

    (ui:on-tap button (lambda (sender)
                        (declare (ignore sender))
                        (handler-case (on-tap)
                          (serious-condition (c) (say "ON-TAP signalled: ~a" c)))))
    (objc:invoke root "addSubview:" button)

    (ui:pin caption "topAnchor" safe "topAnchor" 12)
    (ui:pin caption "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin caption "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin canvas "topAnchor" caption "bottomAnchor" 12)
    (ui:pin canvas "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin canvas "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin canvas "heightAnchor" canvas "widthAnchor")
    (ui:pin button "bottomAnchor" safe "bottomAnchor" -10)
    (ui:pin button "centerXAnchor" safe "centerXAnchor")
    (ui:fix button "heightAnchor" 40)
    (ui:pin status "bottomAnchor" button "topAnchor" -6)
    (ui:pin status "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin status "trailingAnchor" safe "trailingAnchor" -16)

    (setf *canvas* canvas *caption* caption *status* status *button* button)
    (values)))

(defun start ()
  "Entry point, on the main thread. slynk is already listening: %BOOT starts
it before this runs, so a mistake here is reachable from Emacs too."
  (objc:ensure-objc-initialized)
  (build-interface)
  (say (status-line))
  ;; The status line follows slynk: it changes the moment Emacs connects.
  ;; Made here, on the main thread, because an NSTimer is scheduled on the run
  ;; loop of the thread that makes it -- a slynk thread has none.
  (let ((last nil))
    (ui:after-every 1
      (lambda (timer)
        (declare (ignore timer))
        (let ((line (status-line)))
          (unless (equal line last)
            (setf last line)
            (objc:invoke *status* "setText:" line))))))
  (values))

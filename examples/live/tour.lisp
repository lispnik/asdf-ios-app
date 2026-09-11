;;;; tour.lisp -- open this in Emacs, connect to the phone, and send each form
;;;; with C-c C-c (or put point after it and C-x C-e). Watch the phone.
;;;;
;;;; Every form here is evaluated *on the phone*, by the ECL inside the app.
;;;; Nothing is rebuilt, nothing is reinstalled; the new definitions are
;;;; bytecode, compiled on the device, replacing native code compiled on the
;;;; Mac. Undo any of it by sending the original definition from live.lisp.

(in-package #:live)

;;; 1. Say something. SAY puts a line at the bottom of the screen; it goes to
;;;    the main thread by itself, as everything exported from LIVE does.

(say "hello from Emacs")

;;; 2. The caption is a function. Redefine it; REDRAW re-reads it.

(defun caption-text ()
  (format nil "~a, from Emacs" (machine-instance)))

(redraw)

;;; 3. The canvas is a function. PAINT gets the width and height and draws
;;;    into the current CoreGraphics context with the primitives LIVE exports:
;;;    SET-FILL, SET-STROKE, FILL-RECT, FILL-ELLIPSE, STROKE-LINE. Origin
;;;    top-left, y down.

(defun paint (width height)
  (let ((cx (/ width 2)) (cy (/ height 2)) (r (* 0.42 (min width height))))
    (set-fill 0.98 0.55 0.15)
    (fill-ellipse (- cx r) (- cy r) (* 2 r) (* 2 r))
    (set-stroke 1 1 1 0.9 3)
    (loop for i below 24
          for a = (* i (/ pi 12))
          do (stroke-line cx cy (+ cx (* r (cos a))) (+ cy (* r (sin a)))))))

(redraw)

;;; 4. A mistake is not fatal. Send this, then look at the bottom line: a
;;;    condition in drawRect: is caught before it can reach UIKit, reported,
;;;    and the next REDRAW after a fix draws again. Send step 3 again to fix.

(defun paint (width height)
  (declare (ignore width height))
  (error "not finished yet"))

(redraw)

;;; 5. State, and the button. A variable, a PAINT that reads it, and an
;;;    ON-TAP that changes it. Tap the button on the phone.

(defvar *angle* 0d0)

(defun paint (width height)
  (let ((cx (/ width 2)) (cy (/ height 2)) (r (* 0.42 (min width height))))
    (loop for i below 12
          for a = (+ *angle* (* i (/ pi 6)))
          for tint = (/ i 12)
          do (set-fill (+ 0.3 (* 0.7 tint)) (- 0.9 (* 0.6 tint)) 0.95)
             (fill-ellipse (+ cx (* r (cos a)) -14) (+ cy (* r (sin a)) -14) 28 28))
    (set-stroke 1 1 1 0.5 1)
    (stroke-line cx cy (+ cx (* r (cos *angle*))) (+ cy (* r (sin *angle*))))))

(defun on-tap ()
  (incf *angle* (/ pi 12))
  (redraw)
  (say "angle ~,2f" *angle*))

(redraw)

;;;    Tap the button on the phone -- or send this, which is what the button
;;;    does, from here. Either way it is the new definition that runs.

(main (on-tap))

;;; 6. Animation, from Emacs. An NSTimer is scheduled on the run loop of the
;;;    thread that makes it, and a slynk thread has no run loop -- so the
;;;    timer is made inside MAIN. Its callback then runs on the main thread,
;;;    where REDRAW is a plain call.

(defvar *timer* nil)

(setf *timer*
      (main (ui:after-every 1/30
              (lambda (timer)
                (declare (ignore timer))
                (incf *angle* 0.03)
                (redraw)))))

;;; ... and stop it.

(main (objc:invoke *timer* "invalidate"))

;;; 7. A control that did not exist when the app was built. A UISlider,
;;;    wired to a closure, placed under the canvas by ADD-VIEW. Drag it.

(add-view
 (main
   (let ((slider (ui:new "UISlider")))
     (objc:invoke slider "setMinimumValue:" 0.0)
     (objc:invoke slider "setMaximumValue:" (* 2 pi))
     (objc:invoke slider "setValue:" *angle*)
     (objc:invoke slider "addTarget:action:forControlEvents:"
                  (ui:action-target (lambda (sender)
                                      (setf *angle* (objc:invoke sender "value"))
                                      (redraw)))
                  "fire:"
                  4096)                 ; UIControlEventValueChanged
     slider)))

;;; 8. Look around. This is the image on the phone: its threads, its memory,
;;;    the device it is running on. (A device answers "iPhone", nothing more;
;;;    iOS stopped giving apps the owner's name for it. The simulator answers
;;;    with its model, which is how to tell the two apart.)

(mapcar #'mp:process-name (mp:all-processes))

(room)

(objc:ns-string-to-string
 (objc:invoke (objc:invoke "UIDevice" "currentDevice") "name"))

;;; 9. Anything UIKit, straight through objc. The view hierarchy, for one.

(main
  (labels ((walk (view depth)
             (format t "~&~v@t~a~%" (* 2 depth)
                     (objc:ns-string-to-string (objc:invoke view "description")))
             (let ((subviews (objc:invoke view "subviews")))
               (dotimes (i (objc:invoke subviews "count"))
                 (walk (objc:invoke subviews "objectAtIndex:" i) (1+ depth))))))
    (walk (ui:root-view) 0)))

;;; 10. Tidy up: the slider goes, the canvas is the built-in one again.

(remove-added-views)
(redraw)

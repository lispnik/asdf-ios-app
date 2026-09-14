;;;; ink.lisp -- PencilKit, with Lisp on the receiving end.
;;;;
;;;; PKCanvasView takes the finger or the pencil; its delegate is told after
;;;; every stroke. The delegate here is a Lisp class, and what it does with
;;;; the drawing is what PencilKit's Objective-C surface allows: read its
;;;; bounds, render it to an image, and keep its bytes. The strokes
;;;; themselves are Swift-only structures, which is why the spiral the app
;;;; starts with was drawn on the Mac by build.sh and shipped as a resource
;;;; rather than composed here.

(defpackage #:ink
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:load-spiral #:clear #:save))

(in-package #:ink)

(defvar *canvas* nil)
(defvar *preview* nil)
(defvar *caption* nil)
(defvar *changes* 0)

;;; ------------------------------------------------------------------
;;; the delegate: a Lisp class PencilKit tells

(objc:define-objc-class ink-delegate () ()
  (:objc-class-name "LispInkDelegate")
  (:objc-protocols "PKCanvasViewDelegate"))

(defun describe-drawing ()
  "Read what the Objective-C side of PencilKit offers: bounds and a picture."
  (let* ((drawing (objc:invoke *canvas* "drawing"))
         (bounds (objc:invoke drawing "bounds"))
         (bytes (objc:invoke (objc:invoke drawing "dataRepresentation") "length")))
    (if (zerop bytes)
        (progn (objc:invoke *caption* "setText:" "empty")
               (objc:invoke *preview* "setImage:" nil))
        (let ((image (objc:invoke drawing "imageFromRect:scale:" bounds 2d0)))
          (objc:invoke *preview* "setImage:" image)
          (objc:invoke *caption* "setText:"
                       (format nil "~d change~:p; bounds ~,0f×~,0f at (~,0f, ~,0f); ~:d bytes"
                               *changes* (aref bounds 2) (aref bounds 3)
                               (aref bounds 0) (aref bounds 1) bytes))))
    (format t "INK: ~a~%" (objc:ns-string-to-string (objc:invoke *caption* "text")))
    (finish-output)))

(objc:define-objc-method ("canvasViewDrawingDidChange:" :void)
    ((self ink-delegate) (canvas objc:objc-object-pointer))
  (declare (ignore canvas))
  (incf *changes*)
  (describe-drawing))

;;; ------------------------------------------------------------------
;;; loading, clearing, keeping

(defun load-spiral ()
  "The drawing build.sh made, from the bundle."
  (let* ((path (ios-app-runtime:bundle-resource "spiral.drawing"))
         (data (objc:invoke "NSData" "dataWithContentsOfFile:" (namestring path)))
         (drawing (objc:invoke (objc:invoke "PKDrawing" "alloc") "initWithData:error:" data nil)))
    (objc:invoke *canvas* "setDrawing:" drawing)
    (describe-drawing)))

(defun clear ()
  (objc:invoke *canvas* "setDrawing:" (objc:alloc-init-object "PKDrawing"))
  (describe-drawing))

(defun save ()
  "The drawing's bytes to Documents, where HOME points; loadable again."
  (let ((path (namestring (merge-pathnames "kept.drawing" (user-homedir-pathname)))))
    (objc:invoke (objc:invoke (objc:invoke *canvas* "drawing") "dataRepresentation")
                 "writeToFile:atomically:" path t)
    (format t "INK: saved ~a~%" path)
    (finish-output)
    path))

;;; ------------------------------------------------------------------
;;; the screen

(defvar *delegate* nil)

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
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Ink, read by Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "Draw on the canvas. After every stroke PencilKit tells a Lisp delegate, which reads the bounds and renders what you drew." :size 13))
    ;; The canvas.
    (setf *canvas* (ui:new "PKCanvasView"))
    (objc:invoke *canvas* "setDrawingPolicy:" 2)         ; any input, finger included
    (objc:invoke *canvas* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *canvas* "layer") "setCornerRadius:" 12)
    (objc:invoke column "addArrangedSubview:" *canvas*)
    (ui:fix *canvas* "heightAnchor" 360)
    (ui:pin *canvas* "widthAnchor" column "widthAnchor")
    (setf *delegate* (ui:keep (make-instance 'ink-delegate)))
    (objc:invoke *canvas* "setDelegate:" (objc:objc-object-pointer *delegate*))
    ;; What Lisp sees of it.
    (setf *caption* (label "" :size 12))
    (objc:invoke *caption* "setFont:" (ui:mono-font 11))
    (objc:invoke column "addArrangedSubview:" *caption*)
    (setf *preview* (ui:new "UIImageView"))
    (objc:invoke *preview* "setContentMode:" 1)         ; aspect fit
    (objc:invoke *preview* "setBackgroundColor:" (ui:system-color "tertiarySystemBackground"))
    (objc:invoke column "addArrangedSubview:" *preview*)
    (ui:fix *preview* "heightAnchor" 140)
    ;; Buttons.
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 16)
    (dolist (entry (list (cons "Spiral" #'load-spiral) (cons "Clear" #'clear) (cons "Save" #'save)))
      (let ((button (ui:system-button (car entry))))
        (ui:on-tap button (let ((function (cdr entry))) (lambda (sender) (declare (ignore sender)) (funcall function))))
        (objc:invoke row "addArrangedSubview:" button)))
    (objc:invoke column "addArrangedSubview:" row)
    (load-spiral)
    (values)))

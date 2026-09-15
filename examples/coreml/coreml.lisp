;;;; coreml.lisp -- a model, asked questions from Lisp.
;;;;
;;;; Core ML runs a model the app ships. This one is small on purpose --
;;;; a boosted-tree regressor, trained by build.sh on the Mac with Create ML
;;;; to give the area of a triangle from its base and height, plus noise --
;;;; because the model is not the point. The point is the round trip: the
;;;; compiled model loaded from the bundle, inputs handed over as a feature
;;;; provider built from Lisp numbers, the prediction read back as a
;;;; feature value, and the exact answer computed beside it in Lisp so the
;;;; error is visible. Everything a real model needs, with a toy inside.

(defpackage #:coreml
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:predict-area #:model))

(in-package #:coreml)

(defvar *model* nil)
(defvar *text* nil)
(defvar *status* nil)

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "COREML: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

(defun model ()
  "The compiled model, loaded once from the bundle."
  (or *model*
      (let* ((url (objc:invoke "NSURL" "fileURLWithPath:"
                               (namestring (ios-app-runtime:bundle-resource "Area.mlmodelc"))))
             (model (objc:invoke "MLModel" "modelWithContentsOfURL:error:" url nil)))
        (when (cffi:null-pointer-p model) (error "the model did not load"))
        (setf *model* (ui:keep model)))))

(defun feature (double)
  (objc:invoke "MLFeatureValue" "featureValueWithDouble:" (float double 1d0)))

(defun predict-area (base height)
  "The model's answer for BASE and HEIGHT, and the exact one."
  (let* ((inputs (objc:invoke "NSMutableDictionary" "dictionary")))
    (objc:invoke inputs "setObject:forKey:" (feature base) "base")
    (objc:invoke inputs "setObject:forKey:" (feature height) "height")
    (let* ((provider (objc:invoke (objc:invoke (objc:invoke "MLDictionaryFeatureProvider" "alloc")
                                               "initWithDictionary:error:" inputs nil)
                                  "autorelease"))
           (output (objc:invoke (model) "predictionFromFeatures:error:" provider nil)))
      (when (cffi:null-pointer-p output) (error "no prediction"))
      (values (objc:invoke (objc:invoke output "featureValueForName:" "area") "doubleValue")
              (* 0.5 base height)))))

(defun describe-model ()
  (let* ((description (objc:invoke (model) "modelDescription"))
         (inputs (objc:invoke description "inputDescriptionsByName"))
         (outputs (objc:invoke description "outputDescriptionsByName"))
         (metadata (objc:invoke description "metadata")))
    (format nil "inputs ~{~a~^, ~}; outputs ~{~a~^, ~}; ~a"
            (loop for i below (objc:invoke (objc:invoke inputs "allKeys") "count")
                  collect (objc:ns-string-to-string (objc:invoke (objc:invoke inputs "allKeys") "objectAtIndex:" i)))
            (loop for i below (objc:invoke (objc:invoke outputs "allKeys") "count")
                  collect (objc:ns-string-to-string (objc:invoke (objc:invoke outputs "allKeys") "objectAtIndex:" i)))
            (let ((d (objc:invoke metadata "objectForKey:" "MLModelDescriptionKey")))
              (if (cffi:null-pointer-p d) "" (objc:ns-string-to-string d))))))

(defparameter +questions+ '((3 4) (10 10) (7.5 2) (19 18) (1 1) (12.5 6.4)))

(defun ask-everything ()
  ;; Columns under a header, forty characters wide: a phone shows about
  ;; fifty of this font across, and a row that names each column wrapped.
  (let ((lines (cons (format nil "~6@a ~7@a ~8@a ~8@a ~7@a" "base" "height" "model" "exact" "off by")
                     (loop for (base height) in +questions+
                           collect (multiple-value-bind (predicted exact) (predict-area base height)
                                     (format nil "~6,1f ~7,1f ~8,2f ~8,2f ~7,2f"
                                             base height predicted exact (abs (- predicted exact))))))))
    (objc:invoke *text* "setText:" (format nil "~{~a~%~}" lines))
    (dolist (line lines) (format t "COREML: ~a~%" line))
    (finish-output)
    lines))

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
         (column (ui:new "UIStackView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "A model, asked from Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "A Core ML regressor trained on the Mac by Create ML and shipped compiled: loaded from the bundle, fed feature values made of Lisp numbers, its predictions beside the exact answers." :size 13))
    (setf *status* (label "" :size 12 :lines 3))
    (objc:invoke *status* "setFont:" (ui:mono-font 11))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *text* (ui:new "UITextView"))
    (objc:invoke *text* "setEditable:" nil)
    (objc:invoke *text* "setFont:" (ui:mono-font 12))
    (objc:invoke *text* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *text* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *text*)
    (ui:fix *text* "heightAnchor" 200)
    (handler-case
        (progn (say "~a" (describe-model))
               (ask-everything))
      (error (condition) (say "Core ML failed: ~a" condition)))
    (values)))

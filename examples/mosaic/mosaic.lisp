;;;; mosaic.lisp -- a collection view whose layout is decided in Lisp.
;;;;
;;;; UICollectionViewDelegateFlowLayout is the protocol with the awkward
;;;; methods: the layout asks the delegate for a CGSize per item and a
;;;; UIEdgeInsets per section, both structures returned by value. A Lisp
;;;; method returning a structure is the hardest thing the bridge does in
;;;; the inbound direction, and here it does it for every cell, on the
;;;; phone, through a libffi closure -- no C compiler anywhere.
;;;;
;;;; The items are the packages of the running image, each cell's area in
;;;; proportion to how many symbols the package holds, which makes the
;;;; mosaic a picture of the image looking at itself.

(defpackage #:mosaic
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:*items*))

(in-package #:mosaic)

;;; ------------------------------------------------------------------
;;; the items

(defun package-symbol-count (package)
  (let ((count 0))
    (do-symbols (s package) (declare (ignore s)) (incf count))
    count))

(defun items ()
  "(name count side) for every package, largest first; SIDE is the cell's
edge in points, from the square root of the count so that area follows it."
  (let* ((rows (loop for package in (list-all-packages)
                     collect (list (package-name package) (package-symbol-count package))))
         (largest (reduce #'max rows :key #'second :initial-value 1)))
    (sort (loop for (name count) in rows
                collect (list name count (+ 40 (round (* 76 (sqrt (/ count largest)))))))
          #'> :key #'second)))

(defvar *items* '())

;;; ------------------------------------------------------------------
;;; the structures the layout wants

;;; CGSize is cocoa:ns-size here, as it is in the runtime.  UIEdgeInsets
;;; is not in the COCOA package, so it is declared: four doubles, in the
;;; order UIKit lays them out.
(objc:define-objc-struct (ui-edge-insets (:foreign-name "UIEdgeInsets"))
  (:top :double)
  (:left :double)
  (:bottom :double)
  (:right :double))

;;; ------------------------------------------------------------------
;;; data source and delegate, one Lisp class

(objc:define-objc-class mosaic-source () () (:objc-class-name "LispMosaicSource"))

(objc:define-objc-method ("collectionView:numberOfItemsInSection:" (:signed :long-long))
    ((self mosaic-source) (view objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore view section))
  (length *items*))

(defun hue-for (index)
  (/ (mod (* index 47) 360) 360d0))

(objc:define-objc-method ("collectionView:cellForItemAtIndexPath:" objc:objc-object-pointer)
    ((self mosaic-source) (view objc:objc-object-pointer) (path objc:objc-object-pointer))
  (let* ((index (objc:invoke path "item"))
         (cell (objc:invoke view "dequeueReusableCellWithReuseIdentifier:forIndexPath:" "tile" path))
         (content (objc:invoke cell "contentView")))
    (destructuring-bind (name count side) (nth index *items*)
      (declare (ignore side))
      ;; One label per cell, made the first time the cell is used.
      (let ((label (objc:invoke content "viewWithTag:" 7)))
        (when (cffi:null-pointer-p label)
          (setf label (ui:new "UILabel"))
          (objc:invoke label "setTag:" 7)
          (objc:invoke label "setNumberOfLines:" 0)
          (objc:invoke label "setTextAlignment:" 1)
          (objc:invoke label "setTextColor:" (ui:color 1 1 1))
          (objc:invoke content "addSubview:" label)
          (ui:pin label "leadingAnchor" content "leadingAnchor" 4)
          (ui:pin label "trailingAnchor" content "trailingAnchor" -4)
          (ui:pin label "centerYAnchor" content "centerYAnchor"))
        (objc:invoke label "setFont:" (ui:font (if (> count 200) 12 10) 0.4))
        (objc:invoke label "setText:" (format nil "~a~%~d" name count))))
    (objc:invoke content "setBackgroundColor:"
                 (objc:invoke "UIColor" "colorWithHue:saturation:brightness:alpha:"
                              (hue-for index) 0.55 0.8 1.0))
    (objc:invoke (objc:invoke content "layer") "setCornerRadius:" 8)
    cell))

;;; The flow layout delegate: structures out, by value.

(objc:define-objc-method ("collectionView:layout:sizeForItemAtIndexPath:" cocoa:ns-size)
    ((self mosaic-source) (view objc:objc-object-pointer) (layout objc:objc-object-pointer)
     (path objc:objc-object-pointer))
  (declare (ignore view layout))
  (let ((side (third (nth (objc:invoke path "item") *items*))))
    (vector side side)))

(defvar *insets* nil
  "Foreign memory for one UIEdgeInsets, allocated on first use -- not at load
time, which runs on the Mac during the native pass -- and reused: the bridge
copies a returned structure out before the method's caller sees it.")

(objc:define-objc-method ("collectionView:layout:insetForSectionAtIndex:" (:struct ui-edge-insets))
    ((self mosaic-source) (view objc:objc-object-pointer) (layout objc:objc-object-pointer)
     (section (:signed :long-long)))
  (declare (ignore view layout section))
  ;; A declared structure is returned as a pointer to its bytes.  The Cocoa
  ;; ones, ns-size and ns-rect, may be vectors; anything declared with
  ;; DEFINE-OBJC-STRUCT is filled in foreign memory, which is what the
  ;; LispWorks manual's own example does too.
  (unless *insets*
    (setf *insets* (cffi:foreign-alloc :double :count 4)))
  (loop for value in '(8d0 0d0 8d0 0d0) for i from 0
        do (setf (cffi:mem-aref *insets* :double i) value))
  *insets*)

(objc:define-objc-method ("collectionView:layout:minimumInteritemSpacingForSectionAtIndex:" :double)
    ((self mosaic-source) (view objc:objc-object-pointer) (layout objc:objc-object-pointer)
     (section (:signed :long-long)))
  (declare (ignore view layout section))
  6d0)

(objc:define-objc-method ("collectionView:layout:minimumLineSpacingForSectionAtIndex:" :double)
    ((self mosaic-source) (view objc:objc-object-pointer) (layout objc:objc-object-pointer)
     (section (:signed :long-long)))
  (declare (ignore view layout section))
  6d0)

;;; ------------------------------------------------------------------
;;; the screen

(defvar *source* nil)

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font size))
    (objc:invoke label "setNumberOfLines:" lines)
    label))

(defun start ()
  (objc:ensure-objc-initialized)
  (setf *items* (items))
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView"))
         (layout (objc:alloc-init-object "UICollectionViewFlowLayout"))
         (view (objc:invoke (objc:invoke (objc:invoke "UICollectionView" "alloc")
                                         "initWithFrame:collectionViewLayout:"
                                         (vector 0d0 0d0 10d0 10d0) layout)
                            "autorelease")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 8)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" 0)
    (objc:invoke column "addArrangedSubview:" (label "The image, as a mosaic" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label (format nil "~d packages; each tile's area is its symbol count. Sizes and insets come from a Lisp delegate, as CGSize and UIEdgeInsets by value." (length *items*)) :size 13))
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke view "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke view "registerClass:forCellWithReuseIdentifier:"
                 (objc:invoke "UICollectionViewCell" "class") "tile")
    (setf *source* (ui:keep (make-instance 'mosaic-source)))
    (objc:invoke view "setDataSource:" (objc:objc-object-pointer *source*))
    (objc:invoke view "setDelegate:" (objc:objc-object-pointer *source*))
    (objc:invoke column "addArrangedSubview:" view)
    (format t "MOSAIC: ~d packages, largest ~a~%" (length *items*) (first *items*))
    (finish-output)
    (values)))

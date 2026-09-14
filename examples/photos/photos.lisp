;;;; photos.lisp -- the photo library, from Lisp.
;;;;
;;;; PhotoKit is permission gated and block driven, and it has two doors.
;;;; PHPickerViewController opens the library in a system sheet and needs
;;;; no permission at all: the user picks, and only the picks reach the
;;;; app, each through an item provider's completion block. Adding needs
;;;; add-only permission, asked for through a block, and the addition is a
;;;; block PhotoKit runs inside a transaction. All of those are Lisp
;;;; closures here. The picture that gets added is drawn in Lisp, pixel by
;;;; pixel, into a byte array that becomes a CGImage: no drawing API, just
;;;; numbers.
;;;;
;;;; Full library access would let the app fetch every asset itself; the
;;;; picker was chosen because on iOS 26 that access cannot be granted from
;;;; the command line -- `simctl privacy grant photos` leaves the prompt in
;;;; place -- while add-only can, and the picker needs none.

(defpackage #:photos
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:refresh #:add-picture))

(in-package #:photos)

(defvar *grid* nil)
(defvar *status* nil)
(defvar *thumbnails* '())

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "PHOTOS: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

;;; ------------------------------------------------------------------
;;; authorisation

(objc:define-objc-block-type status-reply :void ((:signed :long-long)))

(defparameter +authorized+ 3)
(defparameter +limited+ 5)
(defparameter +add-only+ 1 "PHAccessLevelAddOnly")

(defun with-add-authorization (function)
  "Call FUNCTION on the main thread once the library may be added to."
  (objc:with-objc-block (reply 'status-reply
                               (lambda (status)
                                 (ios-app-runtime:on-main
                                  (lambda ()
                                    (if (member status (list +authorized+ +limited+))
                                        (funcall function)
                                        (say "adding to the library refused (status ~d)" status))))))
    (objc:invoke "PHPhotoLibrary" "requestAuthorizationForAccessLevel:handler:" +add-only+ reply)))

;;; ------------------------------------------------------------------
;;; the picker, and what it hands over

(objc:define-objc-class picker-delegate () ()
  (:objc-class-name "LispPickerDelegate")
  (:objc-protocols "PHPickerViewControllerDelegate"))

(objc:define-objc-block-type object-loaded :void (objc:objc-object-pointer objc:objc-object-pointer))

(defvar *loaders* '() "Kept until the next pick.")

(defun show-thumbnail (image index)
  (let ((view (ui:new "UIImageView"))
        (row (floor index 3)) (column (mod index 3))
        (side 106))
    (objc:invoke view "setImage:" image)
    (objc:invoke view "setContentMode:" 2)
    (objc:invoke view "setClipsToBounds:" t)
    (objc:invoke (objc:invoke view "layer") "setCornerRadius:" 8)
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" t)
    (objc:invoke view "setFrame:" (vector (float (* column (+ side 8)) 1d0) (float (* row (+ side 8)) 1d0)
                                          (float side 1d0) (float side 1d0)))
    (objc:invoke *grid* "addSubview:" view)
    (push view *thumbnails*)))

(objc:define-objc-method ("picker:didFinishPicking:" :void)
    ((self picker-delegate) (picker objc:objc-object-pointer) (results objc:objc-object-pointer))
  (objc:invoke picker "dismissViewControllerAnimated:completion:" t nil)
  (dolist (view *thumbnails*) (objc:invoke view "removeFromSuperview"))
  (setf *thumbnails* '() *loaders* '())
  (let ((count (objc:invoke results "count")))
    (say "~d picked" count)
    (dotimes (i (min count 12))
      (let ((provider (objc:invoke (objc:invoke results "objectAtIndex:" i) "itemProvider"))
            (index i))
        ;; The image arrives later, through this block, off the main thread.
        (let ((block (objc:make-objc-block
                      'object-loaded
                      (lambda (object error)
                        (declare (ignore error))
                        (unless (cffi:null-pointer-p object)
                          (ios-app-runtime:on-main (lambda () (show-thumbnail object index))))))))
          (push block *loaders*)
          (objc:invoke provider "loadObjectOfClass:completionHandler:" (objc:invoke "UIImage" "class") block))))))

(defvar *picker-delegate* nil)

(defun pick ()
  "The system's picker, over the app: no permission needed."
  (let* ((configuration (objc:alloc-init-object "PHPickerConfiguration"))
         (picker (objc:invoke (objc:invoke (objc:invoke "PHPickerViewController" "alloc")
                                           "initWithConfiguration:" configuration)
                              "autorelease")))
    (objc:invoke configuration "setSelectionLimit:" 6)
    (objc:invoke configuration "setFilter:" (objc:invoke "PHPickerFilter" "imagesFilter"))
    (setf *picker-delegate* (ui:keep (make-instance 'picker-delegate)))
    (objc:invoke picker "setDelegate:" (objc:objc-object-pointer *picker-delegate*))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" picker t nil)))

;;; ------------------------------------------------------------------
;;; a picture drawn in Lisp, added to the library

(defun lisp-image (&key (size 256))
  "A UIImage of a pattern computed here: interference rings, in RGBA bytes."
  (let* ((bytes (* size size 4))
         (buffer (cffi:foreign-alloc :uint8 :count bytes)))
    (dotimes (y size)
      (dotimes (x size)
        (let* ((i (* 4 (+ (* y size) x)))
               (d1 (sqrt (+ (expt (- x 90) 2) (expt (- y 100) 2))))
               (d2 (sqrt (+ (expt (- x 170) 2) (expt (- y 150) 2))))
               (v (* 0.5 (+ 1 (* (sin (/ d1 6)) (sin (/ d2 6)))))))
          (setf (cffi:mem-aref buffer :uint8 i) (round (* 255 v))
                (cffi:mem-aref buffer :uint8 (+ i 1)) (round (* 255 (- 1 v) 0.6))
                (cffi:mem-aref buffer :uint8 (+ i 2)) (round (* 255 (* 0.4 (+ 0.5 (* 0.5 (cos (/ d1 9)))))))
                (cffi:mem-aref buffer :uint8 (+ i 3)) 255))))
    (let* ((data (objc:invoke "NSData" "dataWithBytes:length:" buffer bytes))
           (provider (si:call-cfun (cffi:foreign-symbol-pointer "CGDataProviderCreateWithCFData")
                                   :pointer-void '(:pointer-void) (list data)))
           (space (si:call-cfun (cffi:foreign-symbol-pointer "CGColorSpaceCreateDeviceRGB")
                                :pointer-void '() '()))
           ;; kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big = 1 | 4<<12
           (image (si:call-cfun (cffi:foreign-symbol-pointer "CGImageCreate") :pointer-void
                                '(:unsigned-long :unsigned-long :unsigned-long :unsigned-long :unsigned-long
                                  :pointer-void :unsigned-int :pointer-void :pointer-void :int :int)
                                (list size size 8 32 (* 4 size) space (logior 1 (ash 4 12)) provider
                                      (cffi:null-pointer) 0 0))))
      (cffi:foreign-free buffer)
      (objc:invoke "UIImage" "imageWithCGImage:" image))))

(objc:define-objc-block-type change-block :void ())
(objc:define-objc-block-type change-completion :void (objc:objc-c++-bool objc:objc-object-pointer))

(defun add-picture ()
  "Draw the pattern and add it to the library, inside PhotoKit's transaction."
  ;; Kept: the change block runs later, on PhotoKit's queue, after the
  ;; autorelease pool that made the image has drained.  Without this the
  ;; block's UIImage is gone and PhotoKit faults retaining it -- measured.
  (let ((image (ui:keep (lisp-image))))
    (objc:with-objc-block (changes 'change-block
                                   (lambda ()
                                     (objc:invoke "PHAssetChangeRequest" "creationRequestForAssetFromImage:" image)))
      (objc:with-objc-block (done 'change-completion
                                  (lambda (success error)
                                    (ios-app-runtime:on-main
                                     (lambda ()
                                       (ui:unkeep image)
                                       (if success
                                           (say "added a picture drawn in Lisp; find it with Choose")
                                           (say "could not add: ~a"
                                                (objc:ns-string-to-string (objc:invoke error "localizedDescription"))))))))
        (objc:invoke (objc:invoke "PHPhotoLibrary" "sharedPhotoLibrary")
                     "performChanges:completionHandler:" changes done)))))

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
         (row (ui:new "UIStackView"))
         (choose (ui:system-button "Choose photos"))
         (button (ui:system-button "Add one drawn in Lisp")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "The photo library, from Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "The system picker, needing no permission, hands picks to a Lisp delegate, each loaded through a block; a picture computed pixel by pixel in Lisp is added inside PhotoKit's change block." :size 13))
    (setf *status* (label "" :size 12))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *grid* (ui:new "UIView"))
    (objc:invoke column "addArrangedSubview:" *grid*)
    (ui:fix *grid* "heightAnchor" 448)
    (ui:pin *grid* "widthAnchor" column "widthAnchor")
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 16)
    (ui:on-tap choose (lambda (sender) (declare (ignore sender)) (pick)))
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (with-add-authorization #'add-picture)))
    (objc:invoke row "addArrangedSubview:" choose)
    (objc:invoke row "addArrangedSubview:" button)
    (objc:invoke column "addArrangedSubview:" row)
    (say "choose some photos, or add one")
    ;; PHOTOS_ADD=1 adds the picture at launch; PHOTOS_PICK=1 opens the
    ;; picker, for the picture of it.
    (when (ext:getenv "PHOTOS_ADD") (with-add-authorization #'add-picture))
    (when (ext:getenv "PHOTOS_PICK")
      (ui:after-every 1.0 (lambda (timer) (objc:invoke timer "invalidate") (pick)) :repeats nil))
    (values)))

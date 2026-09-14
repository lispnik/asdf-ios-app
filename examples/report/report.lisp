;;;; report.lisp -- a PDF from Lisp, three frameworks in one flow.
;;;;
;;;; UIGraphicsPDFRenderer runs a block per document, and inside it the
;;;; ordinary drawing API works: strings draw themselves with attributes,
;;;; paths fill. The block is a Lisp closure and the data is Lisp's, so
;;;; the report is written by Lisp in every sense. Quick Look then shows
;;;; the file through a data source that is a Lisp class, and the share
;;;; sheet offers it to whatever the phone has.

(defpackage #:report
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:write-report #:preview #:share))

(in-package #:report)

(defvar *status* nil)
(defvar *path* nil)

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "REPORT: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

;;; ------------------------------------------------------------------
;;; the data: the image looking at itself

(defun package-rows ()
  "The eight largest packages: (name symbol-count)."
  (let ((rows (loop for package in (list-all-packages)
                    collect (list (package-name package)
                                  (let ((n 0)) (do-symbols (s package) (declare (ignore s)) (incf n)) n)))))
    (subseq (sort rows #'> :key #'second) 0 (min 8 (length rows)))))

;;; ------------------------------------------------------------------
;;; drawing, inside the renderer's block

(defun attributes (size &key bold (grey 0.1))
  (let ((dictionary (objc:invoke "NSMutableDictionary" "dictionary")))
    (objc:invoke dictionary "setObject:forKey:" (if bold (ui:bold-font size) (ui:font size)) "NSFont")
    (objc:invoke dictionary "setObject:forKey:" (ui:color grey grey grey) "NSColor")
    dictionary))

(defun draw-text (text x y size &key bold (grey 0.1))
  (objc:invoke (objc:invoke "NSString" "stringWithString:" text)
               "drawAtPoint:withAttributes:" (vector x y) (attributes size :bold bold :grey grey)))

(defun draw-report (context)
  "One page: a title, a bar chart of the packages, and a footer."
  (objc:invoke context "beginPage")
  (draw-text "The image, as a report" 48 48 26 :bold t)
  (draw-text (format nil "~a ~a, ~d packages, written on the phone by Lisp"
                     (lisp-implementation-type) (lisp-implementation-version)
                     (length (list-all-packages)))
             48 84 11 :grey 0.4)
  (let* ((rows (package-rows))
         (largest (second (first rows)))
         (top 130) (left 48) (width 480) (row-height 34))
    (loop for (name count) in rows
          for i from 0
          for y = (+ top (* i row-height))
          for bar = (* width (/ count largest))
          do (let ((path (objc:invoke "UIBezierPath" "bezierPathWithRoundedRect:cornerRadius:"
                                      (vector left (+ y 14) bar 14) 4d0))
                   (hue (/ (mod (* i 47) 360) 360d0)))
               (objc:invoke (objc:invoke "UIColor" "colorWithHue:saturation:brightness:alpha:" hue 0.6 0.85 1.0) "setFill")
               (objc:invoke path "fill")
               (draw-text name left y 11 :bold t)
               (draw-text (format nil "~:d symbols" count) (+ left bar 8) (+ y 14) 10 :grey 0.35)))
    (draw-text "Drawn inside UIGraphicsPDFRenderer's actions block, which is a Lisp closure."
               48 (+ top (* (length rows) row-height) 30) 10 :grey 0.5)))

(objc:define-objc-block-type pdf-actions :void (objc:objc-object-pointer))

(defun write-report ()
  "The PDF to Documents; returns its path."
  (let* ((path (namestring (merge-pathnames "report.pdf" (user-homedir-pathname))))
         (renderer (objc:invoke (objc:invoke (objc:invoke "UIGraphicsPDFRenderer" "alloc")
                                             "initWithBounds:" (vector 0 0 612 792))
                                "autorelease")))
    (objc:with-objc-block (actions 'pdf-actions (lambda (context) (draw-report context)))
      (let ((data (objc:invoke renderer "PDFDataWithActions:" actions)))
        (objc:invoke data "writeToFile:atomically:" path t)
        (setf *path* path)
        (say "wrote ~a, ~:d bytes" (file-namestring path) (objc:invoke data "length"))))
    path))

;;; ------------------------------------------------------------------
;;; Quick Look, with a Lisp data source

(objc:define-objc-class preview-source () ()
  (:objc-class-name "LispPreviewSource")
  (:objc-protocols "QLPreviewControllerDataSource"))

(objc:define-objc-method ("numberOfPreviewItemsInPreviewController:" (:signed :long-long))
    ((self preview-source) (controller objc:objc-object-pointer))
  (declare (ignore controller))
  1)

(objc:define-objc-method ("previewController:previewItemAtIndex:" objc:objc-object-pointer)
    ((self preview-source) (controller objc:objc-object-pointer) (index (:signed :long-long)))
  (declare (ignore controller index))
  ;; An NSURL is a QLPreviewItem.
  (objc:invoke "NSURL" "fileURLWithPath:" *path*))

(defvar *source* nil)

(defun preview ()
  (unless *path* (write-report))
  (let ((controller (objc:alloc-init-object "QLPreviewController")))
    (setf *source* (ui:keep (make-instance 'preview-source)))
    (objc:invoke controller "setDataSource:" (objc:objc-object-pointer *source*))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" controller t nil)
    (say "previewing ~a" (file-namestring *path*))))

(defun share ()
  (unless *path* (write-report))
  (let ((sheet (objc:invoke (objc:invoke (objc:invoke "UIActivityViewController" "alloc")
                                         "initWithActivityItems:applicationActivities:"
                                         (vector (objc:invoke "NSURL" "fileURLWithPath:" *path*)) nil)
                            "autorelease")))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" sheet t nil)
    (say "sharing ~a" (file-namestring *path*))))

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
    (objc:invoke column "addArrangedSubview:" (label "A report written by Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "UIGraphicsPDFRenderer draws it inside a block that is a Lisp closure; Quick Look previews it through a Lisp data source; the share sheet offers it." :size 13))
    (setf *status* (label "" :size 12 :lines 2))
    (objc:invoke column "addArrangedSubview:" *status*)
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 16)
    (dolist (entry (list (cons "Write" #'write-report) (cons "Preview" #'preview) (cons "Share" #'share)))
      (let ((button (ui:system-button (car entry))))
        (ui:on-tap button (let ((function (cdr entry))) (lambda (sender) (declare (ignore sender)) (funcall function))))
        (objc:invoke row "addArrangedSubview:" button)))
    (objc:invoke column "addArrangedSubview:" row)
    (write-report)
    ;; REPORT_SHOW=preview or =share opens that at launch, for the picture.
    (let ((show (ext:getenv "REPORT_SHOW")))
      (ui:after-every 0.5 (lambda (timer) (objc:invoke timer "invalidate")
                            (cond ((equal show "preview") (preview))
                                  ((equal show "share") (share))))
                      :repeats nil))
    (values)))

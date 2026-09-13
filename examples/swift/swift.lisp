;;;; swift.lisp -- three frameworks Objective-C cannot see, from Lisp.
;;;;
;;;; CryptoKit, Swift Charts and FoundationModels publish no Objective-C
;;;; classes at all: measured with objc:class-selectors, they are empty from
;;;; here. LispSwift.swift gives each a small @objc surface, build.sh makes
;;;; that a framework, and swift.asd embeds it. After that, everything on this
;;;; side is objc:invoke -- the same calls as any UIKit class, aimed at
;;;; classes that happen to be written in Swift.
;;;;
;;;; What the screen shows: a SwiftUI bar chart of data computed in Lisp,
;;;; hosted as a child view controller; the CryptoKit results as text; a
;;;; button that recomputes the data and swaps the chart; and whether the
;;;; on-device language model is available, which on a simulator it is not.

(defpackage #:swift-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:new-data #:sha256 #:hmac-sha256 #:seal #:open-sealed
           #:bar-chart-png #:language-model-availability))

(in-package #:swift-ios)

;;; ------------------------------------------------------------------
;;; the Swift classes, as Lisp functions

(defun swift-string (pointer)
  "A Lisp string from an NSString the Swift side returned, or NIL for nil."
  (if (cffi:null-pointer-p pointer) nil (objc:ns-string-to-string pointer)))

(defun sha256 (string)
  "The SHA-256 of STRING's UTF-8, as hex, from CryptoKit."
  (swift-string (objc:invoke "LispCrypto" "sha256:" string)))

(defun hmac-sha256 (string key)
  (swift-string (objc:invoke "LispCrypto" "hmac:key:" string key)))

(defun random-key ()
  (swift-string (objc:invoke "LispCrypto" "randomKey")))

(defun seal (string key)
  "STRING sealed with ChaCha20-Poly1305 under KEY, base64."
  (swift-string (objc:invoke "LispCrypto" "seal:key:" string key)))

(defun open-sealed (sealed key)
  "What SEAL sealed, or NIL if KEY is wrong or SEALED was altered."
  (swift-string (objc:invoke "LispCrypto" "open:key:" sealed key)))

(defun ns-numbers (numbers)
  "An NSArray of NSNumbers, which is what the Swift side's [NSNumber] is."
  (let ((array (objc:invoke "NSMutableArray" "array")))
    (dolist (number numbers array)
      (objc:invoke array "addObject:"
                   (objc:invoke "NSNumber" "numberWithDouble:" (float number 1d0))))))

(defun bar-chart-controller (title data)
  "A UIViewController showing a Swift Charts bar chart of DATA, an alist of
label to value, hosted by SwiftUI."
  (objc:invoke "LispCharts" "barChartControllerWithTitle:labels:values:"
               title (coerce (mapcar #'car data) 'vector) (ns-numbers (mapcar #'cdr data))))

(defun bar-chart-png (title data path &key (width 360) (height 240))
  "The same chart rendered by SwiftUI itself into a PNG at PATH. Returns T
when written. PATH must be somewhere writable: the bundle is not, and HOME
is the app's Documents directory."
  (let ((ok (objc:invoke "LispCharts" "barChartWithTitle:labels:values:width:height:pngTo:"
                         title (coerce (mapcar #'car data) 'vector) (ns-numbers (mapcar #'cdr data))
                         (float width 1d0) (float height 1d0) (namestring path))))
    (not (or (null ok) (eql ok 0)))))

(defun language-model-availability ()
  "\"available\", or \"unavailable: <why>\"."
  (swift-string (objc:invoke "LispLanguageModel" "availability")))

;;; ------------------------------------------------------------------
;;; the data
;;;
;;; Ordinary Lisp: how many primes fall in each run of fifty below 400. The
;;; chart is Swift's; the numbers are not.

(defun primep (n)
  (and (> n 1) (loop for d from 2 to (isqrt n) never (zerop (mod n d)))))

(defvar *offset* 0 "Where the current data starts; NEW-DATA moves it on.")

(defun prime-counts (&key (start *offset*) (bins 8) (width 50))
  (loop for i below bins
        for low = (+ start (* i width))
        collect (cons (format nil "~d" low)
                      (count-if #'primep (loop for n from low below (+ low width) collect n)))))

;;; ------------------------------------------------------------------
;;; the interface

(defvar *chart* nil "The hosting controller on screen now.")
(defvar *chart-slot* nil "The view the chart lives in.")
(defvar *caption* nil)

(defun show-chart ()
  "Replace the chart with one of the current data."
  (when *chart*
    (objc:invoke *chart* "willMoveToParentViewController:" nil)
    (objc:invoke (objc:invoke *chart* "view") "removeFromSuperview")
    (objc:invoke *chart* "removeFromParentViewController")
    (ui:unkeep *chart*)
    (setf *chart* nil))
  (let* ((data (prime-counts))
         (root (ui:root-controller))
         (controller (ui:keep (bar-chart-controller
                               (format nil "Primes per fifty, from ~d" *offset*) data)))
         (view (objc:invoke controller "view")))
    ;; The child view controller dance, in the order UIKit documents it.
    (objc:invoke root "addChildViewController:" controller)
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke *chart-slot* "addSubview:" view)
    (ui:pin view "topAnchor" *chart-slot* "topAnchor")
    (ui:pin view "bottomAnchor" *chart-slot* "bottomAnchor")
    (ui:pin view "leadingAnchor" *chart-slot* "leadingAnchor")
    (ui:pin view "trailingAnchor" *chart-slot* "trailingAnchor")
    (objc:invoke controller "didMoveToParentViewController:" root)
    (setf *chart* controller)
    (objc:invoke *caption* "setText:"
                 (format nil "~{~a~^, ~} primes" (mapcar #'cdr data)))
    data))

(defun new-data ()
  "Move the window of numbers on by fifty and redraw. Bound to the button,
and callable from a REPL."
  (incf *offset* 50)
  (show-chart))

(defun label (text &key (size 15) mono (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (if mono (ui:mono-font size) (ui:font size)))
    (objc:invoke label "setNumberOfLines:" lines)
    (objc:invoke label "setTextColor:" (ui:system-color "label"))
    label))

(defun crypto-report ()
  "The CryptoKit calls, as lines for the screen and the console."
  (let* ((key (random-key))
         (sealed (seal "the quick brown fox" key))
         (opened (open-sealed sealed key))
         (tampered (open-sealed (concatenate 'string "A" (subseq sealed 1)) key)))
    (list (format nil "sha256(\"abc\") = ~a…" (subseq (sha256 "abc") 0 16))
          (format nil "hmac(\"abc\", \"key\") = ~a…" (subseq (hmac-sha256 "abc" "key") 0 16))
          (format nil "ChaChaPoly: sealed, opened ~s~%tampered box refused: ~a"
                  opened (if tampered "no" "yes")))))

(defun start ()
  "The entry point: build the screen. Must return; the run loop follows."
  ;; First, as in every example: the Lisp-defined classes uikit needs are
  ;; registered with the runtime here, and the Swift classes are already in,
  ;; loaded by dyld with the framework before main() ran.
  (objc:ensure-objc-initialized)
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView"))
         (report (crypto-report))
         (button (ui:system-button "New data")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)                ; vertical
    (objc:invoke column "setSpacing:" 12)
    (objc:invoke column "setAlignment:" 1)           ; leading
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    ;; Title, the CryptoKit lines, the chart, the button, the model.
    (objc:invoke column "addArrangedSubview:" (label "Swift frameworks, from Lisp" :size 22))
    (dolist (line report)
      (objc:invoke column "addArrangedSubview:" (label line :size 12 :mono t)))
    (setf *chart-slot* (ui:new "UIView"))
    (objc:invoke column "addArrangedSubview:" *chart-slot*)
    (ui:fix *chart-slot* "heightAnchor" 260)
    (ui:pin *chart-slot* "widthAnchor" column "widthAnchor")
    (setf *caption* (label "" :size 13))
    (objc:invoke column "addArrangedSubview:" *caption*)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (new-data)))
    (objc:invoke column "addArrangedSubview:" button)
    (objc:invoke column "addArrangedSubview:"
                 (label (format nil "On-device language model: ~a" (language-model-availability))
                        :size 12))
    (show-chart)
    ;; The console gets the same facts, for a test to read.
    (format t "~&SWIFT: sha256(\"abc\") = ~a~%" (sha256 "abc"))
    (format t "SWIFT: ~{~a~^ | ~}~%" report)
    (format t "SWIFT: chart on screen with ~d bars~%" (length (prime-counts)))
    (let ((png (merge-pathnames "chart.png" (user-homedir-pathname))))
      (format t "SWIFT: chart rendered to ~a: ~a~%" png
              (bar-chart-png "Primes per fifty" (prime-counts) png)))
    (format t "SWIFT: language model ~a~%" (language-model-availability))
    (finish-output)))

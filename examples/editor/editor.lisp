;;;; editor.lisp -- a Lisp editor, in Lisp, on the phone.
;;;;
;;;; TextKit does the text: a UITextView, its text storage an attributed
;;;; string. Lisp does the rest: on every keystroke the delegate, a Lisp
;;;; class, tokenizes the buffer and sets colours through the text storage
;;;; -- parentheses by depth, strings, comments, keywords -- and on every
;;;; cursor move it finds the matching parenthesis and marks the pair. The
;;;; Evaluate button reads the buffer and evaluates it in this image, which
;;;; is the one running the editor.

(defpackage #:editor
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:evaluate-buffer #:highlight))

(in-package #:editor)

(defvar *view* nil)
(defvar *result* nil)

;;; ------------------------------------------------------------------
;;; a tokenizer

(defun tokens (text)
  "((kind start end) ...) over TEXT: :open :close :string :comment :keyword
:number :symbol.  A small scanner, enough for colouring."
  (let ((tokens '()) (i 0) (n (length text)))
    (flet ((emit (kind start end) (push (list kind start end) tokens)))
      (loop while (< i n)
            do (let ((c (char text i)))
                 (cond ((char= c #\;)
                        (let ((end (or (position #\Newline text :start i) n)))
                          (emit :comment i end) (setf i end)))
                       ((char= c #\")
                        (let ((end (loop for j from (1+ i) below n
                                         do (case (char text j)
                                              (#\\ (incf j))
                                              (#\" (return (1+ j))))
                                         finally (return n))))
                          (emit :string i end) (setf i end)))
                       ((char= c #\() (emit :open i (1+ i)) (incf i))
                       ((char= c #\)) (emit :close i (1+ i)) (incf i))
                       ((or (alphanumericp c) (find c "-+*/<>=!?_.:&%$#'`,@^~|"))
                        (let ((end (or (position-if (lambda (d) (or (member d '(#\Space #\Newline #\Tab #\( #\) #\" #\;)))) text :start i) n)))
                          (let ((word (subseq text i end)))
                            (emit (cond ((and (plusp (length word)) (char= (char word 0) #\:)) :keyword)
                                        ((ignore-errors (let ((*read-eval* nil)) (numberp (read-from-string word)))) :number)
                                        (t :symbol))
                                  i end))
                          (setf i end)))
                       (t (incf i))))))
    (nreverse tokens)))

(defparameter +depth-colours+
  '((0.20 0.45 0.95) (0.85 0.35 0.55) (0.20 0.65 0.45) (0.90 0.55 0.15) (0.55 0.35 0.85))
  "Parentheses by depth, cycling.")

(defun colour (r g b) (ui:color r g b))

(defun highlight ()
  "Colour the whole buffer from the tokens: cheap enough per keystroke."
  (let* ((storage (objc:invoke *view* "textStorage"))
         (text (objc:ns-string-to-string (objc:invoke storage "string")))
         (length (length text))
         (depth 0))
    (objc:invoke storage "beginEditing")
    (objc:invoke storage "removeAttribute:range:" "NSColor" (cons 0 length))
    (objc:invoke storage "addAttribute:value:range:" "NSColor" (ui:system-color "label") (cons 0 length))
    (dolist (token (tokens text))
      (destructuring-bind (kind start end) token
        (let ((range (cons start (- end start))))
          (flet ((paint (r g b) (objc:invoke storage "addAttribute:value:range:" "NSColor" (colour r g b) range)))
            (ecase kind
              (:open (apply #'paint (nth (mod depth (length +depth-colours+)) +depth-colours+)) (incf depth))
              (:close (decf depth) (apply #'paint (nth (mod (max 0 depth) (length +depth-colours+)) +depth-colours+)))
              (:string (paint 0.75 0.30 0.20))
              (:comment (paint 0.50 0.50 0.50))
              (:keyword (paint 0.55 0.20 0.70))
              (:number (paint 0.10 0.55 0.65))
              (:symbol nil))))))
    (objc:invoke storage "endEditing")
    depth))

;;; ------------------------------------------------------------------
;;; the matching parenthesis

(defun match-at (text position)
  "The index of the parenthesis matching the one at or before POSITION, or NIL."
  (flet ((partner (index)
           (let ((c (char text index)) (depth 0))
             (case c
               (#\( (loop for j from index below (length text)
                          do (case (char text j) (#\( (incf depth)) (#\) (decf depth)))
                             (when (zerop depth) (return j))))
               (#\) (loop for j from index downto 0
                          do (case (char text j) (#\) (incf depth)) (#\( (decf depth)))
                             (when (zerop depth) (return j))))))))
    (cond ((and (< position (length text)) (find (char text position) "()"))
           (values position (partner position)))
          ((and (plusp position) (find (char text (1- position)) "()"))
           (values (1- position) (partner (1- position))))
          (t nil))))

(defvar *marked* '() "Ranges given a background last time, to clear.")

(defun mark-match ()
  (let* ((storage (objc:invoke *view* "textStorage"))
         (text (objc:ns-string-to-string (objc:invoke storage "string")))
         (selection (objc:invoke *view* "selectedRange")))
    (objc:invoke storage "beginEditing")
    (dolist (range *marked*)
      (when (<= (+ (car range) (cdr range)) (length text))
        (objc:invoke storage "removeAttribute:range:" "NSBackgroundColor" range)))
    (setf *marked* '())
    (multiple-value-bind (here there) (match-at text (car selection))
      (when (and here there)
        (dolist (index (list here there))
          (let ((range (cons index 1)))
            (objc:invoke storage "addAttribute:value:range:" "NSBackgroundColor"
                         (colour 1.0 0.92 0.45) range)
            (push range *marked*)))))
    (objc:invoke storage "endEditing")))

;;; ------------------------------------------------------------------
;;; the delegate, and evaluation

(objc:define-objc-class editor-delegate () ()
  (:objc-class-name "LispEditorDelegate")
  (:objc-protocols "UITextViewDelegate"))

(objc:define-objc-method ("textViewDidChange:" :void)
    ((self editor-delegate) (view objc:objc-object-pointer))
  (declare (ignore view))
  (highlight)
  (mark-match))

(objc:define-objc-method ("textViewDidChangeSelection:" :void)
    ((self editor-delegate) (view objc:objc-object-pointer))
  (declare (ignore view))
  (mark-match))

(defun evaluate-buffer ()
  "Every form in the buffer, evaluated in this image; the last value shown."
  (let ((text (objc:ns-string-to-string (objc:invoke *view* "text")))
        (values nil))
    (handler-case
        (with-input-from-string (in text)
          (loop for form = (read in nil in)
                until (eq form in)
                do (setf values (multiple-value-list (eval form))))
          (objc:invoke *result* "setText:" (format nil "=> ~{~s~^, ~}" values))
          (format t "EDITOR: => ~{~s~^, ~}~%" values))
      (error (condition)
        (objc:invoke *result* "setText:" (format nil "error: ~a" condition))
        (format t "EDITOR: error: ~a~%" condition)))
    (finish-output)
    values))

;;; ------------------------------------------------------------------
;;; the screen

(defparameter +opening-text+
  ";; A Lisp editor, in Lisp, on the phone.
;; Every keystroke re-colours the buffer; the cursor finds its match.
(defun fib (n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(list :tenth (fib 10) :thirtieth (fib 30)
      \"strings are one colour\" 'symbols-another)
")

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
         (button (ui:system-button "Evaluate")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 8)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 12)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 12)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -12)
    (ui:pin column "bottomAnchor" (objc:invoke root "keyboardLayoutGuide") "topAnchor" -8)
    (objc:invoke column "addArrangedSubview:" (label "A Lisp editor, in Lisp" :size 20))
    (setf *view* (ui:new "UITextView"))
    (objc:invoke *view* "setFont:" (ui:mono-font 14))
    (objc:invoke *view* "setAutocorrectionType:" 1)     ; off
    (objc:invoke *view* "setAutocapitalizationType:" 0)
    (objc:invoke *view* "setSmartQuotesType:" 1)
    (objc:invoke *view* "setSmartDashesType:" 1)
    (objc:invoke *view* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *view* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *view*)
    (setf *delegate* (ui:keep (make-instance 'editor-delegate)))
    (objc:invoke *view* "setDelegate:" (objc:objc-object-pointer *delegate*))
    (setf *result* (label "" :size 13 :lines 3))
    (objc:invoke *result* "setFont:" (ui:mono-font 13))
    (objc:invoke column "addArrangedSubview:" *result*)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (evaluate-buffer)))
    (objc:invoke column "addArrangedSubview:" button)
    (objc:invoke *view* "setText:" +opening-text+)
    (highlight)
    ;; The cursor on the closing parenthesis of the last form, so the match
    ;; is shown at once.
    (objc:invoke *view* "setSelectedRange:" (cons (1- (length +opening-text+)) 0))
    (mark-match)
    (evaluate-buffer)
    (format t "EDITOR: ~d tokens in the opening text~%" (length (tokens +opening-text+)))
    (finish-output)
    (values)))

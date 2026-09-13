;;;; model.lisp -- the on-device language model, with its tools in Lisp.
;;;;
;;;; FoundationModels can call tools while it answers: it reads a tool's
;;;; description, decides to use it, produces the input, and folds the
;;;; output into its reply. Here the tools are Lisp closures. The model is
;;;; told it cannot do arithmetic -- which is true of a three-billion
;;;; parameter model -- and that Lisp can, so "what is 2 to the 200th
;;;; power, exactly?" becomes a call into this file, where bignums are
;;;; ordinary numbers, and the model reads the digits back.
;;;;
;;;; The tool's input arrives on the model's thread, not the main one, and
;;;; the block it arrives through was made from a Lisp lambda. That is the
;;;; whole mechanism: OBJC:MAKE-OBJC-BLOCK on this side, a Swift closure
;;;; parameter on the other.

(defpackage #:model-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:ask #:evaluate #:prime-factors))

(in-package #:model-ios)

;;; ------------------------------------------------------------------
;;; the tools

(defparameter +arithmetic+
  '(+ - * / expt sqrt isqrt exp log mod rem gcd lcm floor ceiling round truncate
    abs max min evenp oddp = < > <= >= factorial fib)
  "What an expression from the model may call. Nothing else is evaluated.")

(defun factorial (n)
  (if (< n 2) 1 (* n (factorial (1- n)))))

(defun fib (n)
  (loop repeat n with a = 0 and b = 1 do (psetf a b b (+ a b)) finally (return a)))

(defun check-form (form)
  "FORM is a number, or a call of a whitelisted function on such forms."
  (cond ((numberp form) form)
        ((and (consp form) (member (car form) +arithmetic+))
         (mapc #'check-form (cdr form))
         form)
        (t (error "not arithmetic: ~s" form))))

(defun bare-notation (text)
  "(factorial N) for \"N!\" and (expt A B) for \"A ^ B\", or NIL."
  (let ((bang (position #\! text))
        (caret (position #\^ text)))
    (cond ((and bang (= bang (1- (length text)))
                (every #'digit-char-p (subseq text 0 bang)))
           (format nil "(factorial ~a)" (subseq text 0 bang)))
          ((and caret
                (every (lambda (c) (or (digit-char-p c) (char= c #\Space)))
                       (remove #\^ text)))
           (format nil "(expt ~a ~a)"
                   (string-trim " " (subseq text 0 caret))
                   (string-trim " " (subseq text (1+ caret)))))
          (t nil))))

(defun evaluate (string)
  "STRING as a Common Lisp arithmetic expression, evaluated exactly. The
model writes the expression; the whitelist above decides what it may do.

The model drops the outer parentheses now and then -- `factorial 100` for
(factorial 100) -- so a string that does not start with one is wrapped,
which turns that into the call it meant and leaves a bare number alone."
  (handler-case
      (let* ((*read-eval* nil)
             (*package* (find-package '#:model-ios))
             (text (string-trim " " string))
             ;; And now and then it writes mathematics rather than Lisp:
             ;; 100! or 10 ^ 150. The two spellings that recur are turned
             ;; into the calls they mean; anything else is left to fail
             ;; honestly.
             (text (or (bare-notation text) text))
             (text (if (or (zerop (length text)) (char= (char text 0) #\())
                       text
                       (format nil "(~a)" text)))
             (form (let ((form (read-from-string text)))
                     ;; "(100)" from "100": a one-element list of a number
                     ;; is that number.
                     (if (and (consp form) (null (cdr form)) (numberp (car form)))
                         (car form)
                         form))))
        (check-form form)
        (let ((*print-base* 10))
          ;; The number and nothing else.  A "(158 digits)" suffix was
          ;; tried, so the model could compare lengths it cannot count;
          ;; measured, it sent the model into a loop of factorising its
          ;; own answer until the context window overflowed.
          (princ-to-string (eval form))))
    (error (condition)
      (format nil "error: ~a" condition))))

(defun prime-factors (string)
  "The prime factorisation of the integer in STRING, as \"2^3 * 3^2 * 5\"."
  (handler-case
      (let ((n (parse-integer (string-trim " " string))))
        (when (< n 2) (error "~d has no prime factorisation" n))
        (let ((factors '()))
          (loop for d = 2 then (if (= d 2) 3 (+ d 2))
                while (<= (* d d) n)
                do (loop while (zerop (mod n d))
                         do (push d factors) (setf n (/ n d))))
          (when (> n 1) (push n factors))
          (format nil "~{~a~^ * ~}"
                  (loop for (p . count) in (let ((counts '()))
                                             (dolist (p (nreverse factors) (nreverse counts))
                                               (if (eql (car (first counts)) p)
                                                   (incf (cdr (first counts)))
                                                   (push (cons p 1) counts))))
                        collect (if (= count 1) (format nil "~d" p) (format nil "~d^~d" p count))))))
    (error (condition)
      (format nil "error: ~a" condition))))

;;; ------------------------------------------------------------------
;;; handing them to Swift
;;;
;;; A block from a Lisp closure, kept for the life of the image: the model
;;; may call it at any time, from its own thread.

(objc:define-objc-block-type tool-handler objc:objc-object-pointer (objc:objc-object-pointer))

(defvar *tool-blocks* '() "Kept, never freed: the model holds them.")

(defun register-tool (name description function)
  (let ((block (objc:make-objc-block
                'tool-handler
                (lambda (input)
                  (let ((result (funcall function (objc:ns-string-to-string input))))
                    ;; An NSString for Swift, made here on the model's thread.
                    (objc:invoke "NSString" "stringWithString:" result))))))
    (push block *tool-blocks*)
    (objc:invoke "LispModel" "addToolNamed:description:handler:" name description block)))

(defun register-tools ()
  (register-tool "lispEvaluate"
                 "Evaluates one complete Common Lisp arithmetic expression exactly, with integers of any size. Input is the whole expression with its parentheses, for example (expt 2 200), (* 123456789 987654321), (factorial 100) or (fib 100). Use it for every calculation; never calculate yourself. One call answers one expression; when it has answered, reply."
                 #'evaluate)
  (register-tool "primeFactors"
                 "The prime factorisation of a positive integer. Input is the integer in decimal digits."
                 #'prime-factors))

(defparameter +instructions+
  "You are a careful assistant with no ability to do arithmetic yourself. For any calculation or comparison, however small, call the lispEvaluate tool with one complete Common Lisp expression -- operator first, inside parentheses, such as (factorial 100) or (fib 100) -- never mathematical notation like 100! or 10^150. Use the primeFactors tool for factorisations. Call a tool once per calculation, and when it has answered, reply with its exact output in one or two sentences.")

;;; ------------------------------------------------------------------
;;; the interface

(defvar *transcript* nil)
(defvar *prompt* nil)
(defvar *lines* '())
(defvar *queue* '() "Questions still to ask, one after another as answers arrive.")

(defun say (format &rest arguments)
  "Append a line to the transcript, and to the console."
  (let ((line (apply #'format nil format arguments)))
    (format t "MODEL: ~a~%" line)
    (finish-output)
    (setf *lines* (append *lines* (list line)))
    (objc:invoke *transcript* "setText:" (format nil "~{~a~%~}" *lines*))
    ;; Keep the newest line in view.
    (let ((length (length (objc:ns-string-to-string (objc:invoke *transcript* "text")))))
      (objc:invoke *transcript* "scrollRangeToVisible:" (cons length 0)))))

(objc:define-objc-block-type model-reply :void
  (objc:objc-object-pointer objc:objc-object-pointer objc:objc-object-pointer))

(defun ask (prompt)
  "Put PROMPT to the model. The answer arrives later, on the main thread."
  (say "> ~a" prompt)
  (objc:with-objc-block (reply 'model-reply
                               (lambda (answer failure calls)
                                 (let ((count (objc:invoke calls "count")))
                                   (dotimes (i count)
                                     (say "  [~a]" (objc:ns-string-to-string
                                                    (objc:invoke calls "objectAtIndex:" i)))))
                                 (if (cffi:null-pointer-p answer)
                                     (say "  error: ~a" (objc:ns-string-to-string failure))
                                     (say "~a~%" (objc:ns-string-to-string answer)))
                                 (when *queue*
                                   (ask (pop *queue*)))))
    (objc:invoke "LispModel" "askWithPrompt:instructions:reply:" prompt +instructions+ reply)))

(defun ask-from-field ()
  (let ((text (objc:ns-string-to-string (objc:invoke *prompt* "text"))))
    (when (plusp (length (string-trim " " text)))
      (objc:invoke *prompt* "resignFirstResponder")
      (ask text))))

(defparameter +presets+
  '("What is 2 to the 200th power, exactly?"
    "What are the prime factors of 600851475143?"
    "What is the 100th Fibonacci number?")
  "Questions with one exact answer each. A comparison -- which is bigger,
100! or 10^150 -- was the third for a while, and the model, handed both
numbers, compared them wrongly: it can read digits back, not weigh them.")

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font size))
    (objc:invoke label "setNumberOfLines:" lines)
    label))

(defun start ()
  "The entry point: build the screen, register the tools, ask the first
question. Must return; the run loop follows."
  (objc:ensure-objc-initialized)
  (register-tools)
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView"))
         (availability (objc:ns-string-to-string (objc:invoke "LispModel" "availability"))))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "The on-device model, with tools in Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label (format nil "Language model: ~a" availability) :size 12))
    ;; The transcript.
    (setf *transcript* (ui:new "UITextView"))
    (objc:invoke *transcript* "setEditable:" nil)
    (objc:invoke *transcript* "setFont:" (ui:mono-font 12))
    (objc:invoke *transcript* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *transcript* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *transcript*)
    ;; The presets, each a button.
    (dolist (preset +presets+)
      (let ((button (ui:system-button preset)))
        (objc:invoke button "setContentHorizontalAlignment:" 1) ; left
        (objc:invoke (objc:invoke button "titleLabel") "setFont:" (ui:font 14))
        (ui:on-tap button (let ((preset preset)) (lambda (sender) (declare (ignore sender)) (ask preset))))
        (objc:invoke column "addArrangedSubview:" button)))
    ;; A question of your own.
    (let ((row (ui:new "UIStackView"))
          (field (ui:new "UITextField"))
          (button (ui:system-button "Ask")))
      (objc:invoke row "setAxis:" 0)
      (objc:invoke row "setSpacing:" 8)
      (objc:invoke field "setBorderStyle:" 3)          ; rounded rect
      (objc:invoke field "setPlaceholder:" "Ask something with numbers in it")
      (objc:invoke field "setFont:" (ui:font 14))
      (setf *prompt* field)
      (ui:on-tap button (lambda (sender) (declare (ignore sender)) (ask-from-field)))
      (objc:invoke row "addArrangedSubview:" field)
      (objc:invoke row "addArrangedSubview:" button)
      (objc:invoke column "addArrangedSubview:" row))
    (say "tools: lispEvaluate, primeFactors -- both Lisp closures")
    ;; The first question straight away; all of them, one after another,
    ;; when MODEL_ASK=all is in the environment (SIMCTL_CHILD_MODEL_ASK
    ;; from simctl), which is how the screenshot was taken.
    (when (string= availability "available")
      (when (equal (ext:getenv "MODEL_ASK") "all")
        (setf *queue* (rest +presets+)))
      (ask (first +presets+)))
    (values)))

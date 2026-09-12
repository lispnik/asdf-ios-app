;;;; lem-iphone.lisp -- coding the phone from Lem.
;;;;
;;;; What iphone.el does for Emacs, for Lem: connect to the slynk inside the
;;;; app on the phone and send it the form at point, the region, or a form
;;;; typed at a prompt, showing the value in the echo area. Lem's own Lisp
;;;; mode speaks micros, not slynk, so this is a small slynk client of its
;;;; own -- the protocol is a six-digit hex length and an s-expression, and
;;;; :emacs-rex with (slynk:eval-and-grab-output ...) is all a REPL needs.
;;;;
;;;; Load it from Lem's init file, or M-x load-file it, then:
;;;;
;;;;   M-x iphone-connect        starts iproxy for a phone on the cable, or
;;;;                             connects straight to localhost for the
;;;;                             simulator, and says which
;;;;   C-c C-p                   sends the top-level form around point
;;;;   M-x iphone-eval-region    sends the region
;;;;   M-x iphone-eval           prompts for a form
;;;;   M-x iphone-disconnect
;;;;
;;;; The phone evaluates in LIVE, so (defun paint ...) from tour.lisp lands
;;;; where it should. Needs usocket, which Lem already carries for micros.

(defpackage :lem-iphone
  (:use :cl :lem)
  (:export :iphone-connect
           :iphone-disconnect
           :iphone-eval
           :iphone-eval-defun
           :iphone-eval-region
           :*iphone-port*
           :*iphone-package*))
(in-package :lem-iphone)

(defvar *iphone-port* 4005
  "The port the app's slynk listens on, the same number on both ends.")

(defvar *iphone-package* "LIVE"
  "The package forms are read in on the phone.")

(defvar *connection* nil "The socket to slynk, once connected.")
(defvar *forwarder* nil "The iproxy process, when this connection started one.")
(defvar *counter* 0 "The :emacs-rex continuation id, unique per request.")

(define-key *global-keymap* "C-c C-p" 'iphone-eval-defun)

;;; The slynk wire protocol ------------------------------------------------------

(defun send-message (stream string)
  (let ((octets (babel:string-to-octets string :encoding :utf-8)))
    (format stream "~6,'0x" (length octets))
    (write-sequence (babel:octets-to-string octets :encoding :latin-1) stream)
    (finish-output stream)))

(defun read-message (stream)
  (let* ((header (make-string 6)))
    (unless (= 6 (read-sequence header stream))
      (error "The connection to the phone closed."))
    (let* ((length (parse-integer header :radix 16))
           (raw (make-string length)))
      (read-sequence raw stream)
      (babel:octets-to-string (babel:string-to-octets raw :encoding :latin-1) :encoding :utf-8))))

(defun lisp-string (string)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop :for c :across string
          :do (when (member c '(#\" #\\)) (write-char #\\ out))
              (write-char c out))
    (write-char #\" out)))

(defun remote-eval (form-string)
  "Evaluate FORM-STRING on the phone. Returns what it printed and its value
as strings, or signals with the phone's own report of what went wrong."
  (unless *connection*
    (editor-error "Not connected to the phone: M-x iphone-connect first."))
  (let ((stream (usocket:socket-stream *connection*))
        (id (incf *counter*)))
    (send-message stream
                  (format nil "(:emacs-rex (slynk:eval-and-grab-output ~a) ~s t ~d)"
                          (lisp-string form-string) *iphone-package* id))
    (loop
      (let ((reply (read-message stream)))
        ;; Anything but our :return is slynk telling us things -- indentation
        ;; tables, presentations -- that a REPL this small has no use for.
        (when (and (> (length reply) 8) (string= ":return" reply :start2 1 :end2 8))
          (let* ((*read-eval* nil)
                 (message (let ((*package* (find-package :keyword)))
                            (read-from-string reply))))
            (when (eql (third message) id)
              (let ((result (second message)))
                (case (first result)
                  (:ok (return (values (first (second result)) (second (second result)))))
                  (:abort (error "The phone aborted: ~a" (second result)))
                  (t (error "The phone said: ~s" result)))))))))))

;;; Connecting --------------------------------------------------------------------

(defun phone-on-usb ()
  "The UDID of a phone on the cable, or NIL. idevice_id is libimobiledevice's."
  (let ((listing (ignore-errors
                  (uiop:run-program '("idevice_id" "-l") :output :string :ignore-error-status t))))
    (and listing (first (uiop:split-string (string-trim '(#\Newline) listing) :separator '(#\Newline))))))

(defun start-forwarder (udid)
  "iproxy carrying the port over the cable to the phone UDID."
  (uiop:launch-program (list "iproxy" "-u" udid
                             (format nil "~d:~d" *iphone-port* *iphone-port*))
                       :output nil :error-output nil))

(define-command iphone-connect () ()
  "Connect to the app on the phone, through iproxy if a phone is on the cable,
or straight to localhost, which is where the simulator's app listens."
  (iphone-disconnect)
  (let ((udid (phone-on-usb)))
    (when (and udid (plusp (length udid)))
      (setf *forwarder* (start-forwarder udid))
      (sleep 0.5))
    (handler-case
        (setf *connection* (usocket:socket-connect "127.0.0.1" *iphone-port*
                                                   :element-type 'character))
      (error (condition)
        (editor-error "Could not reach the app on port ~d: ~a" *iphone-port* condition))
      (:no-error (&rest values)
        (declare (ignore values))
        (multiple-value-bind (output value)
            (remote-eval "(list (lisp-implementation-type) (lisp-implementation-version) (machine-instance))")
          (declare (ignore output))
          (message "Connected~a: ~a" (if udid " to the phone" " to the simulator") value))))))

(define-command iphone-disconnect () ()
  "Close the connection to the phone and stop the forwarder."
  (when *connection*
    (ignore-errors (usocket:socket-close *connection*))
    (setf *connection* nil))
  (when *forwarder*
    (ignore-errors (uiop:terminate-process *forwarder*))
    (setf *forwarder* nil)))

;;; Sending code -------------------------------------------------------------------

(defun show-result (output value)
  (message "~@[~a~%~]⇒ ~a" (and (plusp (length output)) (string-right-trim '(#\Newline) output)) value))

(defun eval-and-show (string)
  (multiple-value-bind (output value) (remote-eval string)
    (show-result output value)))

(define-command iphone-eval (string) ((prompt-for-string "Eval on the phone: "))
  "Evaluate STRING on the phone and show the value."
  (eval-and-show string))

(define-command iphone-eval-defun () ()
  "Send the top-level form around point to the phone."
  (with-point ((point (current-point)))
    (lem-lisp-syntax:top-of-defun point)
    (with-point ((start point) (end point))
      (scan-lists end 1 0)
      (eval-and-show (points-to-string start end)))))

(define-command iphone-eval-region (start end) (:region)
  "Send the region to the phone, as one form or several."
  (eval-and-show (format nil "(progn ~a)" (points-to-string start end))))

;;;; serve.lisp -- the phone serves a page, and says so on the network.
;;;;
;;;; Network.framework is Apple's modern socket layer: C functions whose
;;;; every event is a block on a dispatch queue. A listener gets a new
;;;; connection; a connection receives bytes and sends bytes; each of
;;;; those handlers is a Lisp closure here, arriving on the queue's own
;;;; thread. The page it serves is about the image serving it, and the
;;;; listener is advertised as _http._tcp over Bonjour, so Safari on the
;;;; Mac finds the phone by name.

(defpackage #:serve
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:*port* #:page))

(in-package #:serve)

(defparameter *port* 8080)
(defvar *status* nil)
(defvar *log* nil)
(defvar *requests* '())
(defvar *started* (get-universal-time))

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "SERVE: ~a~%" text)
    (finish-output)
    (when *status* (objc:invoke *status* "setText:" text))))

(defun call (name result-type argument-types &rest arguments)
  (si:call-cfun (cffi:foreign-symbol-pointer name) result-type argument-types arguments))

;;; ------------------------------------------------------------------
;;; the page

(defun page (request-line)
  (let ((rows (loop for package in (list-all-packages)
                    collect (list (package-name package)
                                  (let ((n 0)) (do-symbols (s package) (declare (ignore s)) (incf n)) n)))))
    (format nil "<!doctype html><html><head><meta charset=\"utf-8\"><title>A Lisp image, on a phone</title>
<style>body{font-family:-apple-system,sans-serif;margin:2em;max-width:40em}code{background:#eee;padding:2px 5px;border-radius:4px}td{padding:2px 12px 2px 0}</style></head>
<body><h1>Served by Lisp, from the phone</h1>
<p>~a ~a on ~a, up ~d s, ~d request~:p so far. Your request line was <code>~a</code>.</p>
<p>Every byte of this reply was assembled in Lisp and sent through Network.framework, whose handlers are Lisp closures on a dispatch queue.</p>
<table>~{<tr><td>~a</td><td>~:d symbols</td></tr>~}</table></body></html>"
            (lisp-implementation-type) (lisp-implementation-version) (machine-type)
            (- (get-universal-time) *started*) (length *requests*) request-line
            (loop for (name count) in (subseq (sort rows #'> :key #'second) 0 12)
                  append (list name count)))))

(defun response (request-line)
  (let ((body (page request-line)))
    (format nil "HTTP/1.1 200 OK~c~cContent-Type: text/html; charset=utf-8~c~cContent-Length: ~d~c~cConnection: close~c~c~c~c~a"
            #\Return #\Newline #\Return #\Newline
            (length (babel:string-to-octets body :encoding :utf-8)) #\Return #\Newline
            #\Return #\Newline #\Return #\Newline body)))

;;; ------------------------------------------------------------------
;;; dispatch_data in and out

(defun dispatch-data-string (data)
  "The bytes of a dispatch_data_t as a string, through a mapped copy."
  (cffi:with-foreign-objects ((buffer :pointer) (size :uint64))
    (let ((mapped (call "dispatch_data_create_map" :pointer-void '(:pointer-void :pointer-void :pointer-void)
                        data buffer size)))
      (prog1 (cffi:foreign-string-to-lisp (cffi:mem-ref buffer :pointer)
                                          :count (cffi:mem-ref size :uint64) :encoding :utf-8)
        (objc:invoke mapped "release")))))

(defun dispatch-data (string)
  "A dispatch_data_t holding STRING's UTF-8; libdispatch copies the bytes."
  (let* ((octets (babel:string-to-octets string :encoding :utf-8))
         (n (length octets)))
    (cffi:with-foreign-object (bytes :uint8 n)
      (dotimes (i n) (setf (cffi:mem-aref bytes :uint8 i) (aref octets i)))
      (call "dispatch_data_create" :pointer-void '(:pointer-void :unsigned-long :pointer-void :pointer-void)
            bytes n (cffi:null-pointer) (cffi:null-pointer)))))

;;; ------------------------------------------------------------------
;;; the listener and its connections

(objc:define-objc-block-type connection-handler :void (objc:objc-object-pointer))
(objc:define-objc-block-type state-handler :void ((:unsigned :int) objc:objc-object-pointer))
(objc:define-objc-block-type receive-handler :void
  (objc:objc-object-pointer objc:objc-object-pointer objc:objc-c++-bool objc:objc-object-pointer))
(objc:define-objc-block-type send-handler :void (objc:objc-object-pointer))

(defvar *queue* nil)
(defvar *listener* nil)
(defvar *blocks* '() "Every handler ever made, kept: the framework holds them.")
(defvar *connections* '())

(defun keep-block (block)
  "Keep BLOCK for the listener's lifetime and hand back the raw pointer, which
is what SI:CALL-CFUN wants for a :POINTER-VOID argument."
  (push block *blocks*)
  (objc:objc-object-pointer block))

(defun log-request (line)
  (push line *requests*)
  (ios-app-runtime:on-main
   (lambda ()
     (objc:invoke *log* "setText:" (format nil "~{~a~%~}" (reverse (subseq *requests* 0 (min 12 (length *requests*))))))
     (say "listening on port ~d; ~d request~:p served" *port* (length *requests*)))))

(defun serve-connection (connection)
  "One HTTP exchange: read once, answer, close."
  (ui:keep connection)
  (push connection *connections*)
  (call "nw_connection_set_queue" :void '(:pointer-void :pointer-void) connection *queue*)
  (call "nw_connection_set_state_changed_handler" :void '(:pointer-void :pointer-void) connection
        (keep-block (objc:make-objc-block 'state-handler (lambda (state error) (declare (ignore state error))))))
  (call "nw_connection_receive" :void '(:pointer-void :unsigned-int :unsigned-int :pointer-void)
        connection 1 65536
        (keep-block
         (objc:make-objc-block
          'receive-handler
          (lambda (content context complete error)
            (declare (ignore context complete error))
            (let* ((request (if (cffi:null-pointer-p content) "" (dispatch-data-string content)))
                   (line (subseq request 0 (or (position #\Return request) (min 80 (length request))))))
              (log-request (format nil "~a  ~a" (multiple-value-bind (s m h) (get-decoded-time) (format nil "~2,'0d:~2,'0d:~2,'0d" h m s)) line))
              (call "nw_connection_send" :void '(:pointer-void :pointer-void :pointer-void :int :pointer-void)
                    connection (dispatch-data (response line))
                    (cffi:mem-ref (cffi:foreign-symbol-pointer "_nw_content_context_default_message") :pointer)
                    1
                    (keep-block (objc:make-objc-block
                                 'send-handler
                                 (lambda (error)
                                   (declare (ignore error))
                                   (call "nw_connection_cancel" :void '(:pointer-void) connection))))))))))
  (call "nw_connection_start" :void '(:pointer-void) connection))

(defun start-listening ()
  (setf *queue* (call "dispatch_queue_create" :pointer-void '(:cstring :pointer-void) "lisp.serve" (cffi:null-pointer)))
  (let* ((disable (cffi:mem-ref (cffi:foreign-symbol-pointer "_nw_parameters_configure_protocol_disable") :pointer))
         (default (cffi:mem-ref (cffi:foreign-symbol-pointer "_nw_parameters_configure_protocol_default_configuration") :pointer))
         (parameters (call "nw_parameters_create_secure_tcp" :pointer-void '(:pointer-void :pointer-void) disable default)))
    (setf *listener* (call "nw_listener_create_with_port" :pointer-void '(:cstring :pointer-void)
                           (princ-to-string *port*) parameters))
    (when (cffi:null-pointer-p *listener*) (error "no listener on port ~d" *port*))
    ;; Bonjour: _http._tcp, named after the phone.
    (call "nw_listener_set_advertise_descriptor" :void '(:pointer-void :pointer-void) *listener*
          (call "nw_advertise_descriptor_create_bonjour_service" :pointer-void '(:cstring :cstring :pointer-void)
                "Lisp on the phone" "_http._tcp" (cffi:null-pointer)))
    (call "nw_listener_set_queue" :void '(:pointer-void :pointer-void) *listener* *queue*)
    (call "nw_listener_set_state_changed_handler" :void '(:pointer-void :pointer-void) *listener*
          (keep-block (objc:make-objc-block
                       'state-handler
                       (lambda (state error)
                         (declare (ignore error))
                         (ios-app-runtime:on-main
                          (lambda ()
                            (say "listener ~a on port ~d"
                                 (case state (1 "waiting") (2 "ready") (3 "failed") (4 "cancelled") (t state))
                                 *port*)))))))
    (call "nw_listener_set_new_connection_handler" :void '(:pointer-void :pointer-void) *listener*
          (keep-block (objc:make-objc-block 'connection-handler #'serve-connection)))
    (call "nw_listener_start" :void '(:pointer-void) *listener*)))

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
  (setf *started* (get-universal-time))
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
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "The phone serves a page" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label (format nil "Network.framework's listener, receive and send handlers are Lisp blocks on a dispatch queue. Open http://localhost:~d from the Mac, or find \"Lisp on the phone\" in Bonjour." *port*) :size 13))
    (setf *status* (label "" :size 12))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *log* (ui:new "UITextView"))
    (objc:invoke *log* "setEditable:" nil)
    (objc:invoke *log* "setFont:" (ui:mono-font 12))
    (objc:invoke *log* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *log* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *log*)
    (start-listening)
    (values)))

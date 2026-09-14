;;;; fetch.lisp -- the network, from Lisp on the phone.
;;;;
;;;; NSURLSession does the fetching; what is Lisp's is everything around
;;;; it. The completion handler is a block made from a lambda, and it is
;;;; called on one of the session's own threads -- so this is a callback
;;;; arriving on a thread ECL never made, which the runtime imports. The
;;;; JSON is parsed by Foundation and walked here, and the table's data
;;;; source is a Lisp class. Nothing is compiled by a C compiler.
;;;;
;;;; The request is to GitHub's public API for the repositories of the
;;;; account these tools live in, sorted by the last push.

(defpackage #:fetch-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:fetch #:*rows*))

(in-package #:fetch-ios)

(defparameter +url+ "https://api.github.com/users/lispnik/repos?per_page=40&sort=pushed")

;;; ------------------------------------------------------------------
;;; JSON, walked

(defun string-of (dictionary key)
  (let ((value (objc:invoke dictionary "objectForKey:" key)))
    (if (or (cffi:null-pointer-p value)
            (objc:invoke-bool value "isKindOfClass:" (objc:invoke "NSNull" "class")))
        ""
        (objc:ns-string-to-string (objc:invoke value "description")))))

(defun rows-from-json (data)
  "The repositories in DATA, an NSData of JSON: (name language stars pushed)."
  (let ((array (objc:invoke "NSJSONSerialization" "JSONObjectWithData:options:error:"
                            data 0 nil)))
    (when (cffi:null-pointer-p array)
      (error "the reply was not JSON"))
    (loop for i below (objc:invoke array "count")
          for repo = (objc:invoke array "objectAtIndex:" i)
          collect (list (string-of repo "name")
                        (string-of repo "language")
                        (string-of repo "stargazers_count")
                        (subseq (string-of repo "pushed_at") 0 10)))))

;;; ------------------------------------------------------------------
;;; the request

(objc:define-objc-block-type data-task-completion :void
  (objc:objc-object-pointer objc:objc-object-pointer objc:objc-object-pointer))

(defvar *rows* '())
(defvar *status* nil)
(defvar *table* nil)

(defun show-status (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "FETCH: ~a~%" text)
    (finish-output)
    (when *status* (objc:invoke *status* "setText:" text))))

(defun fetch ()
  "Start the request. The reply arrives later, on a session thread, and is
handed to the main thread to show."
  (show-status "fetching ~a…" +url+)
  (let* ((session (objc:invoke "NSURLSession" "sharedSession"))
         (url (objc:invoke "NSURL" "URLWithString:" +url+)))
    (objc:with-objc-block
        (completion 'data-task-completion
                    (lambda (data response error)
                      (declare (ignore response))
                      (let ((outcome
                              (handler-case
                                  (if (cffi:null-pointer-p error)
                                      (let ((rows (rows-from-json data)))
                                        (setf *rows* rows)
                                        ;; A session thread is one ECL never made and
                                        ;; imported on arrival; it has no name.
                                        (format nil "~d repositories, on ~a"
                                                (length rows)
                                                (or (mp:process-name mp:*current-process*)
                                                    "an unnamed session thread, imported")))
                                      (format nil "failed: ~a"
                                              (objc:ns-string-to-string
                                               (objc:invoke error "localizedDescription"))))
                                (error (condition) (format nil "failed: ~a" condition)))))
                        ;; UIKit is main-thread only; this is not the main thread.
                        (ios-app-runtime:on-main
                         (lambda ()
                           (show-status "~a" outcome)
                           (objc:invoke *table* "reloadData"))))))
      (objc:invoke (objc:invoke session "dataTaskWithURL:completionHandler:" url completion)
                   "resume"))))

;;; ------------------------------------------------------------------
;;; the table

(objc:define-objc-class repo-source () () (:objc-class-name "RepoSource"))

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self repo-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (length *rows*))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self repo-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "repo"))
            (row (nth (objc:invoke path "row") *rows*)))
        (when (cffi:null-pointer-p cell)
          (setf cell (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                  "initWithStyle:reuseIdentifier:" 3 "repo")))
        (destructuring-bind (name language stars pushed) (or row '("" "" "" ""))
          (objc:invoke (objc:invoke cell "textLabel") "setText:" name)
          (objc:invoke (objc:invoke cell "detailTextLabel") "setText:"
                       (format nil "~a  ★ ~a  pushed ~a" (if (string= language "") "—" language) stars pushed)))
        cell)
    (serious-condition ()
      (objc:invoke (objc:invoke "UITableViewCell" "alloc") "initWithStyle:reuseIdentifier:" 0 "repo"))))

(defvar *source* nil)

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
         (button (ui:system-button "Fetch again")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "JSON from the network, in Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "NSURLSession's completion handler is a Lisp closure, called on a session thread; the JSON is walked in Lisp and this table's data source is a Lisp class." :size 13))
    (setf *status* (label "" :size 12))
    (objc:invoke *status* "setFont:" (ui:mono-font 11))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *table* (ui:new "UITableView")
          *source* (ui:keep (make-instance 'repo-source)))
    (objc:invoke *table* "setDataSource:" (objc:objc-object-pointer *source*))
    (objc:invoke column "addArrangedSubview:" *table*)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (fetch)))
    (objc:invoke column "addArrangedSubview:" button)
    (fetch)
    (values)))

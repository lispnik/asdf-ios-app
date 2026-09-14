;;;; ledger.lisp -- a ledger in SQLite, with a C fingerprint on every row.
;;;;
;;;; Two things no other example links: SQLite, which iOS ships and one
;;;; linker flag brings in, and a static library of the app's own, built by
;;;; build.sh from fingerprint.c. Both are reached the same way -- a C
;;;; function looked up by name and called through the dynamic FFI -- and
;;;; the ledger they keep survives across launches in the app's Documents,
;;;; which is where HOME points.
;;;;
;;;; The SQLite calls are the classic five: open, prepare, step, column,
;;;; finalize. Text goes in bound as a parameter, never spliced into SQL.

(defpackage #:ledger
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:add #:entries #:fingerprint))

(in-package #:ledger)

;;; ------------------------------------------------------------------
;;; C, by name

(defvar *functions* (make-hash-table :test #'equal))

(defun foreign (name)
  "The C function NAME, looked up once. Lazily, as every example notes: a
lookup at load time runs on the Mac during the native pass, where neither
library is linked."
  (or (gethash name *functions*)
      (setf (gethash name *functions*) (cffi:foreign-symbol-pointer name))))

(defun fingerprint (text)
  "FNV-1a of TEXT, from fingerprint.c, as sixteen hex digits."
  (format nil "~16,'0x"
          (si:call-cfun (foreign "fingerprint") :unsigned-long-long '(:cstring) (list text))))

;;; ------------------------------------------------------------------
;;; SQLite

(defconstant +sqlite-ok+ 0)
(defconstant +sqlite-row+ 100)
(defconstant +sqlite-done+ 101)
(defconstant +sqlite-transient+ -1 "Tell sqlite3_bind_text to copy the string.")

(defvar *db* nil)

(defun db-path ()
  (namestring (merge-pathnames "ledger.sqlite" (user-homedir-pathname))))

(defun check (code what)
  (unless (member code (list +sqlite-ok+ +sqlite-row+ +sqlite-done+))
    (error "sqlite: ~a failed with ~d: ~a" what code
           (cffi:foreign-string-to-lisp
            (si:call-cfun (foreign "sqlite3_errmsg") :pointer-void '(:pointer-void) (list *db*))))))

(defun open-db ()
  (unless *db*
    (cffi:with-foreign-object (handle :pointer)
      (check (si:call-cfun (foreign "sqlite3_open") :int '(:cstring :pointer-void)
                           (list (db-path) handle))
             "open")
      (setf *db* (cffi:mem-ref handle :pointer)))
    (execute "create table if not exists entries (id integer primary key, text text not null, fingerprint text not null, at text not null)"))
  *db*)

(defun prepare (sql)
  (cffi:with-foreign-object (statement :pointer)
    (check (si:call-cfun (foreign "sqlite3_prepare_v2") :int
                         '(:pointer-void :cstring :int :pointer-void :pointer-void)
                         (list *db* sql -1 statement (cffi:null-pointer)))
           sql)
    (cffi:mem-ref statement :pointer)))

(defun bind-text (statement index text)
  ;; The destructor argument is SQLITE_TRANSIENT, which is (void *)-1: passed
  ;; as a :LONG rather than a pointer, since a pointer with the top bit set
  ;; is beyond what CFFI:MAKE-POINTER accepts on ECL.  Same register either
  ;; way.
  (check (si:call-cfun (foreign "sqlite3_bind_text") :int
                       '(:pointer-void :int :cstring :int :long)
                       (list statement index text -1 +sqlite-transient+))
         "bind"))

(defun step-statement (statement)
  (si:call-cfun (foreign "sqlite3_step") :int '(:pointer-void) (list statement)))

(defun column-text (statement index)
  (let ((pointer (si:call-cfun (foreign "sqlite3_column_text") :pointer-void
                               '(:pointer-void :int) (list statement index))))
    (if (cffi:null-pointer-p pointer) "" (cffi:foreign-string-to-lisp pointer))))

(defun finalize (statement)
  (si:call-cfun (foreign "sqlite3_finalize") :int '(:pointer-void) (list statement)))

(defun execute (sql &rest texts)
  "Run SQL with TEXTS bound to its ? parameters; return the rows, each a
list of the columns as strings."
  (let ((statement (prepare sql)))
    (unwind-protect
         (progn
           (loop for text in texts for index from 1 do (bind-text statement index text))
           (loop for code = (step-statement statement)
                 while (= code +sqlite-row+)
                 collect (loop for index below (si:call-cfun (foreign "sqlite3_column_count")
                                                             :int '(:pointer-void) (list statement))
                               collect (column-text statement index))
                 finally (check code sql)))
      (finalize statement))))

;;; ------------------------------------------------------------------
;;; the ledger

(defun clock ()
  (multiple-value-bind (s m h) (get-decoded-time)
    (format nil "~2,'0d:~2,'0d:~2,'0d" h m s)))

(defun add (text)
  "Add TEXT to the ledger, fingerprinted."
  (open-db)
  (execute "insert into entries (text, fingerprint, at) values (?, ?, ?)"
           text (fingerprint text) (clock))
  (refresh)
  text)

(defun entries ()
  "Every entry, newest first: (id text fingerprint at)."
  (open-db)
  (execute "select id, text, fingerprint, at from entries order by id desc"))

;;; ------------------------------------------------------------------
;;; the interface: a table whose data source is Lisp

(objc:define-objc-class ledger-source ()
  ()
  (:objc-class-name "LedgerSource"))

(defvar *rows* '())

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self ledger-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (length *rows*))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self ledger-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "entry"))
            (row (nth (objc:invoke path "row") *rows*)))
        (when (cffi:null-pointer-p cell)
          ;; Style 3 is Subtitle: the text above, the details beneath.
          (setf cell (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                  "initWithStyle:reuseIdentifier:" 3 "entry")))
        (destructuring-bind (id text print at) (or row '("" "" "" ""))
          (objc:invoke (objc:invoke cell "textLabel") "setText:" text)
          (objc:invoke (objc:invoke cell "detailTextLabel") "setText:"
                       (format nil "#~a  ~a  fnv1a ~a" id at print))
          (objc:invoke (objc:invoke cell "detailTextLabel") "setFont:" (ui:mono-font 11)))
        cell)
    (serious-condition ()
      (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                   "initWithStyle:reuseIdentifier:" 0 "entry"))))

(defvar *table* nil)
(defvar *source* nil)
(defvar *field* nil)
(defvar *count* nil)

(defun refresh ()
  (setf *rows* (entries))
  (objc:invoke *count* "setText:"
               (format nil "~d entr~:@p in ~a" (length *rows*) (file-namestring (db-path))))
  (objc:invoke *table* "reloadData"))

(defun add-from-field ()
  (let ((text (objc:ns-string-to-string (objc:invoke *field* "text"))))
    (when (plusp (length (string-trim " " text)))
      (add text)
      (objc:invoke *field* "setText:" "")
      (objc:invoke *field* "resignFirstResponder"))))

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
         (button (ui:system-button "Add")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "A ledger in SQLite" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "Rows through sqlite3_* by name; each fingerprinted by a C function from the app's own static library. It is still here after a relaunch." :size 13))
    (setf *count* (label "" :size 13))
    (objc:invoke column "addArrangedSubview:" *count*)
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 8)
    (setf *field* (ui:new "UITextField"))
    (objc:invoke *field* "setBorderStyle:" 3)
    (objc:invoke *field* "setPlaceholder:" "Something to remember")
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (add-from-field)))
    (objc:invoke row "addArrangedSubview:" *field*)
    (objc:invoke row "addArrangedSubview:" button)
    (objc:invoke column "addArrangedSubview:" row)
    (setf *table* (ui:new "UITableView")
          *source* (ui:keep (make-instance 'ledger-source)))
    (objc:invoke *table* "setDataSource:" (objc:objc-object-pointer *source*))
    (objc:invoke column "addArrangedSubview:" *table*)
    (refresh)
    ;; LEDGER_ADD in the environment adds an entry at launch, so a run can
    ;; show the ledger growing without a finger on the screen.
    (let ((text (ext:getenv "LEDGER_ADD")))
      (when text (add text)))
    (format t "LEDGER: ~d entries; fingerprint(\"abc\") = ~a~%" (length *rows*) (fingerprint "abc"))
    (format t "LEDGER: newest: ~s~%" (first *rows*))
    (finish-output)
    (values)))

;;;; browser.lisp -- the running image, as a table view.
;;;;
;;;; UITableView asks its data source how many rows there are and for a cell
;;;; per row. Here the data source is an Objective-C class created at run time
;;;; whose methods are Lisp functions, and the rows are whatever the image
;;;; happens to contain -- so the app is browsing itself.
;;;;
;;;; Every signature involved is NSInteger and id, which is why this needs no
;;;; C compiler at build time. The one place a struct would have appeared,
;;;; -[UITableView initWithFrame:style:], is avoided by using -init.

(defpackage #:browser
  (:use #:cl)
  (:local-nicknames (#:oc #:objc-lite))
  (:export #:start))

(in-package #:browser)

(defvar *table* nil)
(defvar *title* nil)
(defvar *back* nil)

;;; ------------------------------------------------------------------
;;; the model
;;;
;;; A row is a title, a subtitle and, when it drills in, a thunk returning the
;;; next level. Keeping the whole model in ordinary Lisp is the point: none of
;;; it knows that a table view exists.

(defstruct (row (:constructor row (title subtitle &optional descend)))
  title subtitle descend)

(defstruct (level (:constructor level (title rows)))
  title rows)

(defvar *stack* '()
  "Levels, innermost first. The navigation is a list, because that is what it
is.")

(defun current-level () (first *stack*))

(defun package-symbols (package &key (external nil))
  (let ((symbols '()))
    (if external
        (do-external-symbols (symbol package) (push symbol symbols))
        (do-symbols (symbol package)
          (when (eq (symbol-package symbol) package)
            (push symbol symbols))))
    (sort (remove-duplicates symbols) #'string< :key #'symbol-name)))

(defun describe-symbol-briefly (symbol)
  (let ((parts '()))
    (when (fboundp symbol)
      (push (cond ((macro-function symbol) "macro")
                  ((typep (ignore-errors (fdefinition symbol))
                          'generic-function) "generic function")
                  (t "function"))
            parts))
    (when (boundp symbol)
      (push (if (constantp symbol) "constant" "variable") parts))
    (when (find-class symbol nil) (push "class" parts))
    (when (null parts) (push "symbol" parts))
    (format nil "~{~a~^, ~}" (nreverse parts))))

(defun symbol-level (symbol)
  (level (format nil "~a" symbol)
         (append
          (list (row "package" (package-name (symbol-package symbol)))
                (row "kind" (describe-symbol-briefly symbol)))
          (when (boundp symbol)
            (list (row "value" (let ((*print-length* 12) (*print-level* 3))
                                 (prin1-to-string (symbol-value symbol))))))
          (when (fboundp symbol)
            (list (row "lambda list"
                       (let ((arglist (ignore-errors
                                       (ext:function-lambda-list symbol))))
                         (if arglist (prin1-to-string arglist) "unknown")))))
          (let ((documentation (or (documentation symbol 'function)
                                   (documentation symbol 'variable))))
            (when documentation
              ;; One row per line: a table cell will not wrap, and a docstring
              ;; squeezed onto one line is not worth reading.
              (mapcar (lambda (line) (row "" (string-trim " " line)))
                      (remove "" (uiop-lines documentation) :test #'string=)))))))

(defun uiop-lines (string)
  "STRING split on newlines. Spelled out rather than pulled from UIOP, because
this example deliberately depends on nothing but objc-lite."
  (loop with start = 0
        for position = (position #\Newline string :start start)
        collect (subseq string start position)
        while position
        do (setf start (1+ position))))

(defun package-level (package)
  (let ((symbols (package-symbols package)))
    (level (package-name package)
           (if (null symbols)
               (list (row "(no symbols of its own)" ""))
               (mapcar (lambda (symbol)
                         (row (symbol-name symbol)
                              (describe-symbol-briefly symbol)
                              (lambda () (symbol-level symbol))))
                       symbols)))))

(defun packages-level ()
  (level "Packages"
         (mapcar (lambda (package)
                   (row (package-name package)
                        (format nil "~d symbol~:p~@[, ~a~]"
                                (length (package-symbols package))
                                (let ((nicknames (package-nicknames package)))
                                  (and nicknames
                                       (format nil "~{~a~^ ~}" nicknames))))
                        (lambda () (package-level package))))
                 (sort (copy-list (list-all-packages)) #'string<
                       :key #'package-name))))

;;; ------------------------------------------------------------------
;;; navigation

(defun show (new-level)
  (push new-level *stack*)
  (refresh))

(defun go-back ()
  (when (rest *stack*)
    (pop *stack*)
    (refresh))
  (values))

(defun refresh ()
  (oc:send *title* "setText:" (oc:nsstr (level-title (current-level))))
  (oc:send *back* "setHidden:" (if (rest *stack*) 0 1))
  (oc:send *table* "reloadData"))

;;; ------------------------------------------------------------------
;;; the data source
;;;
;;; Three methods, three Lisp functions. The Objective-C type encodings say
;;; what each one is: q is NSInteger, @ an object, : a selector, v void.
;;;
;;; Nothing here may signal. The caller is UIKit, and a condition unwinding
;;; through its frame corrupts it -- so each one ends in a value UIKit can
;;; live with rather than letting an error escape.

(defun safe-row (index)
  (let ((rows (level-rows (current-level))))
    (and (< -1 index (length rows)) (nth index rows))))

(ffi:defcallback rows-in-section :long
    ((self :pointer-void) (cmd :pointer-void)
     (table :pointer-void) (section :long))
  (declare (ignore self cmd table section))
  (handler-case (length (level-rows (current-level)))
    (serious-condition () 0)))

(ffi:defcallback cell-for-row :pointer-void
    ((self :pointer-void) (cmd :pointer-void)
     (table :pointer-void) (index-path :pointer-void))
  (declare (ignore self cmd))
  (handler-case
      (let* ((identifier (oc:nsstr "row"))
             (cell (oc:send table "dequeueReusableCellWithIdentifier:" identifier))
             (row (safe-row (oc:send-long index-path "row"))))
        (when (or (null cell) (si:null-pointer-p cell))
          ;; Style 3 is Subtitle: two labels, which is what a name and what it
          ;; is want.
          (setf cell (oc:send (oc:send (oc:cls "UITableViewCell") "alloc")
                              "initWithStyle:reuseIdentifier:" 3 identifier)))
        (oc:send (oc:send cell "textLabel") "setText:"
                 (oc:nsstr (if row (row-title row) "")))
        (oc:send (oc:send cell "detailTextLabel") "setText:"
                 (oc:nsstr (if row (row-subtitle row) "")))
        (oc:send (oc:send cell "detailTextLabel") "setFont:" (oc:mono-font 12))
        ;; A chevron only where there is somewhere to go.
        (oc:send cell "setAccessoryType:" (if (and row (row-descend row)) 1 0))
        cell)
    (serious-condition ()
      ;; An empty cell is a bad row; no cell at all is a crash.
      (oc:send (oc:send (oc:cls "UITableViewCell") "alloc")
               "initWithStyle:reuseIdentifier:" 0 (oc:nsstr "row")))))

(ffi:defcallback did-select-row :void
    ((self :pointer-void) (cmd :pointer-void)
     (table :pointer-void) (index-path :pointer-void))
  (declare (ignore self cmd))
  (handler-case
      (let ((row (safe-row (oc:send-long index-path "row"))))
        (oc:send table "deselectRowAtIndexPath:animated:" index-path 1)
        (when (and row (row-descend row))
          (show (funcall (row-descend row)))))
    (serious-condition () nil))
  (values))

(defun install-data-source (table)
  (let* ((class (oc:define-class "LispTableSource" "NSObject"
                  (list (list "tableView:numberOfRowsInSection:"
                              (ffi:callback 'rows-in-section) "q@:@q")
                        (list "tableView:cellForRowAtIndexPath:"
                              (ffi:callback 'cell-for-row) "@@:@@")
                        (list "tableView:didSelectRowAtIndexPath:"
                              (ffi:callback 'did-select-row) "v@:@@"))))
         ;; A table view holds both of these weakly.
         (source (oc:retain (oc:send (oc:send class "alloc") "init"))))
    (oc:send table "setDataSource:" source)
    (oc:send table "setDelegate:" source)
    source))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (oc:root-view))
         (safe (oc:send root "safeAreaLayoutGuide"))
         (title (oc:new "UILabel"))
         (back (oc:system-button "< Back"))
         (table (oc:new "UITableView")))

    (oc:send root "setBackgroundColor:" (oc:system-color "systemBackground"))

    (oc:send title "setFont:" (oc:send (oc:cls "UIFont") "boldSystemFontOfSize:" 22d0))
    (oc:send root "addSubview:" title)

    (oc:send back "setHidden:" 1)
    (oc:on-tap back "(browser::go-back)")
    (oc:send root "addSubview:" back)

    (oc:send root "addSubview:" table)

    (oc:pin title "topAnchor" safe "topAnchor" 10)
    (oc:pin title "leadingAnchor" safe "leadingAnchor" 16)
    (oc:pin back "centerYAnchor" title "centerYAnchor")
    (oc:pin back "trailingAnchor" safe "trailingAnchor" -16)
    (oc:pin table "topAnchor" title "bottomAnchor" 10)
    (oc:pin table "leadingAnchor" safe "leadingAnchor")
    (oc:pin table "trailingAnchor" safe "trailingAnchor")
    (oc:pin table "bottomAnchor" safe "bottomAnchor")

    (setf *table* table *title* title *back* back)
    (install-data-source table)
    (values)))

(defun start ()
  (build-interface)
  (setf *stack* '())
  (show (packages-level))
  (when (equal "1" (ext:getenv "BROWSER_DEMO"))
    (demonstrate-selection))
  (values))

;;; ------------------------------------------------------------------
;;; verifying the selection path without a finger
;;;
;;; A tap is the one thing a screenshot cannot produce, and simctl has no way
;;; to inject one. So this dispatches the delegate method the way UIKit does:
;;; a real NSIndexPath, sent to the real data source object with objc_msgSend.
;;; Everything downstream of that is identical to a tap.
;;;
;;; Gated on an environment variable so it does not disturb the app in normal
;;; use: SIMCTL_CHILD_BROWSER_DEMO=1 xcrun simctl launch ...

(defun row-index (title)
  (position title (level-rows (current-level)) :key #'row-title :test #'string=))

(defun tap-row (index)
  (let ((path (oc:send (oc:cls "NSIndexPath") "indexPathForRow:inSection:" index 0))
        (source (oc:send *table* "delegate")))
    (oc:send source "tableView:didSelectRowAtIndexPath:" *table* path)))

(defun demonstrate-selection ()
  (let ((package-row (row-index "COMMON-LISP")))
    (when package-row
      (tap-row package-row)
      (let ((symbol-row (row-index "DEFSTRUCT")))
        (when symbol-row
          (tap-row symbol-row))))))

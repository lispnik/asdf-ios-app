;;;; browser.lisp -- the running image, as a table view.
;;;;
;;;; UITableView asks its data source how many rows there are and for a cell
;;;; per row. Here the data source is an Objective-C class created at run time
;;;; whose methods are Lisp functions, and the rows are whatever the image
;;;; happens to contain -- so the app is browsing itself.
;;;;
;;;; The methods are libffi closures objc makes at run time, on the phone: no
;;;; C compiler at build time, and no trampoline file.

(defpackage #:browser
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
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
this example deliberately depends on nothing but objc."
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
  (objc:invoke *title* "setText:" (level-title (current-level)))
  (objc:invoke *back* "setHidden:" (not (rest *stack*)))
  (objc:invoke *table* "reloadData"))

;;; ------------------------------------------------------------------
;;; the data source
;;;
;;; Three methods, three Lisp bodies, on an Objective-C class defined here.
;;; The type descriptors say what each one is to the runtime: NSInteger is
;;; (:signed :long-long), an object is objc:objc-object-pointer.
;;;
;;; Nothing here may signal. The caller is UIKit, and a condition unwinding
;;; through its frame corrupts it -- so each one ends in a value UIKit can
;;; live with rather than letting an error escape.

(defun safe-row (index)
  (let ((rows (level-rows (current-level))))
    (and (< -1 index (length rows)) (nth index rows))))

(objc:define-objc-class table-source ()
  ()
  (:objc-class-name "LispTableSource"))

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self table-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (handler-case (length (level-rows (current-level)))
    (serious-condition () 0)))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self table-source) (table objc:objc-object-pointer) (index-path objc:objc-object-pointer))
  (handler-case
      (let* ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "row"))
             (row (safe-row (objc:invoke index-path "row"))))
        (when (cffi:null-pointer-p cell)
          ;; Style 3 is Subtitle: two labels, which is what a name and what it
          ;; is want.
          (setf cell (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                  "initWithStyle:reuseIdentifier:" 3 "row")))
        (objc:invoke (objc:invoke cell "textLabel") "setText:"
                     (if row (row-title row) ""))
        (objc:invoke (objc:invoke cell "detailTextLabel") "setText:"
                     (if row (row-subtitle row) ""))
        (objc:invoke (objc:invoke cell "detailTextLabel") "setFont:" (ui:mono-font 12))
        ;; A chevron only where there is somewhere to go.
        (objc:invoke cell "setAccessoryType:" (if (and row (row-descend row)) 1 0))
        cell)
    (serious-condition ()
      ;; An empty cell is a bad row; no cell at all is a crash.
      (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                   "initWithStyle:reuseIdentifier:" 0 "row"))))

(objc:define-objc-method ("tableView:didSelectRowAtIndexPath:" :void)
    ((self table-source) (table objc:objc-object-pointer) (index-path objc:objc-object-pointer))
  (handler-case
      (let ((row (safe-row (objc:invoke index-path "row"))))
        (objc:invoke table "deselectRowAtIndexPath:animated:" index-path t)
        (when (and row (row-descend row))
          (show (funcall (row-descend row)))))
    (serious-condition () nil))
  (values))

(defun install-data-source (table)
  ;; A table view holds both of these weakly.
  (let* ((source (ui:keep (make-instance 'table-source)))
         (pointer (objc:objc-object-pointer source)))
    (objc:invoke table "setDataSource:" pointer)
    (objc:invoke table "setDelegate:" pointer)
    source))

;;; ------------------------------------------------------------------
;;; the interface

(defun build-interface ()
  (let* ((root (ui:root-view))
         (safe (objc:invoke root "safeAreaLayoutGuide"))
         (title (ui:new "UILabel"))
         (back (ui:system-button "< Back"))
         (table (ui:new "UITableView")))

    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))

    (objc:invoke title "setFont:" (ui:bold-font 22))
    (objc:invoke root "addSubview:" title)

    (objc:invoke back "setHidden:" t)
    (ui:on-tap back (lambda (sender) (declare (ignore sender)) (go-back)))
    (objc:invoke root "addSubview:" back)

    (objc:invoke root "addSubview:" table)

    (ui:pin title "topAnchor" safe "topAnchor" 10)
    (ui:pin title "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin back "centerYAnchor" title "centerYAnchor")
    (ui:pin back "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin table "topAnchor" title "bottomAnchor" 10)
    (ui:pin table "leadingAnchor" safe "leadingAnchor")
    (ui:pin table "trailingAnchor" safe "trailingAnchor")
    (ui:pin table "bottomAnchor" safe "bottomAnchor")

    (setf *table* table *title* title *back* back)
    (install-data-source table)
    (values)))

(defun start ()
  (objc:ensure-objc-initialized)
  (build-interface)
  (setf *stack* '())
  (show (packages-level))
  (let ((demo (ext:getenv "BROWSER_DEMO")))
    (cond ((equal demo "1") (demonstrate-selection))
          ((equal demo "tour") (start-tour))))
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
  (let ((path (objc:invoke "NSIndexPath" "indexPathForRow:inSection:" index 0))
        (source (objc:invoke *table* "delegate")))
    (objc:invoke source "tableView:didSelectRowAtIndexPath:" *table* path)))

(defun scroll-to-row (index &key (position 1))
  "Scroll INDEX into view. POSITION 1 is UITableViewScrollPositionTop.

-scrollToRowAtIndexPath:atScrollPosition:animated: is NSIndexPath, NSInteger,
BOOL."
  (let ((rows (length (level-rows (current-level)))))
    (when (< -1 index rows)
      (objc:invoke *table* "scrollToRowAtIndexPath:atScrollPosition:animated:"
                   (objc:invoke "NSIndexPath" "indexPathForRow:inSection:" index 0)
                   position t))))

(defun highlight-row (index)
  "Select INDEX the way a finger would, so the row flashes before it acts."
  (let ((rows (length (level-rows (current-level)))))
    (when (< -1 index rows)
      (objc:invoke *table* "selectRowAtIndexPath:animated:scrollPosition:"
                   (objc:invoke "NSIndexPath" "indexPathForRow:inSection:" index 0)
                   t 0))))

(defun demonstrate-selection ()
  "The original two-step check: drill into COMMON-LISP, then into DEFSTRUCT."
  (let ((package-row (row-index "COMMON-LISP")))
    (when package-row
      (tap-row package-row)
      (let ((symbol-row (row-index "DEFSTRUCT")))
        (when symbol-row
          (tap-row symbol-row))))))

;;; ------------------------------------------------------------------
;;; a tour, for recording
;;;
;;; The same dispatch as above, spread over time so a person -- or a screen
;;; recorder -- can follow it. Steps are ordinary closures run by a repeating
;;; NSTimer; NIL is a beat, which is how a pause is spelled.

(defvar *tour* '())
(defvar *tour-timer* nil)

(defun enter (title)
  "Scroll TITLE into view, select it, and follow it -- as three steps."
  (let ((index nil))
    (list (lambda () (setf index (row-index title))
            (when index (scroll-to-row (max 0 (- index 2)))))
          (lambda () (when index (highlight-row index)))
          (lambda () (when index (tap-row index))))))

(defun tour-steps ()
  (append
   (list nil nil)
   ;; Down the package list and into COMMON-LISP.
   (list (lambda () (scroll-to-row 12)) nil
         (lambda () (scroll-to-row 4)) nil)
   (enter "COMMON-LISP")
   (list nil)
   ;; A macro, with its lambda list and docstring.
   (enter "DEFSTRUCT")
   (list nil nil (lambda () (scroll-to-row 6)) nil nil nil
         (lambda () (go-back)) nil)
   ;; A function, to show the kind line changing.
   (enter "MAPCAR")
   (list nil nil nil (lambda () (go-back)) nil
         (lambda () (go-back)) nil)
   ;; The library the app is built on: the image is browsing the code that
   ;; built it.
   (enter "OBJC")
   (list nil)
   (enter "INVOKE")
   (list nil nil nil
         (lambda () (go-back)) nil
         (lambda () (go-back)) nil nil)))

(defun stop-tour ()
  (when *tour-timer*
    (objc:invoke *tour-timer* "invalidate")
    (ui:unkeep *tour-timer*)
    (setf *tour-timer* nil))
  (values))

(defun tour-tick ()
  ;; Emptiness is checked BEFORE popping. Checking after drops the last step,
  ;; which in a tour is the one that puts the app back where it started.
  (if (null *tour*)
      (stop-tour)
      (let ((step (pop *tour*)))
        ;; A step must not signal: the caller is a UIKit timer.
        (when step (ignore-errors (funcall step)))))
  (values))

(defun start-tour ()
  (setf *tour* (tour-steps))
  (setf *tour-timer* (ui:after-every 0.9 (lambda (timer) (declare (ignore timer)) (tour-tick))))
  (values))

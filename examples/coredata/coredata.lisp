;;;; coredata.lisp -- the framework way to persist, from Lisp.
;;;;
;;;; The ledger example drove SQLite by hand. Core Data is Apple's layer
;;;; over it: a model of entities and attributes, a container that opens
;;;; the store, a context that holds objects, and fetch requests with
;;;; predicates and sorts. Everything Xcode would put in a .xcdatamodeld
;;;; is built in code here, from Lisp, at launch. The store is the same
;;;; SQLite file underneath, in the app's Application Support directory,
;;;; and the notes survive relaunches.

(defpackage #:coredata
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:add-note #:notes))

(in-package #:coredata)

(defvar *container* nil)
(defvar *context* nil)
(defvar *status* nil)
(defvar *table* nil)
(defvar *field* nil)
(defvar *rows* '())

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "COREDATA: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

;;; ------------------------------------------------------------------
;;; the model, in code

(defconstant +string-type+ 700)
(defconstant +integer-64-type+ 300)
(defconstant +date-type+ 900)

(defun attribute (name type &key optional)
  (let ((attribute (objc:alloc-init-object "NSAttributeDescription")))
    (objc:invoke attribute "setName:" name)
    (objc:invoke attribute "setAttributeType:" type)
    (objc:invoke attribute "setOptional:" optional)
    attribute))

(defun model ()
  "One entity, Note, with a body, a number of words and a date."
  (let ((entity (objc:alloc-init-object "NSEntityDescription"))
        (model (objc:alloc-init-object "NSManagedObjectModel")))
    (objc:invoke entity "setName:" "Note")
    (objc:invoke entity "setManagedObjectClassName:" "NSManagedObject")
    (objc:invoke entity "setProperties:" (vector (attribute "body" +string-type+)
                                                 (attribute "words" +integer-64-type+)
                                                 (attribute "made" +date-type+)))
    (objc:invoke model "setEntities:" (vector entity))
    model))

;;; ------------------------------------------------------------------
;;; the container, loaded through a block

(objc:define-objc-block-type store-loaded :void (objc:objc-object-pointer objc:objc-object-pointer))

(defun open-store (then)
  (setf *container* (ui:keep (objc:invoke (objc:invoke (objc:invoke "NSPersistentContainer" "alloc")
                                                        "initWithName:managedObjectModel:" "Notes" (model))
                                           "autorelease")))
  (objc:with-objc-block (loaded 'store-loaded
                                (lambda (description error)
                                  (ios-app-runtime:on-main
                                   (lambda ()
                                     (if (cffi:null-pointer-p error)
                                         (progn
                                           (setf *context* (ui:keep (objc:invoke *container* "viewContext")))
                                           (say "store at ~a"
                                                (file-namestring
                                                 (objc:ns-string-to-string
                                                  (objc:invoke (objc:invoke description "URL") "path"))))
                                           (funcall then))
                                         (say "could not load the store: ~a"
                                              (objc:ns-string-to-string (objc:invoke error "localizedDescription"))))))))
    (objc:invoke *container* "loadPersistentStoresWithCompletionHandler:" loaded)))

;;; ------------------------------------------------------------------
;;; insert, save, fetch

(defun add-note (body)
  (let ((note (objc:invoke "NSEntityDescription" "insertNewObjectForEntityForName:inManagedObjectContext:"
                           "Note" *context*)))
    (objc:invoke note "setValue:forKey:" body "body")
    (objc:invoke note "setValue:forKey:"
                 (objc:invoke "NSNumber" "numberWithLongLong:" (length (remove "" (uiop:split-string body :separator " ") :test #'string=)))
                 "words")
    (objc:invoke note "setValue:forKey:" (objc:invoke "NSDate" "date") "made")
    (cffi:with-foreign-object (error :pointer)
      (setf (cffi:mem-ref error :pointer) (cffi:null-pointer))
      (unless (objc:invoke-bool *context* "save:" error)
        (say "save failed: ~a" (objc:ns-string-to-string (objc:invoke (cffi:mem-ref error :pointer) "localizedDescription")))))
    (refresh)
    body))

(defun notes (&key (at-least 0))
  "Notes with at least AT-LEAST words, newest first: (body words made)."
  (let ((request (objc:invoke "NSFetchRequest" "fetchRequestWithEntityName:" "Note")))
    ;; A predicate from a format with an argument array: the variadic form
    ;; is the one thing not to call through the bridge.
    (objc:invoke request "setPredicate:"
                 (objc:invoke "NSPredicate" "predicateWithFormat:argumentArray:" "words >= %@"
                              (vector (objc:invoke "NSNumber" "numberWithLongLong:" at-least))))
    (objc:invoke request "setSortDescriptors:"
                 (vector (objc:invoke "NSSortDescriptor" "sortDescriptorWithKey:ascending:" "made" nil)))
    (let ((results (objc:invoke *context* "executeFetchRequest:error:" request nil)))
      (loop for i below (objc:invoke results "count")
            for note = (objc:invoke results "objectAtIndex:" i)
            collect (list (objc:ns-string-to-string (objc:invoke note "valueForKey:" "body"))
                          (objc:invoke (objc:invoke note "valueForKey:" "words") "longLongValue")
                          (objc:ns-string-to-string (objc:invoke (objc:invoke note "valueForKey:" "made") "description")))))))

;;; ------------------------------------------------------------------
;;; the table

(objc:define-objc-class note-source () () (:objc-class-name "LispNoteSource"))

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self note-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (length *rows*))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self note-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "note"))
            (row (nth (objc:invoke path "row") *rows*)))
        (when (cffi:null-pointer-p cell)
          (setf cell (objc:invoke (objc:invoke "UITableViewCell" "alloc") "initWithStyle:reuseIdentifier:" 3 "note")))
        (destructuring-bind (body words made) (or row '("" 0 ""))
          (objc:invoke (objc:invoke cell "textLabel") "setText:" body)
          (objc:invoke (objc:invoke cell "detailTextLabel") "setText:" (format nil "~d word~:p · ~a" words (subseq made 0 (min 19 (length made))))))
        cell)
    (serious-condition ()
      (objc:invoke (objc:invoke "UITableViewCell" "alloc") "initWithStyle:reuseIdentifier:" 0 "note"))))

(defvar *source* nil)

(defun refresh ()
  (setf *rows* (notes))
  (let ((total (length *rows*)) (long (length (notes :at-least 4))))
    (say "~d note~:p; ~d with four words or more, by a fetch with a predicate" total long))
  (objc:invoke *table* "reloadData"))

(defun add-from-field ()
  (let ((text (objc:ns-string-to-string (objc:invoke *field* "text"))))
    (when (plusp (length (string-trim " " text)))
      (add-note text)
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
    (objc:invoke column "addArrangedSubview:" (label "Notes, in Core Data" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "The model built in code; the container loaded through a block; objects inserted and saved; a fetch with a predicate and a sort. Still here after a relaunch." :size 13))
    (setf *status* (label "" :size 12 :lines 2))
    (objc:invoke column "addArrangedSubview:" *status*)
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 8)
    (setf *field* (ui:new "UITextField"))
    (objc:invoke *field* "setBorderStyle:" 3)
    (objc:invoke *field* "setPlaceholder:" "A note")
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (add-from-field)))
    (objc:invoke row "addArrangedSubview:" *field*)
    (objc:invoke row "addArrangedSubview:" button)
    (objc:invoke column "addArrangedSubview:" row)
    (setf *table* (ui:new "UITableView")
          *source* (ui:keep (make-instance 'note-source)))
    (objc:invoke *table* "setDataSource:" (objc:objc-object-pointer *source*))
    (objc:invoke column "addArrangedSubview:" *table*)
    (open-store (lambda ()
                  (let ((text (ext:getenv "COREDATA_ADD")))
                    (when text (add-note text)))
                  (refresh)))
    (values)))

;;;; agenda.lisp -- the calendar and the contacts, from Lisp.
;;;;
;;;; Two of the frameworks every ordinary app touches, neither seen in an
;;;; example before. Both are permission gated: access is asked for through
;;;; a completion block, which is a Lisp closure here, called on a thread
;;;; of the framework's choosing. EventKit then answers queries with
;;;; arrays; Contacts enumerates through a block called once per contact,
;;;; with a stop flag to write through. What Lisp adds is the ordinary
;;;; part: dates from universal time, events made and saved, contacts
;;;; grouped by initial.

(defpackage #:agenda
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:add-event #:refresh))

(in-package #:agenda)

(defvar *text* nil)
(defvar *status* nil)

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "AGENDA: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

(defun show (lines)
  (objc:invoke *text* "setText:" (format nil "~{~a~%~}" lines))
  (dolist (line lines) (format t "AGENDA: ~a~%" line))
  (finish-output))

;;; ------------------------------------------------------------------
;;; dates: NSDate from universal time, and back

(defconstant +unix-epoch+ (encode-universal-time 0 0 0 1 1 1970 0))

(defun ns-date (universal-time)
  (objc:invoke "NSDate" "dateWithTimeIntervalSince1970:" (float (- universal-time +unix-epoch+) 1d0)))

(defun universal-time-of (ns-date)
  (+ +unix-epoch+ (round (objc:invoke ns-date "timeIntervalSince1970"))))

(defun day-and-time (universal-time)
  (multiple-value-bind (s m h day month) (decode-universal-time universal-time)
    (declare (ignore s))
    (format nil "~2,'0d/~2,'0d ~2,'0d:~2,'0d" day month h m)))

;;; ------------------------------------------------------------------
;;; the calendar

(objc:define-objc-block-type access-reply :void (objc:objc-c++-bool objc:objc-object-pointer))

(defvar *store* nil)

(defun event-store ()
  (or *store* (setf *store* (ui:keep (objc:alloc-init-object "EKEventStore")))))

(defun week-events ()
  "Every event in the seven days from now: (start title)."
  (let* ((now (get-universal-time))
         (predicate (objc:invoke (event-store) "predicateForEventsWithStartDate:endDate:calendars:"
                                 (ns-date now) (ns-date (+ now (* 7 24 3600))) nil))
         (events (objc:invoke (event-store) "eventsMatchingPredicate:" predicate)))
    (sort (loop for i below (objc:invoke events "count")
                for event = (objc:invoke events "objectAtIndex:" i)
                collect (list (universal-time-of (objc:invoke event "startDate"))
                              (objc:ns-string-to-string (objc:invoke event "title"))))
          #'< :key #'first)))

(defun add-event (title &key (in-hours 2) (minutes 45))
  "An event IN-HOURS from now, in the default calendar, saved."
  (let* ((start (+ (get-universal-time) (* in-hours 3600)))
         (event (objc:invoke "EKEvent" "eventWithEventStore:" (event-store))))
    (objc:invoke event "setTitle:" title)
    (objc:invoke event "setStartDate:" (ns-date start))
    (objc:invoke event "setEndDate:" (ns-date (+ start (* minutes 60))))
    (objc:invoke event "setCalendar:" (objc:invoke (event-store) "defaultCalendarForNewEvents"))
    (cffi:with-foreign-object (error :pointer)
      (setf (cffi:mem-ref error :pointer) (cffi:null-pointer))
      (let ((ok (objc:invoke-bool (event-store) "saveEvent:span:error:" event 0 error)))
        (unless ok
          (say "could not save: ~a"
               (objc:ns-string-to-string (objc:invoke (cffi:mem-ref error :pointer) "localizedDescription"))))
        ok))))

;;; ------------------------------------------------------------------
;;; the contacts

(objc:define-objc-block-type contact-visitor :void (objc:objc-object-pointer (:pointer objc:objc-c++-bool)))

(defun contacts-by-initial ()
  "((initial . (name ...)) ...), enumerated through a block called per contact."
  (let* ((store (objc:alloc-init-object "CNContactStore"))
         (keys (vector "givenName" "familyName"))
         (request (objc:invoke (objc:invoke (objc:invoke "CNContactFetchRequest" "alloc")
                                            "initWithKeysToFetch:" keys)
                               "autorelease"))
         (names '()))
    (objc:with-objc-block (visitor 'contact-visitor
                                   (lambda (contact stop)
                                     (declare (ignore stop))
                                     (let ((given (objc:ns-string-to-string (objc:invoke contact "givenName")))
                                           (family (objc:ns-string-to-string (objc:invoke contact "familyName"))))
                                       (push (string-trim " " (format nil "~a ~a" given family)) names))))
      (objc:invoke store "enumerateContactsWithFetchRequest:error:usingBlock:" request nil visitor))
    (let ((groups (make-hash-table :test #'equal)))
      (dolist (name (sort names #'string<))
        (push name (gethash (if (plusp (length name)) (string-upcase (subseq name 0 1)) "?") groups)))
      (sort (loop for initial being the hash-keys of groups using (hash-value members)
                  collect (cons initial (nreverse members)))
            #'string< :key #'car))))

;;; ------------------------------------------------------------------
;;; putting it on screen

(defun refresh ()
  (let ((events (week-events))
        (groups (contacts-by-initial)))
    (say "~d event~:p this week; ~d contact~:p in ~d group~:p"
         (length events) (reduce #'+ groups :key (lambda (g) (length (cdr g)))) (length groups))
    (show (append (list "THIS WEEK")
                  (or (loop for (start title) in events collect (format nil "  ~a  ~a" (day-and-time start) title))
                      (list "  nothing"))
                  (list "" "CONTACTS")
                  (loop for (initial . members) in groups
                        collect (format nil "  ~a  ~{~a~^, ~}" initial members))))))

(defun request-everything (then)
  "Calendar access, then contacts access, then THEN, all on the main thread."
  (objc:with-objc-block (calendar 'access-reply
                                  (lambda (granted error)
                                    (declare (ignore error))
                                    (ios-app-runtime:on-main
                                     (lambda ()
                                       (if (not granted)
                                           (say "calendar access refused")
                                           (objc:with-objc-block (contacts 'access-reply
                                                                           (lambda (granted error)
                                                                             (declare (ignore error))
                                                                             (ios-app-runtime:on-main
                                                                              (lambda ()
                                                                                (if granted (funcall then) (say "contacts access refused"))))))
                                             (objc:invoke (objc:alloc-init-object "CNContactStore")
                                                          "requestAccessForEntityType:completionHandler:" 0 contacts)))))))
    (objc:invoke (event-store) "requestFullAccessToEventsWithCompletion:" calendar)))

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
         (button (ui:system-button "Add a meeting in two hours")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "The week and the contacts, in Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "EventKit and Contacts: access through blocks, events made here and listed, contacts enumerated through a block and grouped by initial." :size 13))
    (setf *status* (label "" :size 12))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *text* (ui:new "UITextView"))
    (objc:invoke *text* "setEditable:" nil)
    (objc:invoke *text* "setFont:" (ui:mono-font 12))
    (objc:invoke *text* "setBackgroundColor:" (ui:system-color "secondarySystemBackground"))
    (objc:invoke (objc:invoke *text* "layer") "setCornerRadius:" 8)
    (objc:invoke column "addArrangedSubview:" *text*)
    (ui:on-tap button (lambda (sender) (declare (ignore sender))
                        (when (add-event "Lisp meeting") (refresh))))
    (objc:invoke column "addArrangedSubview:" button)
    (request-everything
     (lambda ()
       ;; AGENDA_SEED=1 puts two events in first, for a week that has some.
       (when (ext:getenv "AGENDA_SEED")
         (add-event "Lisp meeting" :in-hours 2)
         (add-event "Rebuild the phone" :in-hours 26 :minutes 90))
       (refresh)))
    (values)))

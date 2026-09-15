;;;; favourites.lisp -- the songs favourited in Music, listed by Lisp.
;;;;
;;;; MediaPlayer is the framework that reads the phone's music library, and
;;;; MPMediaQuery is its question: all the songs, all the playlists, filtered
;;;; and grouped.  Since iOS 17.2 a song favourited in Music -- the star --
;;;; lands in a playlist the system keeps called Favorite Songs, so the
;;;; favourites are that playlist's items: found by name among the library's
;;;; playlists, then read out one property at a time through
;;;; -valueForProperty:, which is how MPMediaItem answers for everything.
;;;;
;;;; Access is asked for first, through MPMediaLibrary's block, which arrives
;;;; on a thread of the framework's and is bounced to the main thread before
;;;; it touches the table.  Where there is no such playlist -- a library
;;;; without favourites, or an older iOS -- the songs rated four stars or
;;;; more stand in, and failing those the most played.  A simulator has no
;;;; library at all, and says so; this one is for the phone.

(defpackage #:favourites-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:reload #:*songs*))

(in-package #:favourites-ios)

(defvar *songs* '() "The rows: (title artist album seconds plays), in playlist order.")
(defvar *status* nil)
(defvar *table* nil)
(defvar *source* nil)

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "FAVOURITES: ~a~%" text)
    (finish-output)
    (when *status* (objc:invoke *status* "setText:" text))))

;;; ------------------------------------------------------------------
;;; the library

(defconstant +authorized+ 3 "MPMediaLibraryAuthorizationStatusAuthorized.")

(objc:define-objc-block-type authorization-reply :void ((:signed :long-long)))

(defun property (item name &key (as :string))
  "One MPMediaItem or MPMediaPlaylist property, by the key the framework
publishes: valueForProperty: answers an NSString, an NSNumber, or nil."
  (let ((value (objc:invoke item "valueForProperty:" name)))
    (cond ((cffi:null-pointer-p value) (ecase as (:string "") (:number 0)))
          ((eq as :string) (objc:ns-string-to-string value))
          (t (objc:invoke value "doubleValue")))))

(defun playlist-named (pattern)
  "The library playlist whose name contains PATTERN, ignoring case, or NIL."
  (let* ((query (objc:invoke "MPMediaQuery" "playlistsQuery"))
         (playlists (objc:invoke query "collections")))
    (loop for i below (objc:invoke playlists "count")
          for playlist = (objc:invoke playlists "objectAtIndex:" i)
          when (search pattern (string-downcase (property playlist "name")))
            return playlist)))

(defun rows-of (items &key (limit 200))
  (loop for i below (min limit (objc:invoke items "count"))
        for item = (objc:invoke items "objectAtIndex:" i)
        collect (list (property item "title")
                      (property item "artist")
                      (property item "albumTitle")
                      (property item "playbackDuration" :as :number)
                      (round (property item "playCount" :as :number)))))

(defun favourite-songs ()
  "(VALUES ROWS HOW TOTAL): the Favorite Songs playlist, else songs rated
four stars or more, else the most played; which of those it was; and how
many there are, since ROWS stops at two hundred."
  (let ((favourites (or (playlist-named "favorite songs") (playlist-named "favourite songs"))))
    (if favourites
        (let ((items (objc:invoke favourites "items")))
          (values (rows-of items) "the Favorite Songs playlist" (objc:invoke items "count")))
        (let* ((songs (objc:invoke (objc:invoke "MPMediaQuery" "songsQuery") "items"))
               (rated (loop for i below (objc:invoke songs "count")
                            for item = (objc:invoke songs "objectAtIndex:" i)
                            when (>= (property item "rating" :as :number) 4)
                              collect item)))
          (if rated
              (values (rows-of (objc:invoke "NSArray" "arrayWithArray:" (coerce rated 'vector)))
                      "songs rated four stars or more" (length rated))
              (let ((rows (rows-of songs :limit 5000)))
                (values (subseq (sort rows #'> :key #'fifth) 0 (min 40 (length rows)))
                        "the most played songs; nothing is favourited or rated"
                        (length rows))))))))

(defun reload ()
  "Ask for the library, then list, on the main thread."
  (objc:with-objc-block (reply 'authorization-reply
                               (lambda (status)
                                 (ios-app-runtime:on-main
                                  (lambda ()
                                    (if (/= status +authorized+)
                                        (say "media library access ~a" (case status (1 "denied") (2 "restricted") (t "not determined")))
                                        (handler-case
                                            (multiple-value-bind (rows how total) (favourite-songs)
                                              (setf *songs* rows)
                                              (objc:invoke *table* "reloadData")
                                              (say "~d song~:p from ~a~@[, first ~d listed~]"
                                                   total how (and (< (length rows) total) (length rows)))
                                              (loop for (title artist album seconds plays) in rows
                                                    for i from 1 to 30
                                                    do (format t "FAVOURITES:   ~a — ~a (~a) ~d:~2,'0d, played ~d~%"
                                                               title artist album (floor seconds 60) (mod (round seconds) 60) plays))
                                              (finish-output))
                                          (error (e) (say "could not read the library: ~a" e))))))))
    (objc:invoke "MPMediaLibrary" "requestAuthorization:" reply)))

;;; ------------------------------------------------------------------
;;; the table, its data source a Lisp class

(objc:define-objc-class song-source () () (:objc-class-name "SongSource"))

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self song-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (length *songs*))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self song-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "song"))
            (row (nth (objc:invoke path "row") *songs*)))
        (when (cffi:null-pointer-p cell)
          (setf cell (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                  "initWithStyle:reuseIdentifier:" 3 "song")))
        (destructuring-bind (title artist album seconds plays) (or row '("" "" "" 0 0))
          (objc:invoke (objc:invoke cell "textLabel") "setText:" title)
          (objc:invoke (objc:invoke cell "detailTextLabel") "setText:"
                       (format nil "~a — ~a · ~d:~2,'0d · played ~d"
                               artist album (floor seconds 60) (mod (round seconds) 60) plays)))
        cell)
    (serious-condition ()
      (objc:invoke (objc:invoke "UITableViewCell" "alloc") "initWithStyle:reuseIdentifier:" 0 "song"))))

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
         (button (ui:system-button "Reload")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Favourited in Music, listed by Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "MediaPlayer's authorisation through a block; the Favorite Songs playlist found with MPMediaQuery; each song read property by property; the table's data source a Lisp class." :size 13))
    (setf *status* (label "" :size 12 :lines 2))
    (objc:invoke *status* "setFont:" (ui:mono-font 11))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *table* (ui:new "UITableView")
          *source* (ui:keep (make-instance 'song-source)))
    (objc:invoke *table* "setDataSource:" (objc:objc-object-pointer *source*))
    (objc:invoke column "addArrangedSubview:" *table*)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (reload)))
    (objc:invoke column "addArrangedSubview:" button)
    (reload)
    (values)))

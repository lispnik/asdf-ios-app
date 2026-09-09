;;;; bundle.lisp -- the shape of an iOS .app, and what goes in its Info.plist.
;;;;
;;;; An iOS bundle is flat. There is no Contents/, no MacOS/, no Resources/:
;;;; the executable, Info.plist and every resource sit side by side at the top
;;;; level. That is why the resource-destination checks matter more here than
;;;; on macOS -- a resource called "Info.plist" does not land somewhere harmless,
;;;; it lands on the Info.plist.

(in-package #:asdf-ios-app)

(defstruct (app-spec (:conc-name spec-))
  root                                  ; where we are building right now
  final-root                            ; where it ends up on success
  platform                              ; an IOS-PLATFORM
  (name "App")                          ; CFBundleName
  display-name                          ; CFBundleDisplayName
  identifier                            ; CFBundleIdentifier (required)
  (version "0.0.0")                     ; CFBundleVersion
  short-version                         ; CFBundleShortVersionString
  (executable-name "app")               ; <root>/<this>
  (minimum-os-version "15.0")           ; MinimumOSVersion, NOT LSMinimumSystemVersion
  (device-family '(:iphone :ipad))      ; UIDeviceFamily
  (orientations '(:portrait))           ; UISupportedInterfaceOrientations
  ipad-orientations                     ; ...~ipad, when it differs
  (launch-screen t)                     ; UILaunchScreen; T is an empty dict
  (required-capabilities '("arm64"))    ; UIRequiredDeviceCapabilities
  status-bar-hidden-p                   ; UIStatusBarHidden
  category                              ; LSApplicationCategoryType
  copyright                             ; NSHumanReadableCopyright
  url-schemes                           ; list of strings
  document-types                        ; list of DSL dicts
  extra-plist                           ; alist of key -> DSL value
  resources                             ; extra files for the bundle root
  ecl-modules                           ; ("sockets" ...) linked and initialised
  (frameworks '("UIKit" "Foundation"))  ; -framework arguments
  static-libraries                      ; extra .a to link
  link-flags                            ; extra clang arguments
  (signing-identity :automatic)         ; :AUTOMATIC, NIL, "-", or an identity
  team-id
  provisioning-profile
  (entitlements :ios-default)
  (get-task-allow-p t))

;;; ------------------------------------------------------------------
;;; layout

(defun bundle-file (spec name)
  (uiop:subpathname (spec-root spec) name))

(defun executable-path (spec)
  (bundle-file spec (spec-executable-name spec)))

(defun info-plist-path (spec)
  (bundle-file spec "Info.plist"))

(defun pkginfo-path (spec)
  (bundle-file spec "PkgInfo"))

(defun provisioning-profile-path (spec)
  (bundle-file spec "embedded.mobileprovision"))

(defun lisp-directory (spec)
  (uiop:subpathname (spec-root spec) "lisp/"))

(defun make-skeleton (spec &key clean)
  (when (and clean (probe-file (spec-root spec)))
    (uiop:delete-directory-tree (spec-root spec) :validate t))
  (ensure-directories-exist (spec-root spec))
  (spec-root spec))

;;; ------------------------------------------------------------------
;;; Info.plist

(defun sanitize-version (version &optional what)
  "Apple accepts one to three period-separated integers and nothing else, so
\"1.4.2-alpha\" or an ASDF version with a git suffix is rejected outright.
Reduce to the leading numeric components."
  (let* ((parts (uiop:split-string (or version "") :separator "."))
         (numeric (loop for part in parts
                        for digits = (subseq part 0 (or (position-if-not #'digit-char-p part)
                                                        (length part)))
                        while (plusp (length digits))
                        collect (princ-to-string (parse-integer digits))))
         (kept (subseq numeric 0 (min 3 (length numeric))))
         (result (if kept (format nil "~{~a~^.~}" kept) "0")))
    (when (and what (string/= result (or version "")))
      (note "~a ~s is not an Apple version; using ~s" what version result))
    result))

(defparameter +orientation-names+
  '((:portrait . "UIInterfaceOrientationPortrait")
    (:portrait-upside-down . "UIInterfaceOrientationPortraitUpsideDown")
    (:landscape-left . "UIInterfaceOrientationLandscapeLeft")
    (:landscape-right . "UIInterfaceOrientationLandscapeRight")))

(defun orientation-name (keyword)
  (or (cdr (assoc keyword +orientation-names+))
      (barf "Unknown orientation ~s. Expected one of ~{~s~^, ~}."
            keyword (mapcar #'car +orientation-names+))))

(defparameter +device-family-numbers+
  '((:iphone . 1) (:ipad . 2))
  "UIDeviceFamily is a list of small integers, and nobody remembers which.")

(defun device-family-number (keyword)
  (or (cdr (assoc keyword +device-family-numbers+))
      (barf "Unknown device family ~s. Expected :IPHONE or :IPAD." keyword)))

(defun info-plist-form (spec)
  (let* ((platform (spec-platform spec))
         (base
           `(:dict
             ("CFBundleInfoDictionaryVersion" . "6.0")
             ("CFBundlePackageType"           . "APPL")
             ("CFBundleSignature"             . "????")
             ("CFBundleName"                  . ,(spec-name spec))
             ("CFBundleDisplayName"           . ,(or (spec-display-name spec)
                                                     (spec-name spec)))
             ("CFBundleExecutable"            . ,(spec-executable-name spec))
             ("CFBundleIdentifier"            . ,(or (spec-identifier spec)
                                                     (barf "BUNDLE-IDENTIFIER is required.")))
             ("CFBundleVersion"               . ,(sanitize-version
                                                  (spec-version spec) "Version"))
             ("CFBundleShortVersionString"    . ,(sanitize-version
                                                  (or (spec-short-version spec)
                                                      (spec-version spec))
                                                  "Short version"))
             ;; iOS spells this differently from macOS, and using the macOS key
             ;; produces a bundle that installs and then will not launch.
             ("MinimumOSVersion"              . ,(spec-minimum-os-version spec))
             ("LSRequiresIPhoneOS"            . :true)
             ("CFBundleSupportedPlatforms"
              . (:array ,(platform-plist-platform platform)))
             ("UIDeviceFamily"
              . (:array ,@(mapcar #'device-family-number
                                  (spec-device-family spec))))
             ("UISupportedInterfaceOrientations"
              . (:array ,@(mapcar #'orientation-name (spec-orientations spec))))
             ,@(when (spec-ipad-orientations spec)
                 `(("UISupportedInterfaceOrientations~ipad"
                    . (:array ,@(mapcar #'orientation-name
                                        (spec-ipad-orientations spec))))))
             ,@(when (spec-required-capabilities spec)
                 `(("UIRequiredDeviceCapabilities"
                    . (:array ,@(spec-required-capabilities spec)))))
             ;; An empty dict is the modern way to say "no launch storyboard,
             ;; use the default". Without any UILaunchScreen key at all, iOS
             ;; letterboxes the app at a legacy screen size.
             ,@(when (spec-launch-screen spec)
                 `(("UILaunchScreen" . (:dict))))
             ,@(when (spec-status-bar-hidden-p spec)
                 `(("UIStatusBarHidden" . :true)))
             ,@(when (spec-category spec)
                 `(("LSApplicationCategoryType" . ,(spec-category spec))))
             ,@(when (spec-copyright spec)
                 `(("NSHumanReadableCopyright" . ,(spec-copyright spec))))
             ,@(when (spec-url-schemes spec)
                 `(("CFBundleURLTypes"
                    . (:array
                       (:dict ("CFBundleURLName" . ,(spec-identifier spec))
                              ("CFBundleURLSchemes"
                               . (:array ,@(spec-url-schemes spec))))))))
             ,@(when (spec-document-types spec)
                 `(("CFBundleDocumentTypes"
                    . (:array ,@(spec-document-types spec))))))))
    (plist-merge base (spec-extra-plist spec))))

(defun write-info-plist (spec)
  (lint-plist (write-plist (info-plist-form spec) (info-plist-path spec))))

(defun write-pkginfo (spec)
  (let ((path (pkginfo-path spec)))
    (ensure-directories-exist path)
    (with-open-file (s path :direction :output :if-exists :supersede)
      (write-string "APPL????" s))
    path))

;;; ------------------------------------------------------------------
;;; staging
;;;
;;; Everything is assembled off to one side and moved into place at the end.
;;; A failed build must not leave a half-written .app that the simulator will
;;; happily try to install.

(defun files-under (directory)
  (let ((files '()))
    (uiop:collect-sub*directories
     (uiop:ensure-directory-pathname directory)
     (constantly t) (constantly t)
     (lambda (d) (setf files (append files (uiop:directory-files d)))))
    files))

(defun sibling-directory (path suffix)
  (let* ((path (uiop:ensure-directory-pathname path))
         (parent (uiop:pathname-parent-directory-pathname path))
         (name (car (last (pathname-directory path)))))
    (uiop:subpathname parent (concatenate 'string name suffix "/"))))

(defun unique-suffix (tag)
  (format nil ".~a-~36r" tag (random (expt 36 8) (make-random-state t))))

(defun mv (from to)
  "Move a directory. rename(2) is atomic, which is the point of the staging
scheme; it only fails across filesystems, and staging, trash and target are
always siblings. /bin/mv is the fallback for that case."
  (let ((from (string-right-trim "/" (uiop:native-namestring from)))
        (to (string-right-trim "/" (uiop:native-namestring to))))
    (run (list "/bin/mv" from to))
    t))

(defun empty-bundle-stub-p (bundle)
  "True for a bare directory that a failed build left at the destination.
Deliberately strict: this predicate authorises deleting a tree, so it demands
the tree hold no files whatsoever."
  (let ((bundle (uiop:ensure-directory-pathname bundle)))
    (and (uiop:directory-exists-p bundle)
         (null (files-under bundle)))))

(defun commit-bundle (staging final)
  "Move STAGING onto FINAL. The previous bundle is set aside first, so a
failure here leaves the old one intact rather than nothing at all."
  (let ((trash (and (probe-file final)
                    (sibling-directory final (unique-suffix "trash")))))
    (when trash (mv final trash))
    (handler-bind ((error (lambda (e)
                            (declare (ignore e))
                            (when trash (ignore-errors (mv trash final))))))
      (mv staging final))
    (when trash (ignore-errors (uiop:delete-directory-tree trash :validate t)))
    final))

;;; ------------------------------------------------------------------
;;; resources

(defparameter +reserved-bundle-names+
  '("Info.plist" "PkgInfo" "embedded.mobileprovision" "Assets.car"
    "_CodeSignature" "lisp")
  "Names a resource may not take.

Longer than the macOS sibling's list, and it has to be: an iOS bundle is flat,
so a resource called Info.plist does not land somewhere harmless inside
Resources/, it lands ON the Info.plist.")

(defun check-resource-destination (spec destination)
  (let ((name (car (last (uiop:split-string destination :separator "/")))))
    (declare (ignorable name))
    (when (search ".." destination)
      (barf "Resource destination ~s escapes the bundle." destination))
    (when (and (plusp (length destination)) (char= #\/ (char destination 0)))
      (barf "Resource destination ~s must be relative." destination))
    (let ((first-component (first (uiop:split-string destination :separator "/"))))
      (when (member first-component +reserved-bundle-names+ :test #'string=)
        (barf "Resource destination ~s collides with ~a, which the bundle ~
               needs. Choose another name."
              destination first-component)))
    (when (string= destination (spec-executable-name spec))
      (barf "Resource destination ~s collides with the executable." destination))
    destination))

(defun install-resources (spec)
  "Copy :BUNDLE-RESOURCES into the bundle root. Each entry is a path, or a
cons of a path and the relative destination it should take."
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (entry (spec-resources spec))
      (let* ((source (if (consp entry) (car entry) entry))
             (destination (if (consp entry)
                              (cdr entry)
                              (file-namestring source))))
        (check-resource-destination spec destination)
        (when (gethash destination seen)
          (barf "Two resources both want to be ~s." destination))
        (setf (gethash destination seen) t)
        (let ((target (bundle-file spec destination)))
          (ensure-directories-exist target)
          (if (uiop:directory-exists-p source)
              (run (list "/bin/cp" "-R"
                         (string-right-trim "/" (uiop:native-namestring source))
                         (uiop:native-namestring target)))
              (uiop:copy-file source target)))))
    (spec-resources spec)))

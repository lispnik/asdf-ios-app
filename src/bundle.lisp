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

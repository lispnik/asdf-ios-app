;;;; icon.lisp -- asset catalogues, and the keys that say what built this.
;;;;
;;;; iOS icons are not files you copy. They are compiled: actool turns an
;;;; .xcassets directory into an Assets.car and, separately, tells you which
;;;; Info.plist keys the result needs -- CFBundleIcons, CFBundlePrimaryIcon,
;;;; the file names it chose. Guessing those keys is how you get an app that
;;;; installs with a white square, so they are read back from actool rather
;;;; than written here.

(in-package #:asdf-ios-app)

(defun directory-basename (directory)
  "The last component of DIRECTORY, parsed as a file name.

A directory pathname keeps its last component in PATHNAME-DIRECTORY, where it
is one undivided string -- so \"AppIcon.appiconset\" has no PATHNAME-TYPE
until it is parsed as a name, which is what this does."
  (pathname (car (last (pathname-directory
                        (uiop:ensure-directory-pathname directory))))))

(defun icon-catalogue (path)
  "PATH as a .xcassets directory, or a refusal.

Only an asset catalogue: a PNG cannot be accepted, because iOS wants a whole
family of sizes and actool is the thing that knows which. Saying so here is
kinder than letting actool report it."
  (let ((directory (uiop:ensure-directory-pathname path)))
    (unless (uiop:directory-exists-p directory)
      (barf "No asset catalogue at ~a." (uiop:native-namestring directory)))
    (unless (string-equal "xcassets" (or (pathname-type (directory-basename directory)) ""))
      (barf ":BUNDLE-ICON must be a .xcassets directory, not ~a. iOS icons are ~
             compiled by actool, which needs the catalogue and not a single ~
             image."
            (uiop:native-namestring directory)))
    directory))

(defun app-icon-set-name (catalogue)
  "The name of the .appiconset inside CATALOGUE, without the extension.

Read rather than assumed: the convention is AppIcon, but --app-icon takes a
name and an app whose set is called something else would compile to an
Assets.car with no icon in it and no error."
  (let ((sets (remove-if-not
               (lambda (d)
                 (string-equal "appiconset"
                               (or (pathname-type (directory-basename d)) "")))
               (uiop:subdirectories catalogue))))
    (cond ((null sets)
           (barf "~a holds no .appiconset." (uiop:native-namestring catalogue)))
          ((rest sets)
           (barf "~a holds ~d .appiconsets; asdf-ios-app compiles one. ~
                  Name the app's icon set and leave the others out."
                 (uiop:native-namestring catalogue) (length sets)))
          (t (pathname-name (directory-basename (car sets)))))))

(defun target-device-arguments (device-family)
  (loop for family in device-family
        collect "--target-device"
        collect (string-downcase (symbol-name family))))

(defun install-icon (spec catalogue)
  "Compile CATALOGUE into the bundle and merge the keys it needs into Info.plist.

The partial plist is actool's own answer to `which keys does this Assets.car
require' -- CFBundleIcons, the primary icon name, the file names it chose --
and merging it is what makes the icon appear rather than a white square.
PlistBuddy does the merge: the alternative is carrying a plist READER to match
the writer, for values nothing here ever looks at.

Must run after WRITE-INFO-PLIST, since it merges into what that wrote."
  (let* ((platform (spec-platform spec))
         (partial (uiop:tmpize-pathname
                   (uiop:subpathname (spec-root spec) "actool-partial.plist"))))
    (unwind-protect
         (progn
           (run (append
                 (list "/usr/bin/xcrun" "actool"
                       "--output-format" "human-readable-text"
                       "--notices" "--warnings"
                       "--app-icon" (app-icon-set-name catalogue)
                       "--platform" (platform-name platform)
                       "--minimum-deployment-target"
                       (spec-minimum-os-version spec))
                 (target-device-arguments (spec-device-family spec))
                 (list "--output-partial-info-plist"
                       (uiop:native-namestring partial)
                       "--compile"
                       (string-right-trim
                        "/" (uiop:native-namestring (spec-root spec)))
                       (string-right-trim
                        "/" (uiop:native-namestring catalogue))))
                ;; actool reports every unassigned image on stderr and still
                ;; succeeds, and those notices are worth seeing.
                :echo-error t)
           (run (list "/usr/libexec/PlistBuddy"
                      "-c" (format nil "Merge ~a" (uiop:native-namestring partial))
                      (uiop:native-namestring (info-plist-path spec))))
           (lint-plist (info-plist-path spec)))
      (ignore-errors (delete-file partial)))))

;;; ------------------------------------------------------------------
;;; build provenance
;;;
;;; The DT* keys say which SDK and which Xcode produced the bundle. App Store
;;; submission requires them; the simulator does not care, and writing them
;;; there would only be noise in a diff. So they go on device builds alone.

(defun sdk-version (platform)
  (string-trim '(#\Space #\Newline)
               (run (list "/usr/bin/xcrun" "--sdk" (platform-name platform)
                          "--show-sdk-version"))))

(defun sdk-build-version (platform)
  (string-trim '(#\Space #\Newline)
               (run (list "/usr/bin/xcrun" "--sdk" (platform-name platform)
                          "--show-sdk-build-version"))))

(defun xcode-versions ()
  "(version . build) from xcodebuild -version, or NIL if it cannot be had.

NIL rather than an error: a machine with only the command line tools has no
xcodebuild, and that machine can still build and sign an app perfectly well.
The keys are for submission, and submission needs full Xcode anyway."
  (let ((output (ignore-errors (run (list "/usr/bin/xcrun" "xcodebuild" "-version")))))
    (when output
      (let ((lines (remove "" (uiop:split-string output :separator '(#\Newline))
                           :test #'string=)))
        (flet ((tail (line) (car (last (uiop:split-string line :separator '(#\Space))))))
          (when (rest lines)
            (cons (tail (first lines)) (tail (second lines)))))))))

(defun compact-xcode-version (version)
  "Xcode 16.2 as DTXcode writes it: \"1620\". Two digits, then minor, then patch."
  (let ((parts (uiop:split-string version :separator '(#\.))))
    (format nil "~2,'0d~d~d"
            (parse-integer (or (first parts) "0") :junk-allowed t)
            (or (parse-integer (or (second parts) "0") :junk-allowed t) 0)
            (or (parse-integer (or (third parts) "0") :junk-allowed t) 0))))

(defun build-provenance-plist-for (platform)
  "The DT* keys for PLATFORM, as an alist, or NIL on the simulator."
  (let ((platform (if (ios-platform-p platform) platform (find-platform platform))))
    (when (eq (platform-key platform) :device)
      (let ((xcode (xcode-versions)))
        (append
         (list (cons "DTPlatformName" (platform-name platform))
               (cons "DTPlatformVersion" (sdk-version platform))
               (cons "DTPlatformBuild" (sdk-build-version platform))
               (cons "DTSDKName" (format nil "~a~a" (platform-name platform)
                                         (sdk-version platform)))
               (cons "DTSDKBuild" (sdk-build-version platform))
               (cons "DTCompiler" "com.apple.compilers.llvm.clang.1_0")
               (cons "BuildMachineOSBuild"
                     (string-trim '(#\Space #\Newline)
                                  (run (list "/usr/bin/sw_vers" "-buildVersion")))))
         (when xcode
           (list (cons "DTXcode" (compact-xcode-version (car xcode)))
                 (cons "DTXcodeBuild" (cdr xcode)))))))))

;;;; toolchain.lisp -- where the iOS ECL is, and what flags it was built with.
;;;;
;;;; A cross prefix describes itself. bin/ecl-config in it is a POSIX shell
;;;; script -- it runs on the host, not on the phone -- and reports the arch,
;;;; SDK and deployment target that prefix was configured with. So the user
;;;; states a path and nothing else, and there is no second copy of the flags
;;;; to drift out of step with the one that built the library.

(in-package #:asdf-ios-app)

;;; ------------------------------------------------------------------
;;; platforms

(defstruct (ios-platform (:conc-name platform-))
  key                ; :device | :simulator
  name               ; "iphoneos" | "iphonesimulator" -- Xcode's names, and
                     ; also the output subdirectory, so nothing is conditional
  min-flag           ; the -m...-version-min flag this platform wants
  plist-platform     ; CFBundleSupportedPlatforms entry
  mach-o-platform    ; what otool -lv must report; asserted after linking
  simulator-p)

(defparameter +platforms+
  (list (make-ios-platform :key :device
                           :name "iphoneos"
                           :min-flag "-miphoneos-version-min"
                           :plist-platform "iPhoneOS"
                           :mach-o-platform "IOS"
                           :simulator-p nil)
        (make-ios-platform :key :simulator
                           :name "iphonesimulator"
                           :min-flag "-mios-simulator-version-min"
                           :plist-platform "iPhoneSimulator"
                           :mach-o-platform "IOSSIMULATOR"
                           :simulator-p t))
  "The two platforms, and every way in which they differ. Anything that
branches on device-versus-simulator should read a slot here rather than test a
keyword, so that adding a platform is adding a row.")

(defun find-platform (key)
  (or (find key +platforms+ :key #'platform-key)
      (barf "Unknown platform ~s. Expected one of ~{~s~^, ~}."
            key (mapcar #'platform-key +platforms+))))

;;; ------------------------------------------------------------------
;;; where things live

(defvar *cache-directory* nil
  "Override for CACHE-DIRECTORY.")

(defun cache-directory ()
  "Where BOOTSTRAP-ECL keeps the ECL checkout and the prefixes it builds.
Not inside the user's project: several hundred megabytes that nothing in a
project should carry, and shared between every project on the machine."
  (or *cache-directory*
      (uiop:subpathname
       (or (let ((xdg (uiop:getenv "XDG_CACHE_HOME")))
             (and xdg (plusp (length xdg)) (uiop:ensure-directory-pathname xdg)))
           (uiop:subpathname (user-homedir-pathname) ".cache/"))
       "asdf-ios-app/")))

(defvar *ios-ecl-prefix* nil
  "The device cross build, as produced by tools/build-ecl-ios.sh.")

(defvar *ios-simulator-ecl-prefix* nil
  "The simulator cross build.")

(defvar *host-ecl* nil
  "The ECL that drives cross-compilation.

It MUST come from the same source tree as the prefixes above. The cross build
reuses this ECL's dpp and ecl_min, and dpp resolves each @[pkg::sym] in the C
sources to a numeric index into src/c/symbols_list.h -- so an ECL from another
revision does not fail, it silently resolves every symbol to a different index.
CHECK-ECL-PREFIX compares the versions for exactly this reason.")

(defun toolchain-file ()
  (uiop:subpathname (cache-directory) "toolchain.sexp"))

(defun read-toolchain ()
  "The recorded toolchain, or NIL. Never signals: an unreadable or outdated
file should send you to BOOTSTRAP-ECL, not stop you loading this system."
  (let ((path (toolchain-file)))
    (when (probe-file path)
      (ignore-errors
       (with-open-file (in path)
         (let ((*read-eval* nil))
           (read in)))))))

(defun write-toolchain (plist)
  (let ((path (toolchain-file)))
    (ensure-directories-exist path)
    (with-open-file (out path :direction :output :if-exists :supersede)
      (write-string ";;;; Written by ASDF-IOS-APP:BOOTSTRAP-ECL. Safe to delete.
;;;; Deleting it does not delete the prefixes; re-running BOOTSTRAP-ECL will
;;;; find them already built and simply record them again.
" out)
      (let ((*print-readably* nil) (*print-pretty* t))
        (prin1 plist out))
      (terpri out))
    path))

(defun toolchain ()
  "Prefixes and host ECL, from the specials if set and from the recorded
toolchain otherwise. Specials beat the environment, which beats the file, so a
user with a hand-built ECL never has to care that the file exists."
  (let ((recorded (read-toolchain)))
    (flet ((directory-from-env (name)
             (let ((value (uiop:getenv name)))
               (and value (plusp (length value))
                    (uiop:ensure-directory-pathname value))))
           (file-from-env (name)
             (let ((value (uiop:getenv name)))
               (and value (plusp (length value)) (pathname value)))))
      (list :device (or *ios-ecl-prefix*
                        (directory-from-env "ECL_IOS_PREFIX")
                        (getf recorded :device))
            :simulator (or *ios-simulator-ecl-prefix*
                           (directory-from-env "ECL_IOS_SIM_PREFIX")
                           (getf recorded :simulator))
            :host (or *host-ecl*
                      (file-from-env "ECL_HOST")
                      (getf recorded :host))))))

(defun platform-prefix (platform)
  (let* ((p (if (ios-platform-p platform) platform (find-platform platform)))
         (prefix (getf (toolchain) (platform-key p))))
    (or prefix
        (barf "No ECL prefix for ~a. Run (asdf-ios-app:bootstrap-ecl), or set ~
               ASDF-IOS-APP:*IOS~:[~;-SIMULATOR~]-ECL-PREFIX*."
              (platform-name p) (platform-simulator-p p)))))

(defun toolchain-available-p (&optional (platform :simulator))
  (let ((prefix (getf (toolchain) (platform-key (find-platform platform)))))
    (and prefix (probe-file (uiop:subpathname prefix "bin/ecl-config")) t)))

;;; ------------------------------------------------------------------
;;; reading a prefix

(defun ecl-config (prefix &rest args)
  "Ask a prefix's ecl-config what it was built with.

It is a shell script, so it runs on the build host even when the prefix it
describes is full of arm64 objects that cannot."
  (let ((script (uiop:subpathname prefix "bin/ecl-config")))
    (unless (probe-file script)
      (barf "~a is not an ECL prefix: no bin/ecl-config."
            (uiop:native-namestring prefix)))
    (run (list* "/bin/sh" (uiop:native-namestring script) args))))

(defun tokens (string)
  (remove "" (uiop:split-string string :separator '(#\Space #\Tab #\Newline))
          :test #'string=))

(defun flag-argument (flag tokens)
  "The token after FLAG, as in -arch arm64."
  (let ((tail (member flag tokens :test #'string=)))
    (second tail)))

(defun flag-starting-with (prefix tokens)
  (find-if (lambda (token)
             (and (>= (length token) (length prefix))
                  (string= prefix token :end2 (length prefix))))
           tokens))

(defun prefix-build-flags (prefix)
  "Arch, SDK and deployment-target flag, read back out of the prefix.

They come from --libs rather than --cflags because the cross build put them in
LDFLAGS; --cflags carries only -Ddarwin and the include path."
  (let ((tokens (tokens (ecl-config prefix "--libs"))))
    (list :arch (or (flag-argument "-arch" tokens) "arm64")
          :sdk (flag-argument "-isysroot" tokens)
          :min-flag (or (flag-starting-with "-miphoneos-version-min=" tokens)
                        (flag-starting-with "-mios-simulator-version-min=" tokens)))))

(defun prefix-include (prefix)
  (uiop:subpathname prefix "include/"))

(defun prefix-lib (prefix)
  (uiop:subpathname prefix "lib/"))

(defun prefix-ecl-version (prefix)
  "The ECL version a prefix was built from, taken from lib/ecl-<version>/.

By globbing rather than by running anything: the ecl in a cross prefix is an
arm64 binary and will not run here."
  (let* ((libs (uiop:subdirectories (prefix-lib prefix)))
         (dir (find-if (lambda (d)
                         (let ((name (car (last (pathname-directory d)))))
                           (and (> (length name) 4)
                                (string= "ecl-" name :end2 4))))
                       libs)))
    (when dir
      (subseq (car (last (pathname-directory dir))) 4))))

(defun prefix-module-directory (prefix)
  (let ((version (prefix-ecl-version prefix)))
    (unless version
      (barf "~a has no lib/ecl-<version>/ directory; it is not a finished ~
             ECL prefix." (uiop:native-namestring prefix)))
    (uiop:subpathname (prefix-lib prefix) (format nil "ecl-~a/" version))))

(defun host-ecl-version (ecl)
  (let ((out (run (list (uiop:native-namestring ecl) "--version"))))
    ;; "ECL 26.5.5"
    (car (last (tokens out)))))

(defun prefix-has-dlopen-p (prefix)
  "Whether the prefix was built with ENABLE_DLOPEN.

Without it SI:FIND-FOREIGN-SYMBOL refuses to resolve anything and CFFI, whose
ECL backend looks foreign functions up by name, cannot work at all. This
detects only half the problem: the companion fix -- ecl_library_symbol asking
for RTLD_DEFAULT rather than a null handle, which on Darwin is not the global
scope -- is a runtime behaviour and cannot be seen from here."
  (let ((config (uiop:subpathname (prefix-include prefix) "ecl/config-internal.h"))
        (public (uiop:subpathname (prefix-include prefix) "ecl/config.h")))
    (and (some (lambda (file)
                 (and (probe-file file)
                      (search "ENABLE_DLOPEN" (uiop:read-file-string file))))
               (list config public))
         t)))

(defun check-ecl-prefix (platform)
  "Signal unless PLATFORM's prefix is usable, and unless the host ECL agrees
with it about the version.

The version check is not belt and braces. A host ECL from another revision does
not fail: dpp resolves every @[pkg::sym] to an index into that revision's
symbols_list.h, so the cross build silently gets the wrong symbol everywhere."
  (let* ((p (find-platform platform))
         (prefix (platform-prefix p))
         (host (getf (toolchain) :host)))
    (unless (probe-file (uiop:subpathname prefix "lib/libecl.a"))
      (barf "~a has no lib/libecl.a. Run (asdf-ios-app:bootstrap-ecl)."
            (uiop:native-namestring prefix)))
    (unless (and host (probe-file host))
      (barf "No host ECL recorded. Run (asdf-ios-app:bootstrap-ecl), or set ~
             ASDF-IOS-APP:*HOST-ECL* to an ECL built from the same tree as ~a."
            (uiop:native-namestring prefix)))
    (let ((prefix-version (prefix-ecl-version prefix))
          (host-version (host-ecl-version host)))
      (unless (equal prefix-version host-version)
        (barf "Host ECL is ~a but ~a was built from ~a.~%~
               They must come from one tree: the cross build reuses the host's ~
               dpp, which resolves symbols to indices into that revision's ~
               symbols_list.h. A mismatch corrupts every symbol silently.~%~
               Run (asdf-ios-app:bootstrap-ecl) to build a matched set."
              host-version (uiop:native-namestring prefix) prefix-version)))
    (unless (prefix-has-dlopen-p prefix)
      (note "~a was built without ENABLE_DLOPEN. SI:FIND-FOREIGN-SYMBOL will ~
             fail and CFFI will not work. Rebuild with (bootstrap-ecl)."
            (uiop:native-namestring prefix)))
    prefix))

(defun describe-toolchain (&optional (stream *standard-output*))
  "Print what is configured, for when a build complains and you want to know why."
  (let ((tc (toolchain)))
    (format stream "~&host ECL:  ~a~%" (or (getf tc :host) "(not set)"))
    (dolist (p +platforms+)
      (let ((prefix (getf tc (platform-key p))))
        (format stream "~a:~vT~a~%" (platform-name p) 18
                (or (and prefix (uiop:native-namestring prefix)) "(not set)"))
        (when (and prefix (probe-file (uiop:subpathname prefix "bin/ecl-config")))
          (let ((flags (prefix-build-flags prefix)))
            (format stream "~vT~a, min ~a, ECL ~a~@[, no ENABLE_DLOPEN~]~%"
                    18
                    (getf flags :arch)
                    (or (getf flags :min-flag) "?")
                    (or (prefix-ecl-version prefix) "?")
                    (not (prefix-has-dlopen-p prefix)))))))
    (values)))

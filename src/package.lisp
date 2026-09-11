;;;; package.lisp

(defpackage #:asdf-ios-app
  (:use #:cl)
  (:nicknames #:ios-app)
  (:export
   ;; build driver
   #:make-app
   #:run-in-simulator
   #:install-on-device
   #:export-ipa
   ;; toolchain
   #:bootstrap-ecl
   #:toolchain
   #:toolchain-available-p
   #:describe-toolchain
   ;; conditions
   #:app-build-error
   ;; knobs
   #:*ios-ecl-prefix*
   #:*ios-simulator-ecl-prefix*
   #:*host-ecl*
   #:*cache-directory*
   #:*ecl-repository*
   #:*ecl-revision*
   #:*force-compile*))

(in-package #:asdf-ios-app)

(define-condition app-build-error (simple-error) ())

(defun barf (fmt &rest args)
  (error 'app-build-error :format-control fmt :format-arguments args))

(defparameter +host-toolchain-environment+
  '("CPATH" "C_INCLUDE_PATH" "CPLUS_INCLUDE_PATH"
    "OBJC_INCLUDE_PATH" "OBJCPLUS_INCLUDE_PATH"
    "LIBRARY_PATH" "LD_LIBRARY_PATH" "DYLD_LIBRARY_PATH" "DYLD_FRAMEWORK_PATH"
    "SDKROOT")
  "Variables that aim a compiler at the *host's* headers and libraries.

Each one is an implicit -I or -L that no command line mentions, which in a
cross build is precisely the wrong machine. A Homebrew shell profile setting
LIBRARY_PATH to a host GCC's library directory is enough to put

    ld: warning: search path '/opt/homebrew/Cellar/gcc/.../16' not found

in the middle of an iOS link. Benign in that instance only because the path did
not exist: on a machine where it does, the linker would search a directory of
arm64 *macOS* objects while building for a phone. SDKROOT is here for the same
reason and is the worst of them -- it is a whole sysroot, and clang takes it
without comment.")

(defun without-host-toolchain (argv)
  "ARGV, run with +HOST-TOOLCHAIN-ENVIRONMENT+ removed from its environment.

/usr/bin/env rather than UIOP's :ENVIRONMENT, which on ECL is accepted and then
ignored -- the subprocess inherits the lot, and nothing says so. Only variables
that are actually set are named, so the usual command line is unchanged."
  (let ((set (remove-if-not #'uiop:getenvp +host-toolchain-environment+)))
    (if (null set)
        argv
        (append (list "/usr/bin/env")
                (loop for name in set append (list "-u" name))
                argv))))

(defun run (argv &key (ignore-error-status nil) input directory echo-error)
  "Run ARGV, returning its stdout as a string. Errors are fatal by default.

ECHO-ERROR passes stderr through even on success. clang and codesign put real
warnings there and say nothing on stdout, so a build that discards stderr
whenever the exit code is zero is a build that silently swallows every warning
in the project."
  (multiple-value-bind (out err code)
      (uiop:run-program (without-host-toolchain argv)
                        :output '(:string :stripped t)
                        :error-output '(:string :stripped t)
                        :input input
                        :directory directory
                        :ignore-error-status t)
    (when (and (not ignore-error-status) (/= code 0))
      (barf "~a exited ~d:~%~a" (first argv) code err))
    (when (and echo-error (plusp (length err)))
      (format *standard-output* "~&~a~%" err)
      (finish-output *standard-output*))
    (values out err code)))

(defun write-file-if-changed (path content)
  "Write CONTENT to PATH only if it differs from what is there.

Rewriting an unchanged generated file is not free: its write date is what
decides whether everything that includes it has to be recompiled, so a header
rewritten on every build means the Objective-C is rebuilt on every build."
  (let ((existing (and (probe-file path)
                       (ignore-errors (uiop:read-file-string path)))))
    (unless (equal existing content)
      (ensure-directories-exist path)
      (with-open-file (out path :direction :output :if-exists :supersede
                                :external-format :utf-8)
        (write-string content out))))
  path)

(defun note (format-control &rest args)
  "Say something on the build log. Deliberately not WARN: a build driver may
muffle warnings, and these are things the person running the build must see."
  (format *standard-output* "~&; ~?~%" format-control args)
  (finish-output *standard-output*))

(defvar *simulate-non-darwin* nil
  "Bind to T to make DARWIN-P answer NIL on a Mac. For the suite, and only for
it, so that the refusals can be tested on the machine this library is for.")

(defun darwin-p ()
  (and (not *simulate-non-darwin*) (uiop:os-macosx-p)))

(defparameter +required-tools+
  '("/usr/bin/xcrun"                                ; SDK paths, actool, simctl
    "/usr/bin/clang"                                ; the whole build is clang
    "/usr/bin/nm" "/usr/bin/ar" "/usr/bin/ranlib"   ; init symbols, archives
    "/usr/bin/otool"                                ; asserting the Mach-O platform
    "/usr/bin/codesign" "/usr/bin/security"         ; signing, profiles
    "/usr/bin/plutil"                               ; validation, reading profiles
    "/usr/libexec/PlistBuddy"                       ; merging actool's partial plist
    "/usr/bin/ditto" "/usr/bin/sw_vers"             ; .ipa export, provenance keys
    "/usr/bin/git" "/usr/bin/make"                  ; BOOTSTRAP-ECL
    "/usr/bin/env")                                 ; WITHOUT-HOST-TOOLCHAIN
  "Every command line tool the build shells out to, checked up front so a
missing one is reported before any work happens rather than from somewhere deep
inside RUN. A test asserts this list covers every /usr/bin/ literal in the
sources, because the two drift apart otherwise.

Unlike the macOS sibling there is no exception for xcrun: on iOS it is part of
every build, not just of a release step.")

(defun missing-build-tools (&optional (tools +required-tools+))
  (remove-if #'probe-file tools))

(defun require-darwin (what)
  (unless (darwin-p)
    (barf "~a requires macOS." what))
  ;; Being on macOS is not the same as having the tools: a clean install has
  ;; none of these until the Xcode command line tools are present.
  (let ((missing (missing-build-tools)))
    (when missing
      (barf "~a needs ~{~a~^, ~}, which ~:[is~;are~] not installed. ~
             Run: xcode-select --install"
            what missing (rest missing)))))

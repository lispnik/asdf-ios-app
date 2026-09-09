;;;; compile.lisp -- turn Lisp into an arm64 static library.
;;;;
;;;; ECL's compiler emits C and then shells out to a C compiler, so pointing
;;;; that compiler at an iOS SDK cross-compiles Lisp for the phone. Everything
;;;; here runs in the HOST ECL -- the one built from the same tree as the
;;;; prefix -- and produces objects that only a phone can run.

(in-package #:asdf-ios-app)

(defun platform-cc-flags (platform)
  "The flags ECL should hand to clang when compiling for PLATFORM, read back
out of that platform's own prefix."
  (let* ((p (if (ios-platform-p platform) platform (find-platform platform)))
         (prefix (platform-prefix p))
         (flags (prefix-build-flags prefix)))
    (format nil "-arch ~a ~a -isysroot ~a -fPIC -fno-common -Ddarwin"
            (getf flags :arch)
            (or (getf flags :min-flag)
                (format nil "~a=15.0" (platform-min-flag p)))
            (or (getf flags :sdk)
                (barf "~a's ecl-config reports no -isysroot."
                      (uiop:native-namestring prefix))))))

(defun module-names-in (directory)
  "The ECL module names a prefix's module directory offers, as a set of strings.

A module shows up under several names -- sockets.asd, sockets.fasc,
libsockets.a -- so the extension and any lib prefix are stripped and the result
uniquified. Only the names matter here, never the files themselves: a target
module directory holds arm64 objects this Lisp must not load."
  (when directory
    (let ((names '()))
      (dolist (file (directory (merge-pathnames "*.*"
                                                (uiop:ensure-directory-pathname directory)))
               names)
        (let ((name (pathname-name file))
              (type (pathname-type file)))
          (when (and name
                     (member type '("fas" "fasc" "asd" "a") :test #'equal))
            (when (and (equal type "a") (uiop:string-prefix-p "lib" name))
              (setf name (subseq name 3)))
            (pushnew name names :test #'string-equal)))))))

(defun host-only-module-features (target-directory)
  "Features named after a module the host has and TARGET-DIRECTORY does not.

These are lies during cross compilation. A system that adapts to its host --
slynk's ECL backend is the example -- probes for a module at load time and
pushes a feature when it finds one:

    (when (probe-file \"sys:serve-event.fas\")
      (require :serve-event)
      (pushnew :serve-event *features*))

The child loads that system natively before cross-compiling it, so the probe
answers for the Mac. The prefixes do not carry the same module set --
--disable-shared drops serve-event -- so the #+serve-event code then compiled
into the app references a package no linked module provides, and the app dies
at boot. Repointing SYS: stops the probe succeeding a second time; it cannot
retract what the native load already pushed. This can."
  (let* ((directory (and target-directory
                         (probe-file (uiop:ensure-directory-pathname target-directory))
                         target-directory))
         (host (module-names-in (ignore-errors (translate-logical-pathname #p"SYS:"))))
         (target (module-names-in directory)))
    ;; DIRECTORY rather than TARGET: an unreadable prefix must drop nothing,
    ;; but a readable one with no modules in it legitimately drops everything.
    (when (and host directory)
      (remove-if-not (lambda (feature)
                       (let ((name (symbol-name feature)))
                         (and (member name host :test #'string-equal)
                              (not (member name target :test #'string-equal)))))
                     (remove-if-not #'symbolp *features*)))))

(defmacro with-target-sys-translations ((platform) &body body)
  "Run BODY with SYS: and *FEATURES* answering for PLATFORM rather than the Mac.

SYS: is repointed at the target's module directory. SETF of
LOGICAL-PATHNAME-TRANSLATIONS is global state rather than a binding, so the old
translations are saved and put back by UNWIND-PROTECT.

*FEATURES* loses the features named after modules only the host has; see
HOST-ONLY-MODULE-FEATURES for why that is not as arbitrary as it looks."
  (let ((p (gensym "PLATFORM"))
        (saved (gensym "SAVED"))
        (dir (gensym "DIR"))
        (dropped (gensym "DROPPED")))
    `(let* ((,p ,platform)
            (,dir (prefix-module-directory (platform-prefix ,p)))
            (,dropped (host-only-module-features ,dir))
            (*features* (set-difference *features* ,dropped))
            (,saved (logical-pathname-translations "SYS")))
       (when ,dropped
         (note "cross-compiling without host-only feature~p: ~{~s~^ ~}"
               (length ,dropped) ,dropped))
       (unwind-protect
            (progn
              (when ,dir
                (setf (logical-pathname-translations "SYS")
                      (list (list "**;*.*"
                                  (merge-pathnames "**/*.*"
                                                   (uiop:ensure-directory-pathname ,dir))))))
              ,@body)
         (setf (logical-pathname-translations "SYS") ,saved)))))

(defmacro with-ios-toolchain ((platform) &body body)
  "Point ECL's C backend at an iOS SDK for the duration.

C::*ECL-INCLUDE-DIRECTORY* rather than a -I in the flags: COMPILER-CC puts its
own -I ahead of anything in *CC-FLAGS*, so a -I there loses to the HOST's
ecl/config.h and the objects are built against the wrong configuration.

FFI::*USE-DFFI* must be NIL at compile time or FFI:DEFCALLBACK emits a libffi
closure instead of a C function -- and a libffi closure is the one thing iOS
will not run.

C::*USE-PRECOMPILED-HEADERS* off because that cache is keyed with EQ on the
flag strings, which goes wrong the moment one image builds two platforms.

SYS: is repointed at the target's module directory, because a cross compiler
that answers host questions compiles the wrong code. Systems probe SYS: at
compile time to decide what to emit -- slynk's ECL backend asks
(probe-file \"sys:serve-event.fas\") and, told yes by the host, compiles in
references to a package the phone has no module for, so the app dies at boot
with `Package SERVE-EVENT ... referenced in compiled file but has not been
created'. The prefixes do not carry the same module set: --disable-shared
drops serve-event entirely. Pointing SYS: at the target makes those probes
answer for the machine the code is going to run on.

Safe because REQUIRE consults *MODULES* first, so the child's already-loaded
modules are not re-sought, and because the header path the compiler needs
comes from C::*ECL-INCLUDE-DIRECTORY* above rather than from SYS:."
  (let ((p (gensym "PLATFORM")))
    `(let* ((,p ,platform)
            (c::*cc* "clang")
            (c::*cc-flags* (platform-cc-flags ,p))
            (c::*cc-optimize* "-O2")
            (c::*ecl-include-directory*
              (uiop:native-namestring (prefix-include (platform-prefix ,p))))
            (c::*use-precompiled-headers* nil)
            (ffi::*use-dffi* nil))
       (with-target-sys-translations (,p) ,@body))))

(defun require-compiler ()
  (unless (find-package "C")
    (funcall (find-symbol "REQUIRE" "CL") :cmp))
  (unless (find-package "C")
    (barf "This ECL has no compiler: (require :cmp) did not give a C package.")))

;;; ------------------------------------------------------------------
;;; names

(defun c-identifier (string)
  "STRING as a C identifier, following ECL's own convention for module names:
upper case, and anything that is not a letter or digit becomes an underscore."
  (map 'string
       (lambda (c)
         (if (or (alpha-char-p c) (digit-char-p c)) (char-upcase c) #\_))
       string))

(defun library-init-name (name)
  "The init entry point of the library built for system NAME.

Deterministic on purpose. C::BUILDER randomises the real init symbol -- it
mixes GET-UNIVERSAL-TIME into it -- and emits a stable WRAPPER carrying the
:INIT-NAME we ask for. The wrapper is what the generated header declares."
  (format nil "init_lib_~a" (c-identifier name)))

;;; ------------------------------------------------------------------
;;; compiling

(defun object-path (source cache)
  "Where SOURCE's object goes.

The name carries a hash of the source's full path, because basenames are not
unique across a dependency closure and a collision here is silent and awful.
Alexandria is the example that found it: it ships alexandria-1 and
alexandria-2, each with its own package.lisp, arrays.lisp, lists.lisp and more.
Keyed on the basename alone, the second package.o overwrote the first, the
archive never defined ALEXANDRIA.1.0.0, and the app died at boot complaining
about a package rather than about a build."
  ;; NAMESTRING rather than TRUENAME: ASDF hands us absolute pathnames already,
  ;; and requiring the file to exist would make this a partial function that
  ;; cannot be tested without touching the disk.
  (make-pathname :name (format nil "~a-~(~8,'0x~)"
                               (pathname-name source)
                               (logand (sxhash (namestring source))
                                       #xffffffff))
                 :type "o"
                 :defaults cache))

(defvar *force-compile* nil
  "Bind to T to recompile every file even when its object looks current.")

(defun object-is-current-p (source object)
  "Whether OBJECT can be reused.

Only the source's own write date is consulted. A change to a macro in another
file will not invalidate this one, which is the same bargain every make-style
build strikes; :FORCE-COMPILE and deleting the cache are the ways out. Getting
this wrong in the other direction -- recompiling a whole dependency closure on
every build -- costs a minute per build forever."
  (and (not *force-compile*)
       (probe-file object)
       (probe-file source)
       (>= (file-write-date object) (file-write-date source))))

(defun cross-compile-file (source cache)
  "Compile one source file to an iOS object.

:SYSTEM-P T is the whole trick: it stops at the object file and never builds
or loads a fasl, which is what makes this safe to do in a host image."
  (let ((output (object-path source cache)))
    (when (object-is-current-p source output)
      (return-from cross-compile-file output))
    (ensure-directories-exist output)
    (multiple-value-bind (result warnings failure)
        (compile-file source :system-p t :output-file output)
      (declare (ignore warnings))
      (when (or failure (null result))
        (barf "Cross-compiling ~a failed." (uiop:native-namestring source)))
      result)))

(defun nm-defined-symbols (path)
  "The globally defined symbols of an object or archive.

Mach-O prefixes C identifiers with an underscore; exactly one is stripped."
  (let ((out (run (list "/usr/bin/nm" "-g" (uiop:native-namestring path))
                  :ignore-error-status t)))
    (loop for line in (uiop:split-string out :separator '(#\Newline))
          for fields = (tokens line)
          when (and (= (length fields) 3) (string= "T" (second fields)))
            collect (let ((name (third fields)))
                      (if (and (plusp (length name)) (char= #\_ (char name 0)))
                          (subseq name 1)
                          name)))))

(defun verify-init-symbol (library init-name)
  "Check that C::BUILDER really emitted the wrapper we asked for.

Cheap, and it is the guard against ECL changing how init names are computed --
see cmpc-init-name.lsp. A missing symbol here becomes an unresolved external at
link time, which is a much worse place to find out."
  (unless (member init-name (nm-defined-symbols library) :test #'string=)
    (barf "~a does not define ~a.~%ECL may have changed how C::BUILDER names ~
           module init functions; see cmpc-init-name.lsp."
          (uiop:native-namestring library) init-name))
  init-name)

(defun cross-compile-lisp (sources &key platform name cache)
  "Compile SOURCES for PLATFORM and archive them. Returns the library and its
init symbol."
  (require-compiler)
  (check-ecl-prefix (if (ios-platform-p platform) (platform-key platform) platform))
  (let* ((p (if (ios-platform-p platform) platform (find-platform platform)))
         (cache (uiop:ensure-directory-pathname
                 (uiop:subpathname cache (format nil "~a/" (platform-name p)))))
         (library (uiop:subpathname cache (format nil "lib~a.a" name)))
         (init (library-init-name name)))
    (ensure-directories-exist cache)
    (with-ios-toolchain (p)
      (let ((objects (mapcar (lambda (source) (cross-compile-file source cache))
                             sources)))
        (funcall (find-symbol "BUILDER" "C")
                 :static-library library
                 :lisp-files objects
                 :init-name init)))
    (unless (probe-file library)
      (barf "C::BUILDER produced no ~a." (uiop:native-namestring library)))
    (verify-init-symbol library init)
    (values library init)))

;;;; op.lisp -- the ASDF extension proper.
;;;;
;;;; Classes are interned in the ASDF package so that a .asd file can say
;;;;   :class :ios-app-system
;;;;   :build-operation "ios-app-op"
;;;; without needing our package to exist at read time.

(in-package #:asdf-ios-app)

;;; ------------------------------------------------------------------
;;; system class

(defclass asdf::ios-app-system (asdf:system)
  (;; identity
   (identifier    :initarg :bundle-identifier :initform nil :reader app-identifier)
   (bundle-name   :initarg :bundle-name :initform nil :reader app-bundle-name)
   (display-name  :initarg :bundle-display-name :initform nil :reader app-display-name)
   (exe-name      :initarg :bundle-executable :initform nil :reader app-exe-name)
   (short-version :initarg :bundle-short-version :initform nil :reader app-short-version)
   (copyright     :initarg :bundle-copyright :initform nil :reader app-copyright)
   (category      :initarg :bundle-category :initform nil :reader app-category)

   ;; iOS Info.plist
   (min-os        :initarg :bundle-minimum-os-version :initform nil :reader app-min-os)
   (device-family :initarg :bundle-device-family :initform nil :reader app-device-family)
   (orientations  :initarg :bundle-orientations :initform nil :reader app-orientations)
   (ipad-orient   :initarg :bundle-ipad-orientations :initform nil :reader app-ipad-orientations)
   (launch-screen :initarg :bundle-launch-screen :initform t :reader app-launch-screen)
   (capabilities  :initarg :bundle-required-capabilities :initform nil :reader app-capabilities)
   (status-bar    :initarg :bundle-status-bar-hidden :initform nil :reader app-status-bar-hidden-p)
   (url-schemes   :initarg :bundle-url-schemes :initform nil :reader app-url-schemes)
   (doc-types     :initarg :bundle-document-types :initform nil :reader app-doc-types)
   (extra-plist   :initarg :bundle-info-plist :initform nil :reader app-extra-plist)
   (resources     :initarg :bundle-resources :initform nil :reader app-resources)

   ;; what gets built, and how
   (platforms     :initarg :bundle-platforms :initform '(:simulator) :reader app-platforms)
   (interpreted   :initarg :bundle-interpreted :initform nil :reader app-interpreted)
   (modules       :initarg :bundle-ecl-modules :initform nil :reader app-ecl-modules)
   (frameworks    :initarg :bundle-frameworks :initform nil :reader app-frameworks)
   (static-libs   :initarg :bundle-static-libraries :initform nil :reader app-static-libraries)
   (objc-sources  :initarg :bundle-objc-sources :initform nil :reader app-objc-sources)
   (objc-main     :initarg :bundle-objc-main :initform nil :reader app-objc-main)
   (delegate      :initarg :bundle-app-delegate :initform nil :reader app-delegate-class)
   (trampolines   :initarg :bundle-trampolines :initform nil :reader app-trampolines)
   (remote-repl   :initarg :remote-repl :initform nil :reader app-remote-repl)
   (objc-flags    :initarg :bundle-objc-flags :initform nil :reader app-objc-flags)
   (link-flags    :initarg :bundle-link-flags :initform nil :reader app-link-flags)
   (output-dir    :initarg :bundle-output-directory :initform nil :reader app-output-directory)

   ;; signing
   (identity      :initarg :code-signing-identity :initform :automatic :reader app-identity)
   (team-id       :initarg :development-team :initform nil :reader app-team-id)
   (profile       :initarg :provisioning-profile :initform nil :reader app-provisioning-profile)
   (entitlements  :initarg :entitlements :initform :ios-default :reader app-entitlements)
   (task-allow    :initarg :get-task-allow :initform t :reader app-get-task-allow-p)))

;;; ------------------------------------------------------------------
;;; operations

(defclass asdf::ios-app-op (asdf::non-propagating-operation) ()
  (:documentation "Build a .app bundle for every requested platform.

Non-propagating: a dependency system is something to compile INTO this app, not
something to build an app out of."))

(defclass asdf::ios-app-cross-compile-op (asdf::selfward-operation)
  ((asdf::selfward-operation :initform 'asdf:load-op :allocation :class))
  (:documentation "Cross-compile the system to iOS objects and archive them.
This is what the child ECL performs.

Selfward to LOAD-OP because a cross compiler needs every macro, package and
reader macro the sources define, and loading them natively first is how it gets
them. That does mean each file is compiled twice in the child -- once for the
host, once for iOS -- which is the one place a system with a DEFCONSTANT of a
non-EQL value will complain. :BUNDLE-INTERPRETED is the escape."))

;;; ------------------------------------------------------------------
;;; system -> spec

(defun default-bundle-name (system)
  (or (app-bundle-name system)
      (let ((build (asdf::component-build-pathname system)))
        (and build (pathname-name build)))
      (string-capitalize (asdf:component-name system))))

(defun app-output-root (system)
  (uiop:ensure-directory-pathname
   (or (app-output-directory system)
       (uiop:subpathname (asdf:system-source-directory system) "build/"))))

(defun bundle-root-for (system platform)
  "Always <output>/<platform-name>/<Name>.app -- never a conditional name, so
that two platforms cannot land on each other and a path tells you which is
which."
  (uiop:subpathname (app-output-root system)
                    (format nil "~a/~a.app/"
                            (platform-name platform)
                            (default-bundle-name system))))

(defun system-app-spec (system platform)
  (let ((source (asdf:system-source-directory system)))
    (flet ((resource (entry)
             (if (consp entry)
                 (cons (merge-pathnames (car entry) source) (cdr entry))
                 (merge-pathnames entry source))))
      (make-app-spec
       :root (bundle-root-for system platform)
       :final-root (bundle-root-for system platform)
       :platform platform
       :name (default-bundle-name system)
       :display-name (app-display-name system)
       :identifier (app-identifier system)
       :version (or (asdf:component-version system) "0.0.0")
       :short-version (app-short-version system)
       :executable-name (or (app-exe-name system)
                            (string-downcase (asdf:component-name system)))
       :minimum-os-version (or (app-min-os system) "15.0")
       :device-family (or (app-device-family system) '(:iphone :ipad))
       :orientations (or (app-orientations system) '(:portrait))
       :ipad-orientations (app-ipad-orientations system)
       :launch-screen (app-launch-screen system)
       :required-capabilities (or (app-capabilities system) '("arm64"))
       :status-bar-hidden-p (app-status-bar-hidden-p system)
       :category (app-category system)
       :copyright (app-copyright system)
       :url-schemes (app-url-schemes system)
       :document-types (app-doc-types system)
       :extra-plist (app-extra-plist system)
       :resources (mapcar #'resource (app-resources system))
       :ecl-modules (needed-ecl-modules system)
       :frameworks (or (app-frameworks system)
                       '("UIKit" "Foundation" "CoreGraphics"))
       :static-libraries (mapcar (lambda (p) (merge-pathnames p source))
                                 (app-static-libraries system))
       :link-flags (app-link-flags system)
       :signing-identity (app-identity system)
       :team-id (app-team-id system)
       :provisioning-profile (and (app-provisioning-profile system)
                                  (merge-pathnames
                                   (app-provisioning-profile system) source))
       :entitlements (app-entitlements system)
       :get-task-allow-p (app-get-task-allow-p system)))))

;;; ------------------------------------------------------------------
;;; ASDF glue

(defmethod asdf:output-files ((o asdf::ios-app-op) (s asdf::ios-app-system))
  ;; Real files rather than the bundle directories, so ASDF's timestamp
  ;; bookkeeping has something it can stat. T because the bundle must land
  ;; where the user asked, not under output-translations.
  (values (mapcar (lambda (key)
                    (uiop:subpathname (bundle-root-for s (find-platform key))
                                      "Info.plist"))
                  (app-platforms s))
          t))

(defmethod asdf:operation-done-p ((o asdf::ios-app-op) (s asdf::ios-app-system))
  nil)

;;; ------------------------------------------------------------------
;;; which sources get compiled

(defun interpreted-system-names (system)
  (let ((interpreted (app-interpreted system)))
    (cond ((null interpreted) '())
          ((eq interpreted t) (list (asdf:component-name system)))
          (t (mapcar #'string-downcase
                     (mapcar #'string interpreted))))))

(defun component-system-name (component)
  (string-downcase (asdf:component-name (asdf:component-system component))))

(defparameter +never-cross-compiled+
  '("asdf" "uiop" "asdf-ios-app")
  "Systems that must not be cross-compiled.

UIOP and ASDF because the prefix already has libasdf.a, built for the target,
and recompiling them for arm64 is slower and no better. Ourselves because we
are the build tool, not part of the app.

Skipping them is only half the job: whatever needed them still needs them at
run time. See NEEDED-ECL-MODULES.")

(defun closure-needs-asdf-p (system)
  "Whether anything in the closure depends on UIOP or ASDF.

Asked of the SYSTEM graph rather than the component list, because UIOP and
ASDF contribute no components here -- they are excluded from cross-compilation,
so nothing of theirs turns up in SOURCE-FILES-IN-ORDER.

CFFI does, which makes this the common case rather than an exotic one. Left
unlinked, the app dies at boot with

  The packages ((UIOP/OS . ...) (UIOP/PATHNAME . ...)) were referenced in
  compiled file NIL

which names the packages but not the cause."
  (some (lambda (dependency)
          (member (string-downcase (asdf:component-name dependency))
                  '("asdf" "uiop") :test #'string=))
        (dependency-closure (asdf:component-name system))))

(defparameter +remote-repl-modules+ '("sockets" "sb-bsd-sockets" "cmp")
  "The ECL modules a slynk server needs linked into the app.

sockets and sb-bsd-sockets because slynk's ECL backend does
(require 'sockets) and talks to SB-BSD-SOCKETS directly; cmp because that
backend references the C package -- C:COMPILER-FATAL-ERROR among others -- and
because a REPL where COMPILE does not work is a poor sort of REPL.")

(defun remote-repl-options (system)
  "SYSTEM's :REMOTE-REPL as a plist for IOS-APP-RUNTIME:START-REMOTE-REPL, or NIL.

Accepts T, a port number, or a plist -- (:port 4005 :interface \"127.0.0.1\"
:style :spawn) -- because a port is what almost everyone means and spelling out
a plist to say 4005 would be a tax."
  (let ((value (app-remote-repl system)))
    (etypecase value
      (null nil)
      ((eql t) (list :port 4005))
      (integer (list :port value))
      (cons
       (let ((port (getf value :port 4005)))
         (unless (integerp port)
           (barf ":REMOTE-REPL was given ~s as a :PORT; it must be an integer."
                 port))
         (list :port port
               :interface (getf value :interface)
               :style (getf value :style :spawn)))))))

(defun check-remote-repl (system)
  "Refuse a :REMOTE-REPL build whose closure has no slynk in it.

Caught here rather than at boot because the failure is otherwise an app that
launches, says nothing, and does not listen -- and the fix is one line in the
.asd. ASDF-IOS-APP deliberately does not depend on slynk itself: which REPL
server you want, and where its sources live, is yours to say."
  (when (and (remote-repl-options system)
             (notany (lambda (dependency)
                       (string-equal "slynk" (asdf:component-name dependency)))
                     (dependency-closure (asdf:component-name system))))
    (barf ":REMOTE-REPL needs slynk in the system's closure. Add \"slynk\" to ~
           :DEPENDS-ON, and put sly's slynk/ directory on the source registry ~
           -- it is not on Quicklisp under that name.")))

(defun needed-ecl-modules (system)
  "The ECL modules to link: what the system asked for, plus what its closure
implies. ASDF and the remote REPL are the implied ones so far."
  (let ((asked (app-ecl-modules system))
        (implied '()))
    (when (closure-needs-asdf-p system)
      (push "asdf" implied))
    (when (remote-repl-options system)
      (setf implied (append (reverse +remote-repl-modules+) implied)))
    (dolist (module (reverse implied) asked)
      (unless (member module asked :test #'string-equal)
        (setf asked (append asked (list module)))))))

(defun source-files-in-order (system)
  "The CL source files LOAD-OP would touch, in ASDF's own dependency order.

The TYPEP filter is not redundant: :COMPONENT-TYPE does not exclude the system
component itself, whose pathname is a directory, and handing that to
COMPILE-FILE fails in a way that names the directory and explains nothing."
  (remove-if-not
   (lambda (component) (typep component 'asdf:cl-source-file))
   (asdf:required-components system
                             :other-systems t
                             :goal-operation 'asdf:load-op
                             :keep-operation 'asdf:compile-op
                             :component-type 'asdf:cl-source-file)))

(defun warn-about-interpreted-dependencies (system)
  "Say something when compiled code depends on an interpreted system.

Compiled code is initialised when the library's module init runs, which is
before any bundled source is LOADed. So a compiled file that references an
interpreted package AT LOAD TIME -- an IN-PACKAGE, a macro from it, a
top-level call -- fails, because that package does not exist yet.

A reference deferred to run time is fine, and is the intended shape: the whole
point of :BUNDLE-INTERPRETED is a compiled core calling out to an editable
skin. examples/hello does exactly that, through READ-FROM-STRING and FUNCALL.

Which of the two a file does is not decidable from here, so this is a note and
not an error. Refusing outright would forbid the ordinary case -- an
application that depends on its own scripts system -- to prevent a mistake the
person can see in their own source."
  (let ((interpreted (interpreted-system-names system))
        (dependents '()))
    (when interpreted
      (let ((seen '()))
        (dolist (component (source-files-in-order system))
          (let ((name (component-system-name component)))
            (cond ((member name interpreted :test #'string=) (pushnew name seen
                                                                     :test #'string=))
                  (seen (pushnew name dependents :test #'string=))))))
      (when dependents
        (note "~{~a~^, ~} ~:[is~;are~] compiled but ~:*~:[comes~;come~] after ~
               the interpreted ~{~a~^, ~}. That is fine as long as nothing in ~
               them touches an interpreted package at LOAD time -- bundled ~
               source is loaded after every compiled module has initialised."
              (reverse dependents) (rest dependents) interpreted))))
  t)

(defun cross-compiled-source-files (system)
  "Every source file to compile into the app, in ASDF's own dependency order.

ASDF is used for the ORDER and nothing else: REQUIRED-COMPONENTS answers what
LOAD-OP would touch, and we then compile those files ourselves. Going through
ASDF's own compile-op instead would, on ECL, build and try to LOAD a .fas --
an iOS bundle, in the host image."
  (let ((interpreted (interpreted-system-names system)))
    (remove-if
     (lambda (component)
       (let ((name (component-system-name component)))
         (or (member name +never-cross-compiled+ :test #'string=)
             (member name interpreted :test #'string=))))
     (source-files-in-order system))))

(defun trampoline-files (system)
  "Lisp files cross-compiled for the target and NEVER compiled on the host.

This is where FFI:C-INLINE belongs, and the exemption is the whole point.
Ordinary sources are compiled twice -- natively in the child, so the cross
compiler has their macros, and then for iOS -- and C-INLINE does not survive
the native pass. It cannot be interpreted at all, and compiling it natively
means ECL builds and LINKS a host fasl, so anything referring to CoreGraphics
or objc_msgSend fails at link time against the macOS toolchain.

A trampoline needs no macros from anywhere, so skipping the native pass costs
nothing. And with the C compiler doing the work, struct returns and variadic
calls -- the two things ECL's dynamic FFI cannot express at all -- come free."
  (mapcar (lambda (file)
            (merge-pathnames file (asdf:system-source-directory system)))
          (app-trampolines system)))

(defun interpreted-source-files (system)
  (let ((interpreted (interpreted-system-names system)))
    (when interpreted
      (remove-if-not
       (lambda (component)
         (member (component-system-name component) interpreted :test #'string=))
       (source-files-in-order system)))))

;;; ------------------------------------------------------------------
;;; the child
;;;
;;; Cross-compilation runs in a child ECL, and not because anything here
;;; terminates the process -- nothing does. The cross compiler must BE the host
;;; ECL built from the same tree as the prefix, and that is a different binary
;;; from whatever Lisp is running ASDF. The child also keeps the user's whole
;;; system, C::*CC-FLAGS* pointed at an iOS SDK and FFI::*USE-DFFI* NIL out of
;;; the build driver's image.

(defparameter +child-phases+
  '((:configuring    . "configuring the source registry")
    (:reading-system . "reading the .asd (a dependency system may be unfindable)")
    (:loading-system . "compiling and loading the system natively, which the
                        cross compiler needs for macros -- a failure here is an
                        ordinary compile error, not an iOS one")
    (:cross-compiling . "cross-compiling for iOS"))
  "What each phase means, for the parent's error message.")

(defun cl-user-symbol (name)
  "Symbols in the bootstrap must be readable by the child before any of our
packages exist there, so they live in CL-USER."
  (intern name (find-package :cl-user)))

(defun dependency-names (dependency)
  "The system names in one :DEPENDS-ON entry.

ASDF allows more shapes than a string. (:VERSION \"x\" \"1.0\") and
(:REQUIRE \"x\") name a system in second position, but (:FEATURE :DARWIN \"x\")
names it in THIRD -- and taking the second there yields :DARWIN, which finds no
system and silently drops the real dependency. CFFI depends on UIOP exactly
that way, which is how this was found."
  (cond ((null dependency) '())        ; NIL is a symbol; test it first
        ((stringp dependency) (list dependency))
        ((symbolp dependency) (list (string-downcase (symbol-name dependency))))
        ((consp dependency)
         (case (first dependency)
           (:feature (dependency-names (third dependency)))
           ((:version :require) (dependency-names (second dependency)))
           (t (dependency-names (second dependency)))))
        (t '())))

(defun dependency-closure (system-name)
  (let ((systems '()))
    (labels ((walk (name)
               (let ((system (ignore-errors (asdf:find-system name nil))))
                 (when (and system (not (member system systems)))
                   (push system systems)
                   (dolist (dep (asdf:system-depends-on system))
                     (mapc #'walk (dependency-names dep)))))))
      (walk system-name))
    systems))

(defun child-source-registry-form (system)
  "An explicit source registry for the child, one (:directory ...) per system
in the resolved dependency closure.

Inheriting configuration is not enough: the parent may have found systems
through ASDF:*CENTRAL-REGISTRY* or a search function -- ocicl, say -- that the
child's own configuration cannot see. It travels inside the bootstrap file
rather than the environment, which has a length limit a large closure can
outgrow."
  (let* ((closure (cons (asdf:find-system "asdf-ios-app")
                        (dependency-closure (asdf:component-name system))))
         (dirs (remove-duplicates
                (remove nil (mapcar #'asdf:system-source-directory closure))
                :test #'equal :from-end t)))
    `(:source-registry
      ,@(mapcar (lambda (d) (list :directory (uiop:native-namestring d))) dirs)
      :inherit-configuration)))

(defun child-bootstrap-forms (system status-file request-file registry)
  "The forms the child loads.

Built as data and printed, rather than interpolated into a template: a template
is read as one opaque string, so an arity or quoting mistake in it is caught,
if at all, by the compiler in the child. Self-contained plain CL, because it
must be able to report a failure in LOAD-ASD itself, which happens before this
extension is loaded there."
  ;; EVERY symbol introduced here must be a CL-USER symbol. Any symbol read in
  ;; our own package prints as ASDF-IOS-APP::FOO, and the child cannot read
  ;; that: our package does not exist there yet, and the whole point of the
  ;; bootstrap is to run before it does. A test asserts the printed file
  ;; mentions no package of ours.
  (let ((e (cl-user-symbol "E"))
        (s (cl-user-symbol "S"))
        (hook (cl-user-symbol "HOOK"))
        (enter (cl-user-symbol "ENTER-PHASE"))
        (report (cl-user-symbol "REPORT-FAILURE"))
        (asd (asdf:system-source-file system))
        (name (asdf:component-name system)))
    `((require :asdf)
      (defun ,enter (,s)
        (with-open-file (,e ,(uiop:native-namestring status-file)
                            :direction :output :if-exists :supersede)
          (prin1 (list :phase ,s) ,e)))
      (defun ,report (,e)
        (with-open-file (,s ,(uiop:native-namestring status-file)
                            :direction :output :if-exists :supersede)
          (prin1 (list :error (princ-to-string ,e)) ,s)))
      ;; ECL has no --disable-debugger, so an unhandled error would sit at a
      ;; broken REPL forever rather than failing the build.
      (setf ext:*invoke-debugger-hook*
            (lambda (,e ,hook)
              (declare (ignore ,hook))
              (,report ,e)
              (ext:quit 1)))
      (handler-bind ((error (lambda (,e) (,report ,e) (ext:quit 1))))
        (,enter :configuring)
        (asdf:initialize-source-registry ',registry)
        ;; Our extension BEFORE the .asd: the .asd says :class
        ;; :ios-app-system, and ASDF cannot recognise that class until the
        ;; system defining it is loaded. A user's .asd also says
        ;; :defsystem-depends-on ("asdf-ios-app"), which does the same thing,
        ;; but the child should not depend on the user having written it.
        (,enter :reading-system)
        (asdf:load-system "asdf-ios-app")
        (asdf:load-asd ,(uiop:native-namestring asd))
        (,enter :loading-system)
        (asdf:load-system ,name)
        (,enter :cross-compiling)
        (funcall (find-symbol "CROSS-COMPILE-IN-CHILD" "ASDF-IOS-APP")
                 ,name ,(uiop:native-namestring request-file))
        (with-open-file (,s ,(uiop:native-namestring status-file)
                            :direction :output :if-exists :supersede)
          (prin1 (list :done t) ,s))
        (ext:quit 0)))))

(defun read-child-status (status-file)
  (when (probe-file status-file)
    (ignore-errors
     (with-open-file (in status-file)
       (let ((*read-eval* nil)) (read in))))))

(defun child-failure (status-file)
  (let ((status (read-child-status status-file)))
    (cond ((null status)
           "the child did not start; check that the host ECL runs")
          ((getf status :error)
           (getf status :error))
          ((getf status :phase)
           (let* ((phase (getf status :phase))
                  (what (cdr (assoc phase +child-phases+))))
             (format nil "died while ~a" (or what phase))))
          (t (format nil "~s" status)))))

;;; ------------------------------------------------------------------
;;; cross-compilation, in the child

(defun cross-compile-in-child (system-name request-file)
  "Called in the child, by name, from the bootstrap. Writes a reply beside the
request naming the library and init symbol built for each platform."
  (let* ((system (asdf:find-system system-name))
         (request (with-open-file (in request-file)
                    (let ((*read-eval* nil)) (read in))))
         (cache (uiop:ensure-directory-pathname (getf request :cache)))
         (*ios-ecl-prefix* (getf request :device-prefix))
         (*ios-simulator-ecl-prefix* (getf request :simulator-prefix))
         ;; The child IS the host ECL, but CHECK-ECL-PREFIX compares versions
         ;; and needs to know which binary that is.
         (*host-ecl* (getf request :host))
         (results '()))
    (dolist (key (getf request :platforms))
      (let* ((platform (find-platform key))
             ;; Trampolines last: they may call into the application, and nothing
         ;; in the application can call them at load time.
         (sources (append (list (system-file "src/runtime.lisp"))
                          (mapcar #'asdf:component-pathname
                                  (cross-compiled-source-files system))
                          (trampoline-files system))))
        (multiple-value-bind (library init)
            (cross-compile-lisp sources
                                :platform platform
                                :name (asdf:component-name system)
                                :cache cache)
          (push (list key :library (uiop:native-namestring library) :init init)
                results))))
    (with-open-file (out (make-pathname :type "reply" :defaults request-file)
                         :direction :output :if-exists :supersede)
      (prin1 (list :products (nreverse results)) out))
    t))

(defun run-cross-compile (system platforms cache)
  "Spawn the host ECL to cross-compile SYSTEM. Returns the products plist."
  (let* ((host (or (getf (toolchain) :host)
                   (barf "No host ECL. Run (asdf-ios-app:bootstrap-ecl).")))
         (work (uiop:ensure-directory-pathname cache))
         (boot (uiop:subpathname work "child-bootstrap.lisp"))
         (status (uiop:subpathname work "child-status.sexp"))
         (request (uiop:subpathname work "child-request.sexp"))
         (reply (make-pathname :type "reply" :defaults request)))
    (ensure-directories-exist work)
    (dolist (stale (list status reply)) (ignore-errors (delete-file stale)))
    ;; The child is a fresh image: it inherits none of our specials, and
    ;; re-deriving the toolchain there would consult a config file that may not
    ;; be the one we are using. The parent has already resolved and validated
    ;; the prefixes, so it simply says which.
    (let ((tc (toolchain)))
      (with-open-file (out request :direction :output :if-exists :supersede)
        (prin1 (list :cache (uiop:native-namestring work)
                     :platforms platforms
                     :device-prefix (getf tc :device)
                     :simulator-prefix (getf tc :simulator)
                     :host (getf tc :host))
               out)))
    (with-open-file (out boot :direction :output :if-exists :supersede)
      (let ((*package* (find-package :cl-user)))
        (dolist (form (child-bootstrap-forms system status request
                                             (child-source-registry-form system)))
          (prin1 form out)
          (terpri out))))
    (note "cross-compiling ~a for ~{~a~^, ~}"
          (asdf:component-name system)
          (mapcar (lambda (k) (platform-name (find-platform k))) platforms))
    (multiple-value-bind (out err code)
        (uiop:run-program (list (uiop:native-namestring host)
                                "-norc" "--load" (uiop:native-namestring boot))
                          :output t :error-output t :ignore-error-status t)
      (declare (ignore out err))
      (unless (and (zerop code) (probe-file reply))
        (barf "Cross-compilation failed: ~a" (child-failure status))))
    (with-open-file (in reply) (let ((*read-eval* nil)) (read in)))))

;;; ------------------------------------------------------------------
;;; assembling a bundle

(defun install-lisp-sources (spec system)
  "Copy :BUNDLE-INTERPRETED sources into lisp/, with a manifest naming them in
dependency order. They are shipped as source precisely so they can be edited
without a rebuild."
  (let ((files (interpreted-source-files system)))
    (when files
      (let ((directory (lisp-directory spec))
            (names '()))
        (ensure-directories-exist directory)
        (dolist (component files)
          (let* ((source (asdf:component-pathname component))
                 (name (file-namestring source)))
            (uiop:copy-file source (uiop:subpathname directory name))
            (push (format nil "lisp/~a" name) names)))
        (with-open-file (out (uiop:subpathname directory "boot-order.sexp")
                             :direction :output :if-exists :supersede)
          (prin1 (nreverse names) out))
        (length files)))))

(defun install-provisioning-profile (spec)
  (let ((profile (spec-provisioning-profile spec)))
    (when profile
      (unless (probe-file profile)
        (barf "No provisioning profile at ~a."
              (uiop:native-namestring profile)))
      (uiop:copy-file profile (provisioning-profile-path spec))
      (provisioning-profile-path spec))))

(defun boot-form-for (system spec)
  (declare (ignorable spec))
  (let ((entry (asdf::component-entry-point system)))
    (unless entry
      (barf "System ~a needs an :ENTRY-POINT. It is called once, on the main ~
             thread, and must RETURN -- the run loop starts after it."
            (asdf:component-name system)))
    (format nil "(ios-app-runtime::%boot :entry-point ~s~@[ :manifest ~s~]~@[ :remote-repl '~s~])"
            entry
            (and (app-interpreted system) "lisp/boot-order.sexp")
            (remote-repl-options system))))

(defun assemble-bundle (system platform products cache)
  (let* ((spec (system-app-spec system platform))
         (final (spec-final-root spec))
         (staging (sibling-directory final (unique-suffix "staging")))
         (product (cdr (assoc (platform-key platform) products)))
         (library (getf product :library))
         (init (getf product :init))
         (objc-cache (uiop:subpathname (uiop:ensure-directory-pathname cache)
                                       (format nil "~a/" (platform-name platform))))
         (committed nil))
    (setf (spec-root spec) staging)
    (unwind-protect
         (progn
           (make-skeleton spec :clean t)
           (write-info-plist spec)
           (write-pkginfo spec)
           (install-resources spec)
           (install-lisp-sources spec system)
           (install-provisioning-profile spec)
           ;; Before anything expensive: a mismatched profile is a build-time
           ;; fact and should not be discovered by an app that will not launch.
           (unless (platform-simulator-p platform)
             (check-provisioning-profile spec))
           (write-build-header objc-cache
                               :name (spec-name spec)
                               :delegate (app-delegate-class system)
                               :boot-form (boot-form-for system spec)
                               ;; ECL's own modules FIRST, the application's
                               ;; library last. Its objects reference packages
                               ;; those modules define -- CFFI wants UIOP -- and
                               ;; a module initialised afterwards is too late:
                               ;; the app dies at boot reporting packages
                               ;; "referenced in compiled file NIL", which names
                               ;; the packages and not the ordering.
                               :modules (append (ecl-module-inits spec)
                                                (list (cons (c-identifier
                                                             (asdf:component-name system))
                                                            init))))
           (let ((objects (compile-objc-sources
                           platform objc-cache
                           :user-sources (mapcar
                                          (lambda (p)
                                            (merge-pathnames
                                             p (asdf:system-source-directory system)))
                                          (app-objc-sources system))
                           :own-main (app-objc-main system)
                           :extra-flags (app-objc-flags system))))
             (link-executable spec (pathname library) objects))
           (verify-mach-o-platform spec)
           (sign-bundle spec)
           (commit-bundle staging final)
           (setf committed t)
           (note "built ~a" (uiop:native-namestring final))
           final)
      (when (probe-file staging)
        (ignore-errors (uiop:delete-directory-tree staging :validate t)))
      ;; ASDF made the destination directory before PERFORM ran. If nothing was
      ;; committed, that stub is all there is and it must not survive.
      (unless committed
        (when (empty-bundle-stub-p final)
          (ignore-errors
           (uiop:delete-directory-tree (uiop:ensure-directory-pathname final)
                                       :validate t)))))))

(defun ecl-module-inits (spec)
  "(module-name . init-symbol) for each :BUNDLE-ECL-MODULES entry.

ECL gives every linked module a stable init_lib_<NAME> entry point, which is
why these do not need looking up."
  (mapcar (lambda (name)
            (cons (string-upcase name)
                  (format nil "init_lib_~a" (c-identifier name))))
          (spec-ecl-modules spec)))

;;; ------------------------------------------------------------------
;;; perform

(defmethod asdf:perform ((o asdf::ios-app-op) (s asdf::ios-app-system))
  (require-darwin "Building an iOS .app bundle")
  (let* ((platforms (mapcar #'find-platform (app-platforms s)))
         (cache (uiop:subpathname (app-output-root s) "cache/")))
    (dolist (platform platforms)
      (check-ecl-prefix (platform-key platform)))
    (check-remote-repl s)
    (warn-about-interpreted-dependencies s)
    ;; One child for every platform: loading the system natively is the
    ;; expensive half and there is no reason to do it twice.
    (let ((products (getf (run-cross-compile s (mapcar #'platform-key platforms)
                                             cache)
                          :products)))
      (mapcar (lambda (platform) (assemble-bundle s platform products cache))
              platforms))))

(defun call-in-asdf-session (thunk)
  "Run THUNK inside whatever this ASDF calls a session.

3.3 renamed CALL-WITH-ASDF-CACHE to CALL-WITH-ASDF-SESSION, and ECL still
bundles 3.1.8.11, so both have to be tolerated. Something is needed: without a
fresh session a second MAKE-APP in one image finds the action already visited
and quietly does nothing. :FORCE is not the alternative -- ASDF rejects it in a
nested OPERATE, which would make MAKE-APP uncallable from inside any :perform."
  (let ((session (or (find-symbol "CALL-WITH-ASDF-SESSION" "ASDF")
                     (find-symbol "CALL-WITH-ASDF-CACHE" "ASDF"))))
    (cond ((null session) (funcall thunk))
          ;; :OVERRIDE is what forces a fresh session rather than joining the
          ;; enclosing one. Older ASDFs may not take it; falling back is better
          ;; than refusing to build.
          (t (handler-case (funcall session thunk :override t)
               (program-error () (funcall session thunk)))))))

(defun make-app (system &key platforms)
  "Build SYSTEM's .app bundles. Returns their pathnames."
  (let ((system (asdf:find-system system)))
    (call-in-asdf-session
     (lambda () (asdf:operate 'asdf::ios-app-op system)))
    (mapcar (lambda (key) (bundle-root-for system (find-platform key)))
            (or platforms (app-platforms system)))))

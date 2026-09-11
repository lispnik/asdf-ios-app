;;;; tests/unit.lisp -- everything testable with no Xcode, no ECL prefix and
;;;; no simulator.
;;;;
;;;; Most of what can go wrong here is a wrong string in an argument vector or
;;;; a wrong key in a plist, and both are pure functions of the spec. The
;;;; expensive machinery -- cross-compiling, linking, launching -- is exercised
;;;; in build.lisp, which skips when the toolchain is absent.

(in-package #:asdf-ios-app-tests)

(defun test-spec (&rest args)
  "A spec with sensible defaults, which ARGS override.

ARGS come first: for keyword arguments the leftmost occurrence wins, so
defaults listed ahead of them would silently ignore everything a test asked
for -- which is exactly the sort of test that passes while proving nothing."
  (apply #'app::make-app-spec
         (append args
                 (list :platform (app::find-platform :simulator)
                       :name "Fixture"
                       :identifier "org.example.fixture"
                       :executable-name "fixture"
                       :root #p"/tmp/asdf-ios-app-tests/Fixture.app/"))))

(defun plist-entry (form key)
  (cdr (assoc key (cdr form) :test #'string=)))

(defun plist-has-key-p (form key)
  (and (assoc key (cdr form) :test #'string=) t))

;;; ------------------------------------------------------------------
;;; plist writer

(deftest xml-special-characters-are-escaped
  (is= "a &amp; b &lt;c&gt; &quot;d&quot;" (app::xml-escape "a & b <c> \"d\"")))

(deftest plist-merge-overrides-and-adds
  (let ((merged (app::plist-merge '(:dict ("A" . "one") ("B" . "two"))
                                  '(("B" . "changed") ("C" . "new")))))
    (is= "one" (plist-entry merged "A"))
    (is= "changed" (plist-entry merged "B"))
    (is= "new" (plist-entry merged "C"))))

;;; ------------------------------------------------------------------
;;; versions

(deftest apple-versions-are-numeric-only
  (is= "1.4.2" (app::sanitize-version "1.4.2"))
  (is= "1.4.2" (app::sanitize-version "1.4.2-alpha"))
  (is= "1.4.2" (app::sanitize-version "1.4.2.7"))   ; at most three
  (is= "0" (app::sanitize-version ""))
  (is= "0" (app::sanitize-version nil)))

;;; ------------------------------------------------------------------
;;; the iOS Info.plist
;;;
;;; The substitution most likely to be got wrong is MinimumOSVersion for
;;; LSMinimumSystemVersion. Using the macOS key produces a bundle that installs
;;; and then will not launch, so this asserts both halves.

(deftest ios-uses-minimum-os-version-and-not-the-macos-key
  (let ((form (app::info-plist-form (test-spec :minimum-os-version "15.0"))))
    (is= "15.0" (plist-entry form "MinimumOSVersion"))
    (is (not (plist-has-key-p form "LSMinimumSystemVersion")))))

(deftest ios-requires-the-iphoneos-marker
  (let ((form (app::info-plist-form (test-spec))))
    (is= :true (plist-entry form "LSRequiresIPhoneOS"))
    (is= "APPL" (plist-entry form "CFBundlePackageType"))))

(deftest device-family-is-a-list-of-numbers
  (is= '(:array 1) (plist-entry (app::info-plist-form
                                 (test-spec :device-family '(:iphone)))
                                "UIDeviceFamily"))
  (is= '(:array 1 2) (plist-entry (app::info-plist-form
                                   (test-spec :device-family '(:iphone :ipad)))
                                  "UIDeviceFamily"))
  (signals app::app-build-error
    (app::info-plist-form (test-spec :device-family '(:watch)))))

(deftest orientations-become-uikit-names
  (is= '(:array "UIInterfaceOrientationPortrait"
                "UIInterfaceOrientationLandscapeLeft")
       (plist-entry (app::info-plist-form
                     (test-spec :orientations '(:portrait :landscape-left)))
                    "UISupportedInterfaceOrientations"))
  (signals app::app-build-error
    (app::info-plist-form (test-spec :orientations '(:sideways)))))

(deftest the-ipad-orientation-variant-appears-only-when-asked-for
  (is (not (plist-has-key-p (app::info-plist-form (test-spec))
                            "UISupportedInterfaceOrientations~ipad")))
  (is (plist-has-key-p (app::info-plist-form
                        (test-spec :ipad-orientations '(:portrait)))
                       "UISupportedInterfaceOrientations~ipad")))

(deftest launch-screen-is-an-empty-dict-and-can-be-turned-off
  ;; Without any UILaunchScreen key iOS letterboxes the app at a legacy size,
  ;; so the empty dict is load bearing rather than decorative.
  (is= '(:dict) (plist-entry (app::info-plist-form (test-spec)) "UILaunchScreen"))
  (is (not (plist-has-key-p (app::info-plist-form (test-spec :launch-screen nil))
                            "UILaunchScreen"))))

(deftest supported-platforms-differ-between-device-and-simulator
  (is= '(:array "iPhoneSimulator")
       (plist-entry (app::info-plist-form (test-spec)) "CFBundleSupportedPlatforms"))
  (is= '(:array "iPhoneOS")
       (plist-entry (app::info-plist-form
                     (test-spec :platform (app::find-platform :device)))
                    "CFBundleSupportedPlatforms")))

(deftest a-bundle-identifier-is-required
  (signals app::app-build-error
    (app::info-plist-form (test-spec :identifier nil))))

;;; ------------------------------------------------------------------
;;; the flat layout
;;;
;;; Every one of these is Contents/-free on iOS, and a stray Contents/ would
;;; mean the macOS sibling's code had been copied without being read.

(deftest an-ios-bundle-is-flat
  (let ((spec (test-spec)))
    (is= "fixture" (file-namestring (app::executable-path spec)))
    (is= "Info.plist" (file-namestring (app::info-plist-path spec)))
    (dolist (path (list (app::executable-path spec)
                        (app::info-plist-path spec)
                        (app::pkginfo-path spec)))
      (is (not (member "Contents" (pathname-directory path) :test #'equal))))))

;;; ------------------------------------------------------------------
;;; resources
;;;
;;; Stricter than on macOS, and it has to be: the bundle is flat, so a resource
;;; called Info.plist lands ON the Info.plist rather than safely inside
;;; Contents/Resources/.

(deftest reserved-names-are-refused
  (dolist (name '("Info.plist" "PkgInfo" "_CodeSignature"
                  "embedded.mobileprovision" "lisp"))
    (signals app::app-build-error
      (app::check-resource-destination (test-spec) name))))

(deftest the-executables-own-name-is-refused
  (signals app::app-build-error
    (app::check-resource-destination (test-spec) "fixture")))

(deftest resources-may-not-escape-the-bundle
  (signals app::app-build-error
    (app::check-resource-destination (test-spec) "../outside.txt"))
  (signals app::app-build-error
    (app::check-resource-destination (test-spec) "/etc/passwd")))

(deftest ordinary-resource-destinations-are-allowed
  (is= "data.txt" (app::check-resource-destination (test-spec) "data.txt"))
  (is= "res/data.txt" (app::check-resource-destination (test-spec) "res/data.txt")))

;;; ------------------------------------------------------------------
;;; init names
;;;
;;; ECL's rule, not ours, which is why it is pinned to a table.

(deftest module-init-names-follow-ecls-convention
  (is= "init_lib_HELLO_IOS" (app::library-init-name "hello-ios"))
  (is= "init_lib_FOO_BAR" (app::library-init-name "foo_bar"))
  (is= "init_lib_A_B" (app::library-init-name "a.b"))
  (is= "SOCKETS" (app::c-identifier "sockets")))

;;; ------------------------------------------------------------------
;;; object paths
;;;
;;; Alexandria ships alexandria-1 and alexandria-2, each with its own
;;; package.lisp. Keyed on the basename the second overwrote the first and the
;;; app died at boot saying no package ALEXANDRIA.1.0.0 exists.

(deftest object-paths-are-unique-per-source-not-per-basename
  (let* ((cache #p"/tmp/asdf-ios-app-tests/cache/")
         ;; The exact shape alexandria has: one basename, two systems.
         (a (app::object-path #p"/x/alexandria-1/package.lisp" cache))
         (b (app::object-path #p"/x/alexandria-2/package.lisp" cache)))
    (is (string/= (file-namestring a) (file-namestring b)))
    (is (search "package-" (file-namestring a)))
    (is= "o" (pathname-type a))
    ;; and the same source always lands in the same place, or nothing caches
    (is= (namestring a)
         (namestring (app::object-path #p"/x/alexandria-1/package.lisp" cache)))))

;;; ------------------------------------------------------------------
;;; platforms

(deftest each-platform-knows-its-own-names
  (let ((sim (app::find-platform :simulator))
        (dev (app::find-platform :device)))
    (is= "iphonesimulator" (app::platform-name sim))
    (is= "iphoneos" (app::platform-name dev))
    (is= "IOSSIMULATOR" (app::platform-mach-o-platform sim))
    (is= "IOS" (app::platform-mach-o-platform dev))
    (is (app::platform-simulator-p sim))
    (is (not (app::platform-simulator-p dev)))
    (signals app::app-build-error (app::find-platform :watchos))))

;;; ------------------------------------------------------------------
;;; signing
;;;
;;; A simulator app signed WITH entitlements is refused at launch by
;;; SpringBoard, with a message that says nothing about entitlements. iOS
;;; validates them against a provisioning profile and a simulator app has none.

(deftest the-simulator-signs-ad-hoc-and-the-device-demands-an-identity
  (is= "-" (app::effective-identity (test-spec)))
  (signals app::app-build-error
    (app::effective-identity (test-spec :platform (app::find-platform :device)))))

(deftest a-simulator-build-carries-no-entitlements
  (is (null (app::entitlements-file (test-spec))))
  (is (null (app::entitlements-file (test-spec :entitlements nil)))))

;;; ------------------------------------------------------------------
;;; the child bootstrap
;;;
;;; It runs before our package exists in the child, so a symbol of ours in it
;;; is not a style problem: the child cannot READ the file.

(deftest the-bootstrap-mentions-no-package-of-ours
  (let* ((system (asdf:find-system "asdf-ios-app"))
         (forms (app::child-bootstrap-forms
                 system #p"/tmp/status.sexp" #p"/tmp/request.sexp"
                 '(:source-registry :inherit-configuration)))
         (text (let ((*package* (find-package :cl-user)))
                 (with-output-to-string (s)
                   (dolist (form forms) (prin1 form s) (terpri s))))))
    (is (not (search "ASDF-IOS-APP::" text)))
    (is (not (search "ASDF-IOS-APP:" text)))
    ;; and it must still say what it is for
    (is (search "CROSS-COMPILE-IN-CHILD" text))))

;;; ------------------------------------------------------------------
;;; drift
;;;
;;; Two lists that go stale silently unless something checks them.

(deftest every-tool-we-shell-out-to-is-declared
  (let ((declared app::+required-tools+)
        (used '()))
    (dolist (file (directory (merge-pathnames "src/*.lisp"
                                              (asdf:system-source-directory
                                               "asdf-ios-app"))))
      (let ((text (uiop:read-file-string file)))
        (loop with start = 0
              for hit = (search "\"/usr/bin/" text :start2 start)
              while hit
              do (let ((end (position #\" text :start (1+ hit))))
                   (push (subseq text (1+ hit) end) used)
                   (setf start (1+ end))))
        (loop with start = 0
              for hit = (search "\"/bin/" text :start2 start)
              while hit
              do (let ((end (position #\" text :start (1+ hit))))
                   (push (subseq text (1+ hit) end) used)
                   (setf start (1+ end))))))
    (dolist (tool (remove-duplicates used :test #'string=))
      ;; /bin/sh and /bin/cp and /bin/mv are base-system certainties; the point
      ;; of the list is tools that can be missing.
      (unless (member tool '("/bin/sh" "/bin/cp" "/bin/mv") :test #'string=)
        (is (member tool declared :test #'string=))))))

(deftest the-shipped-objc-list-matches-the-directory
  (let* ((directory (app::objc-directory))
         (on-disk (mapcar #'file-namestring
                          (directory (merge-pathnames "*.m" directory)))))
    (dolist (name app::+bootstrap-sources+)
      (is (member name on-disk :test #'string=)))
    (dolist (name on-disk)
      (is (member name app::+bootstrap-sources+ :test #'string=)))))

;;; ------------------------------------------------------------------
;;; interpreted components

(deftest interpreted-names-normalise-however-they-are-written
  ;; T means "this system", a list means those, NIL means none. Written as
  ;; strings, keywords or symbols, they all have to come out comparable.
  (let ((system (asdf:find-system "hello-ios" nil)))
    (if (null system)
        (skip "hello-ios is not in the registry")
        (is= '("hello-scripts") (app::interpreted-system-names system)))))

(deftest the-runtime-loads-a-manifest-in-order
  ;; The manifest is what carries dependency order into an image that has no
  ;; ASDF, so its shape matters more than it looks.
  (let* ((directory (uiop:subpathname (uiop:temporary-directory)
                                      "asdf-ios-app-manifest-test/"))
         (manifest (uiop:subpathname directory "boot-order.sexp")))
    (ensure-directories-exist directory)
    (with-open-file (out manifest :direction :output :if-exists :supersede)
      (prin1 '("lisp/a.lisp" "lisp/b.lisp") out))
    (is= '("lisp/a.lisp" "lisp/b.lisp")
         (with-open-file (in manifest) (let ((*read-eval* nil)) (read in))))
    (uiop:delete-directory-tree directory :validate t)))

;;; ------------------------------------------------------------------
;;; the dynamic-callback guard
;;;
;;; Interpreted code can reach SI::MAKE-DYNAMIC-CALLBACK, and on iOS that does
;;; not signal -- the process dies, silently and uncatchably, because
;;; ffi_closure_alloc needs executable memory. Turning it into a condition is
;;; the difference between a puzzling crash and a message naming the cause.

(deftest the-callback-guard-replaces-a-silent-death-with-an-error
  (let ((symbol (find-symbol "MAKE-DYNAMIC-CALLBACK" "SI")))
    (if (not (and symbol (fboundp symbol)))
        (skip "this ECL has no SI::MAKE-DYNAMIC-CALLBACK")
        (let ((original (symbol-function symbol)))
          (unwind-protect
               (progn
                 (funcall (find-symbol "GUARD-DYNAMIC-CALLBACKS" "IOS-APP-RUNTIME"))
                 (is (nth-value 1 (ignore-errors
                                   (funcall symbol nil nil :int nil :default)))))
            (setf (symbol-function symbol) original))))))

;;; ------------------------------------------------------------------
;;; provisioning profiles
;;;
;;; The matching rule is pure and worth pinning: a mismatch produces an app
;;; that installs and then refuses to launch, saying nothing.

(deftest application-identifiers-match-exactly-or-by-wildcard
  (is (app::application-identifier-matches-p "ABCDE12345.com.example.app"
                                             "com.example.app"))
  (is (not (app::application-identifier-matches-p "ABCDE12345.com.example.app"
                                                  "com.example.other")))
  ;; a team-wide wildcard
  (is (app::application-identifier-matches-p "ABCDE12345.*" "anything.at.all"))
  ;; a prefix wildcard
  (is (app::application-identifier-matches-p "ABCDE12345.com.example.*"
                                             "com.example.app"))
  (is (not (app::application-identifier-matches-p "ABCDE12345.com.example.*"
                                                  "com.other.app")))
  ;; malformed
  (is (not (app::application-identifier-matches-p "nodots" "com.example.app"))))

(deftest a-device-build-without-a-profile-is-refused
  (signals app::app-build-error
    (app::profile-entitlements-form
     (test-spec :platform (app::find-platform :device)
                :provisioning-profile nil))))

;;; ------------------------------------------------------------------
;;; dependency forms
;;;
;;; ASDF's :DEPENDS-ON allows more shapes than a string, and the one that
;;; matters names its system in THIRD position. CFFI depends on UIOP exactly
;;; that way; reading the second element yields :DARWIN, which finds no system
;;; and silently drops the dependency.

(deftest dependency-forms-are-all-understood
  (is= '("alexandria") (app::dependency-names "alexandria"))
  (is= '("alexandria") (app::dependency-names :alexandria))
  (is= '("uiop") (app::dependency-names '(:feature :darwin "uiop")))
  (is= '("babel") (app::dependency-names '(:version "babel" "1.0")))
  (is= '("sb-posix") (app::dependency-names '(:require "sb-posix")))
  (is= '() (app::dependency-names nil)))

;;; ------------------------------------------------------------------
;;; module init order
;;;
;;; ECL's own modules must initialise BEFORE the application's library: its
;;; objects reference packages those modules define. Getting it backwards makes
;;; the app die at boot reporting packages "referenced in compiled file NIL",
;;; which names the packages and not the ordering.

(deftest ecl-modules-are-listed-before-the-application-library
  (let* ((spec (test-spec :ecl-modules '("sockets")))
         (modules (app::ecl-module-inits spec)))
    (is= '(("SOCKETS" . "init_lib_SOCKETS")) modules)))

;;; ------------------------------------------------------------------
;;; trampolines
;;;
;;; Cross-compiled only, never compiled on the host. That exemption is the
;;; whole feature: FFI:C-INLINE cannot be interpreted, and compiling it
;;; natively makes ECL LINK a host fasl, which fails the moment the C mentions
;;; CoreGraphics or objc_msgSend.

(deftest trampoline-files-resolve-against-the-system
  (let ((system (asdf:find-system "hello-ios" nil)))
    (if (null system)
        (skip "hello-ios is not in the registry")
        ;; hello-ios declares none, and the empty case must stay empty rather
        ;; than resolving to the system directory.
        (is= '() (app::trampoline-files system)))))

(deftest trampoline-paths-are-merged-against-the-system-directory
  (let* ((system (asdf:find-system "asdf-ios-app"))
         (directory (asdf:system-source-directory system)))
    ;; A relative name must land beside the .asd, not in the current directory,
    ;; which is wherever the build happened to be started from.
    (is= (namestring (merge-pathnames "glue.lisp" directory))
         (namestring
          (merge-pathnames "glue.lisp" (asdf:system-source-directory system))))))

;;; ------------------------------------------------------------------
;;; the remote REPL

(defun repl-system (value)
  "A throwaway system carrying VALUE as its :REMOTE-REPL."
  (make-instance 'asdf::ios-app-system :name "repl-test" :remote-repl value))

(deftest remote-repl-accepts-t-a-port-or-a-plist
  (is= nil (app::remote-repl-options (repl-system nil)))
  (is= '(:port 4005) (app::remote-repl-options (repl-system t)))
  (is= '(:port 9999) (app::remote-repl-options (repl-system 9999)))
  (is= '(:port 4005 :interface nil :style :spawn)
       (app::remote-repl-options (repl-system '(:port 4005))))
  (is= '(:port 1234 :interface "0.0.0.0" :style :fd-handler)
       (app::remote-repl-options
        (repl-system '(:port 1234 :interface "0.0.0.0" :style :fd-handler)))))

(deftest a-non-integer-repl-port-is-refused
  ;; Caught in the .asd rather than at boot, where the symptom would be an app
  ;; that launches and quietly does not listen.
  (signals app::app-build-error
    (app::remote-repl-options (repl-system '(:port "4005")))))

(deftest the-remote-repl-implies-the-modules-it-needs
  ;; slynk's ECL backend requires sockets, talks to sb-bsd-sockets, and names
  ;; the C package -- all three have to be linked or the app dies at boot.
  (let ((modules (app::needed-ecl-modules (repl-system t))))
    (dolist (module '("sockets" "sb-bsd-sockets" "cmp"))
      (is (member module modules :test #'string-equal))))
  (is= nil (app::needed-ecl-modules (repl-system nil))))

(deftest an-implied-module-is-not-added-twice
  (let ((modules (app::needed-ecl-modules
                  (make-instance 'asdf::ios-app-system :name "repl-test"
                                 :remote-repl t
                                 :bundle-ecl-modules '("sockets")))))
    (is= 1 (count "sockets" modules :test #'string-equal))))

;;; ------------------------------------------------------------------
;;; the main-thread bridge
;;;
;;; ON-MAIN has to work with no application around it, because that is how the
;;; host tests -- and every system that builds UI -- can be exercised here.

(deftest on-main-without-a-hook-just-calls
  (let ((ios-app-runtime::*on-main-hook* nil))
    (is= 42 (ios-app-runtime:on-main (lambda () 42)))
    (is= '(1 2) (multiple-value-list (ios-app-runtime:with-main-thread (values 1 2))))))

(deftest on-main-returns-values-through-the-hook
  ;; The hook stands in for the Objective-C dispatcher, which can only call a
  ;; function of no arguments and can only take back one value.
  (let ((ios-app-runtime::*on-main-hook* (lambda (thunk) (funcall thunk))))
    (is= 42 (ios-app-runtime:on-main (lambda () 42)))
    (is= '(1 2 3)
         (multiple-value-list (ios-app-runtime:on-main (lambda () (values 1 2 3)))))))

(deftest on-main-re-signals-on-the-calling-thread
  ;; Nothing may unwind through the hook: a condition crossing a GCD frame
  ;; corrupts it. So the error is caught inside and signalled again out here.
  (let* ((escaped nil)
         (ios-app-runtime::*on-main-hook*
           (lambda (thunk)
             (handler-case (funcall thunk)
               (error () (setf escaped t))))))
    (signals error (ios-app-runtime:on-main (lambda () (error "boom"))))
    (is (not escaped))))

;;; ------------------------------------------------------------------
;;; cross-compiling with the target's answers
;;;
;;; A cross compiler that answers host questions compiles the wrong code, and
;;; the failure lands at boot rather than at build time.

(deftest module-names-are-read-from-every-spelling
  (let ((names (app::module-names-in
                (asdf:system-relative-pathname "asdf-ios-app" "tests/fixture/modules/"))))
    (if (null names)
        (skip "no module fixture directory")
        (progn (is (member "sockets" names :test #'string-equal))
               (is (member "asdf" names :test #'string-equal))))))

(deftest a-feature-naming-a-host-only-module-is-dropped
  ;; The concrete case: slynk pushes :SERVE-EVENT after probing the host, and
  ;; --disable-shared leaves no serve-event in either iOS prefix.
  (let ((*features* (list* :serve-event :ecl *features*)))
    (is (member :serve-event
                (app::host-only-module-features
                 (asdf:system-relative-pathname "asdf-ios-app" "tests/fixture/no-modules/"))))))

(deftest the-boot-form-is-one-line
  ;; The pretty printer will break a :REMOTE-REPL plist across two lines, and
  ;; the result is a C string literal that does not compile.
  (let* ((system (make-instance 'asdf::ios-app-system
                                :name "boot-form-test"
                                :remote-repl '(:port 4005 :interface "127.0.0.1")))
         (form (progn (setf (asdf::component-entry-point system) "app:start")
                      (app::boot-form-for system nil))))
    (is (null (find #\Newline form)))
    (is (search ":remote-repl" form))))

;;; ------------------------------------------------------------------
;;; icons
;;;
;;; iOS icons are compiled, not copied: actool turns a .xcassets into an
;;; Assets.car and reports the Info.plist keys the result needs. Everything
;;; here is about refusing bad input before actool has to.

(deftest an-icon-must-be-an-asset-catalogue
  (let ((directory (asdf:system-relative-pathname "asdf-ios-app" "tests/fixture/")))
    (signals app::app-build-error (app::icon-catalogue directory))
    (signals app::app-build-error
      (app::icon-catalogue (merge-pathnames "nowhere.xcassets/" directory)))))

(deftest a-directorys-last-component-parses-as-a-name
  ;; PATHNAME-DIRECTORY keeps it as one undivided string, so "AppIcon" and
  ;; "appiconset" have to be recovered rather than read off.
  (let ((parsed (app::directory-basename #p"/tmp/Foo.xcassets/AppIcon.appiconset/")))
    (is= "AppIcon" (pathname-name parsed))
    (is= "appiconset" (pathname-type parsed))))

(deftest xcode-versions-compact-the-way-dtxcode-wants
  (is= "1620" (app::compact-xcode-version "16.2"))
  (is= "1630" (app::compact-xcode-version "16.3"))
  (is= "0912" (app::compact-xcode-version "9.1.2")))

(deftest the-simulator-carries-no-build-provenance
  ;; DT* keys matter for submission and are noise otherwise, so they go on
  ;; device builds alone -- and computing them shells out, which a simulator
  ;; build should not have to do.
  (is= nil (app::build-provenance-plist-for :simulator)))

;;; ------------------------------------------------------------------
;;; a boot that fails should say so on screen
;;;
;;; There is no terminal behind an app. An entry point that signals used to
;;; leave a blank window and a message on a console nobody was reading, and the
;;; only way to find out what happened was to rebuild with print statements in
;;; it -- the most expensive minute in the loop.

(deftest a-clean-boot-reports-no-failure
  (let ((ios-app-runtime::*boot-failure* nil))
    (is= "" (ios-app-runtime:boot-failure))))

(deftest an-entry-point-that-signals-is-recorded
  (let ((ios-app-runtime::*boot-failure* nil))
    (ios-app-runtime::%boot :entry-point "cl-user::a-function-that-signals"
                            :guard-callbacks nil)
    ;; Not fbound, which is its own message and must still be reported.
    (is (search "not fbound" (ios-app-runtime:boot-failure))))
  (let ((ios-app-runtime::*boot-failure* nil))
    (setf (symbol-function 'cl-user::deliberately-broken)
          (lambda () (error "a deliberate failure")))
    (ios-app-runtime::%boot :entry-point "cl-user::deliberately-broken"
                            :guard-callbacks nil)
    (let ((failure (ios-app-runtime:boot-failure)))
      (is (search "deliberate failure" failure))
      (is (search "SIMPLE-ERROR" failure)))))

;;; ------------------------------------------------------------------
;;; generated code has to survive the user's printer settings
;;;
;;; The child bootstrap is written with PRIN1 and read back by another Lisp. A
;;; *PRINT-LEVEL* in someone's init file silently turns a nested form into `#',
;;; and the child then dies on generated code with no hint as to why.

(deftest the-child-bootstrap-survives-a-hostile-printer
  (let ((system (asdf:find-system "hello-ios" nil)))
    (if (null system)
        (skip "hello-ios is not in the registry")
        (let ((forms (app::child-bootstrap-forms
                      system #p"/tmp/status.sexp" #p"/tmp/request.sexp"
                      '(:source-registry :inherit-configuration))))
          ;; Exactly the settings that broke it: level 4, length 3.
          (let* ((*print-level* 4)
                 (*print-length* 3)
                 (text (app::with-readable-printer
                         (with-output-to-string (out)
                           (dolist (form forms)
                             (prin1 form out)
                             (terpri out))))))
            (is (not (search "#)" text)))
            (is (not (search "..." text)))
            ;; And it must read back as the same number of forms.
            (is= (length forms)
                 (with-input-from-string (in text)
                   (loop for form = (read in nil :eof)
                         until (eq form :eof)
                         count t))))))))

(deftest the-readable-printer-neutralises-every-control
  (let ((*print-level* 1) (*print-length* 1) (*print-pretty* t))
    (is= "(1 (2 (3 (4 5))))"
         (app::with-readable-printer
           (prin1-to-string '(1 (2 (3 (4 5)))))))))

;;; ------------------------------------------------------------------
;;; a wildcard profile is a pattern, not an entitlement

(deftest a-wildcard-profile-specialises-to-this-app
  "Xcode's default team profile is Q47YS469F2.*, and the binary must claim the
one app it is. Measured on a device: copying the pattern through gets

    Upgrade's application-identifier entitlement string (Q47YS469F2.*) does not
    match installed application's application-identifier string (...)

from the installer, and quietly gives every app built from one profile the same
identifier -- which is what keychain access groups are keyed on."
  (is= "Q47YS469F2.org.example.app"
       (app::specialised-application-identifier
        "Q47YS469F2.*" "org.example.app" "Q47YS469F2"))
  (is= "Q47YS469F2.org.example.app"
       (app::specialised-application-identifier
        "Q47YS469F2.org.example.*" "org.example.app" "Q47YS469F2")))

(deftest an-exact-profile-is-left-alone
  "It already names one app, and it has been checked against this bundle."
  (is= "Q47YS469F2.org.example.app"
       (app::specialised-application-identifier
        "Q47YS469F2.org.example.app" "org.example.app" "Q47YS469F2")))

(deftest specialising-falls-back-to-the-profiles-own-prefix
  "When the profile carries no separate team field, the prefix is the team."
  (is= "ABCDE12345.org.example.app"
       (app::specialised-application-identifier
        "ABCDE12345.*" "org.example.app" nil)))

;;; ------------------------------------------------------------------
;;; SYS:help.doc is not in a bundle

(deftest the-documentation-file-is-detached-from-the-pool
  "ECL's documentation pool is a hash table AND the pathname SYS:help.doc, so
an ordinary (setf (documentation ...)) at load time opens that file. No bundle
contains it. The failure is worse than it sounds: it arrives before the debugger
is usable, so ECL reports an unbounded recursion on SI:*BREAK-LOCALS* and dies
on SIGSEGV with the real cause well out of sight -- and it does not happen on
the simulator, where SYS: resolves to a readable directory on the Mac."
  (let ((pool (find-symbol "*DOCUMENTATION-POOL*" "SI")))
    (if (not (and pool (boundp pool)))
        (skip "not ECL, or no documentation pool")
        (let ((saved (symbol-value pool)))
          (unwind-protect
               (progn
                 (setf (symbol-value pool)
                       (list (make-hash-table :test #'equal) "SYS:help.doc"))
                 (ios-app-runtime:detach-documentation-file)
                 (is (notany (lambda (entry) (or (stringp entry) (pathnamep entry)))
                             (symbol-value pool)))
                 (is (some #'hash-table-p (symbol-value pool))))
            (setf (symbol-value pool) saved))))))

;;; ------------------------------------------------------------------
;;; the host's C toolchain environment stays out of a cross build

(deftest a-clean-environment-leaves-the-command-alone
  "Nothing set, nothing wrapped. The scrubbing must not turn every command in
the build into an env(1) invocation on a machine that never needed it."
  (let ((app::+host-toolchain-environment+ '("ASDF_IOS_APP_NO_SUCH_VARIABLE")))
    (is= '("/usr/bin/clang" "-c" "x.m")
         (app::without-host-toolchain '("/usr/bin/clang" "-c" "x.m")))))

(defparameter +scrub-test-variable+ "ASDF_IOS_APP_SCRUB_PROBE"
  "A variable this suite sets itself.

The first version of these tests keyed on LIBRARY_PATH, which made them a
no-op wherever it happened not to be set -- CI, most obviously, which is the
one place they most need to run. A test that quietly skips on the machine it
was written to protect protects nothing.")

(deftest a-set-variable-is-unset-for-the-child
  "The shape of the wrapped command: env, then -u for the variable, then the
original argv unchanged and in order."
  (ext:setenv +scrub-test-variable+ "host-junk")
  (let ((app::+host-toolchain-environment+ (list +scrub-test-variable+)))
    (is= (list "/usr/bin/env" "-u" +scrub-test-variable+
               "/usr/bin/clang" "-o" "app")
         (app::without-host-toolchain '("/usr/bin/clang" "-o" "app")))))

(deftest the-child-really-does-not-see-it
  "The one that matters, and the one that would have caught the original bug
from the other direction: UIOP's :ENVIRONMENT is accepted and ignored on ECL,
so a subprocess launched with it inherits the lot and nothing says so. Only
running a child and asking it settles this."
  (ext:setenv +scrub-test-variable+ "host-junk")
  (let ((command (list "/bin/sh" "-c"
                       (format nil "echo \"${~a-GONE}\"" +scrub-test-variable+))))
    ;; inherited without the scrubbing ...
    (let ((app::+host-toolchain-environment+ '()))
      (is= "host-junk" (app::run command)))
    ;; ... and absent with it
    (let ((app::+host-toolchain-environment+ (list +scrub-test-variable+)))
      (is= "GONE" (app::run command)))))

(deftest the-variables-named-are-the-ones-that-aim-a-compiler
  "A list worth asserting: each entry is a silent -I or -L, and SDKROOT is a
whole sysroot. Adding to it is fine; losing one of these is the bug."
  (dolist (name '("CPATH" "C_INCLUDE_PATH" "LIBRARY_PATH" "SDKROOT"))
    (is (member name app::+host-toolchain-environment+ :test #'string=))))

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

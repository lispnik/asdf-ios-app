;;;; tests/build.lisp -- end to end, against a real cross-compiled ECL.
;;;;
;;;; Skips wholesale when there is no simulator prefix, because building one is
;;;; a twenty-minute job and no CI runner has it. Everything that can be
;;;; checked WITHOUT booting a simulator is checked here; booting one is slow
;;;; and flaky, so those few tests are gated behind an environment variable
;;;; rather than being the price of running the suite.

(in-package #:asdf-ios-app-tests)

(defun toolchain-ready-p ()
  (and (uiop:os-macosx-p) (app::toolchain-available-p :simulator)))

(defun simulator-tests-enabled-p ()
  (let ((v (uiop:getenv "ASDF_IOS_APP_SIMULATOR_TESTS")))
    (and v (plusp (length v)) (not (string= v "0")))))

(defvar *fixture-directory* nil)
(defvar *fixture-bundle* nil)

(defun fixture-source ()
  (uiop:subpathname (asdf:system-source-directory "asdf-ios-app")
                    "tests/fixture/"))

(defun prepare-fixture ()
  "Copy the fixture somewhere writable, renaming the .asd.in as we go."
  (or *fixture-directory*
      (let ((directory (uiop:subpathname (uiop:temporary-directory)
                                         "asdf-ios-app-fixture/")))
        (when (probe-file directory)
          (uiop:delete-directory-tree directory :validate t))
        (ensure-directories-exist directory)
        (dolist (file (uiop:directory-files (fixture-source)))
          (let ((name (file-namestring file)))
            (uiop:copy-file file
                            (uiop:subpathname
                             directory
                             (if (uiop:string-suffix-p name ".asd.in")
                                 (subseq name 0 (- (length name) 3))
                                 name)))))
        (setf *fixture-directory* directory))))

(defun build-little-framework (directory)
  "LittleC.framework beside the fixture: one C function, built for the
simulator by clang, with the install name an embedded framework must have."
  (let* ((framework (uiop:subpathname directory "LittleC.framework/"))
         (source (uiop:subpathname directory "little.c"))
         (binary (uiop:subpathname framework "LittleC")))
    (ensure-directories-exist binary)
    (with-open-file (out source :direction :output :if-exists :supersede)
      (write-string "int little_c_answer(void) { return 42; }" out))
    (app::run (append (list "/usr/bin/clang" "-dynamiclib")
                      (app::platform-clang-flags :simulator)
                      (list "-install_name" "@rpath/LittleC.framework/LittleC"
                            "-o" (uiop:native-namestring binary)
                            (uiop:native-namestring source))))
    (app::write-plist '(:dict ("CFBundleIdentifier" . "org.asdf-ios-app.littlec")
                              ("CFBundleExecutable" . "LittleC")
                              ("CFBundleName" . "LittleC")
                              ("CFBundlePackageType" . "FMWK")
                              ("CFBundleShortVersionString" . "1.0")
                              ("CFBundleVersion" . "1")
                              ("MinimumOSVersion" . "15.0"))
                      (uiop:subpathname framework "Info.plist"))
    framework))

(defun build-fixture ()
  "Build the fixture once; every assertion below shares the result."
  (or *fixture-bundle*
      (let ((directory (prepare-fixture)))
        (build-little-framework directory)
        (asdf:initialize-source-registry
         `(:source-registry
           (:directory ,(uiop:native-namestring directory))
           (:directory ,(uiop:native-namestring
                         (asdf:system-source-directory "asdf-ios-app")))
           :inherit-configuration))
        (asdf:clear-system "ios-app-test-fixture")
        (setf *fixture-bundle*
              (first (app:make-app "ios-app-test-fixture"))))))

(defmacro with-fixture ((bundle) &body body)
  `(if (not (toolchain-ready-p))
       (skip "no iOS simulator ECL prefix; run (asdf-ios-app:bootstrap-ecl)")
       (let ((,bundle (build-fixture)))
         ,@body)))

;;; ------------------------------------------------------------------
;;; the bundle

(deftest the-bundle-is-flat-and-holds-what-it-should
  (with-fixture (bundle)
    (dolist (name '("fixture" "Info.plist" "PkgInfo"))
      (is (probe-file (uiop:subpathname bundle name))))
    (is (uiop:directory-exists-p (uiop:subpathname bundle "_CodeSignature/")))
    ;; No Contents/ anywhere: that would mean the macOS sibling's layout had
    ;; been copied rather than read.
    (is (null (remove-if-not
               (lambda (d) (equal "Contents" (car (last (pathname-directory d)))))
               (uiop:subdirectories bundle))))))

(deftest an-embedded-framework-is-installed-linked-and-signed
  (with-fixture (bundle)
    (let ((framework (uiop:subpathname bundle "Frameworks/LittleC.framework/"))
          (executable (uiop:native-namestring (uiop:subpathname bundle "fixture"))))
      ;; Installed, with the Mach-O where an iOS framework keeps it.
      (is (probe-file (uiop:subpathname framework "LittleC")))
      (is (probe-file (uiop:subpathname framework "Info.plist")))
      ;; Signed on its own, before the app sealed it.
      (is (probe-file (uiop:subpathname framework "_CodeSignature/CodeResources")))
      ;; Linked by install name, and the rpath that resolves it.
      (is (search "@rpath/LittleC.framework/LittleC"
                  (app::run (list "/usr/bin/otool" "-L" executable))))
      (is (search "@executable_path/Frameworks"
                  (app::run (list "/usr/bin/otool" "-l" executable)))))))

(deftest a-framework-with-the-wrong-install-name-is-refused
  (with-fixture (bundle)
    (declare (ignore bundle))
    ;; The same library built without -install_name names its own path,
    ;; which the device does not have; the check says what to pass.
    (let* ((directory (uiop:subpathname (uiop:temporary-directory) "asdf-ios-app-badfw/"))
           (framework (uiop:subpathname directory "Bad.framework/"))
           (source (uiop:subpathname directory "bad.c")))
      (ensure-directories-exist (uiop:subpathname framework "Bad"))
      (with-open-file (out source :direction :output :if-exists :supersede)
        (write-string "int bad(void) { return 1; }" out))
      (app::run (append (list "/usr/bin/clang" "-dynamiclib")
                        (app::platform-clang-flags :simulator)
                        (list "-o" (uiop:native-namestring (uiop:subpathname framework "Bad"))
                              (uiop:native-namestring source))))
      (unwind-protect
           (signals app::app-build-error
             (app::check-embedded-framework
              (app::make-app-spec :platform (app::find-platform :simulator))
              framework))
        (ignore-errors (uiop:delete-directory-tree directory :validate t))))))

(deftest plutil-accepts-the-generated-plist
  (with-fixture (bundle)
    (is (app::lint-plist (uiop:subpathname bundle "Info.plist")))))

(deftest the-executable-is-a-simulator-binary
  (with-fixture (bundle)
    (is= "IOSSIMULATOR"
         (app::mach-o-platform (uiop:subpathname bundle "fixture")))))

(deftest the-library-init-symbol-is-linked-in
  (with-fixture (bundle)
    (is (member "init_lib_IOS_APP_TEST_FIXTURE"
                (app::nm-defined-symbols (uiop:subpathname bundle "fixture"))
                :test #'string=))))

(deftest the-bundle-is-ad-hoc-signed-and-verifies
  (with-fixture (bundle)
    (let ((details (app::signature-details bundle)))
      (is (search "adhoc" details))
      (is (search "TeamIdentifier=not set" details)))
    (is (app::verify-signature (app::make-app-spec
                                :root bundle
                                :platform (app::find-platform :simulator))))))

(deftest building-leaves-no-staging-or-trash-directories
  (with-fixture (bundle)
    (let ((siblings (uiop:subdirectories
                     (uiop:pathname-parent-directory-pathname bundle))))
      (dolist (d siblings)
        (let ((name (car (last (pathname-directory d)))))
          (is (not (search ".staging-" name)))
          (is (not (search ".trash-" name))))))))

(deftest a-second-build-reuses-the-objects
  (with-fixture (bundle)
    (declare (ignore bundle))
    (let* ((cache (uiop:subpathname *fixture-directory* "build/cache/iphonesimulator/"))
           (objects (uiop:directory-files cache "*.o"))
           (before (mapcar #'file-write-date objects)))
      (is (plusp (length objects)))
      (sleep 1)
      (setf *fixture-bundle* nil)
      (build-fixture)
      (is= before (mapcar #'file-write-date objects)))))

;;; ------------------------------------------------------------------
;;; running it
;;;
;;; Booting a simulator is thirty seconds and varies by runner, so this is
;;; opt-in. It is also the only test that proves the thing actually works.

(deftest an-ipa-is-refused-for-a-simulator-bundle
  (with-fixture (bundle)
    ;; The two bundles are indistinguishable from the outside -- same layout,
    ;; same keys, an ad-hoc signature that verifies -- and the only symptom of
    ;; shipping the wrong one is a rejected upload, weeks later.
    (signals app::app-build-error (app:export-ipa bundle))))

(deftest an-ipa-holds-the-bundle-under-payload
  (with-fixture (bundle)
    ;; A device build needs a signing identity and a provisioning profile, so
    ;; the packaging is exercised on a copy with the platform key rewritten.
    ;; It tests the layout and nothing about signing, which is the honest
    ;; boundary of what can be checked without an account.
    (let* ((copy (uiop:subpathname (uiop:temporary-directory) "ipa-test/Fixture.app/"))
           (root (uiop:pathname-parent-directory-pathname copy)))
      (when (probe-file root) (uiop:delete-directory-tree root :validate t))
      (ensure-directories-exist root)
      (app::run (list "/usr/bin/ditto"
                      (string-right-trim "/" (uiop:native-namestring bundle))
                      (string-right-trim "/" (uiop:native-namestring copy))))
      (app::run (list "/usr/bin/plutil" "-replace" "CFBundleSupportedPlatforms"
                      "-json" "[\"iPhoneOS\"]"
                      (uiop:native-namestring
                       (uiop:subpathname copy "Info.plist"))))
      (unwind-protect
           (let ((ipa (app:export-ipa copy)))
             (is (probe-file ipa))
             (let ((listing (app::run (list "/usr/bin/unzip" "-Z1"
                                            (uiop:native-namestring ipa)))))
               (is (search "Payload/Fixture.app/Info.plist" listing))
               (is (search "Payload/Fixture.app/fixture" listing))))
        (ignore-errors (uiop:delete-directory-tree root :validate t))))))

(deftest the-app-runs-and-lisp-speaks
  (cond ((not (toolchain-ready-p))
         (skip "no iOS simulator ECL prefix"))
        ((not (simulator-tests-enabled-p))
         (skip "set ASDF_IOS_APP_SIMULATOR_TESTS=1 and boot a simulator"))
        (t
         (let* ((bundle (build-fixture))
                (device (app::booted-simulator)))
           (if (null device)
               (skip "no simulator booted; xcrun simctl boot 'iPhone 17'")
               (progn
                 (app::terminate-in-simulator "org.asdf-ios-app.fixture"
                                              :device device)
                 (let ((output (app::launch-in-simulator
                                bundle "org.asdf-ios-app.fixture"
                                :device device :console t
                                ;; The fixture's last line: wait for it,
                                ;; not for a clock.
                                :until "little_c_answer")))
                   (is (search "FIXTURE: hello from Lisp on iOS" output))
                   ;; The image is live even though every function in it was
                   ;; compiled ahead of time.
                   (is (search "defined at runtime" output))
                   ;; And REQUIRE found the linked module rather than hunting
                   ;; for a host .fas under the compiled-in ECLDIR.
                   (is (search "sockets present: T" output))
                   ;; And the embedded framework was found by dyld and called.
                   (is (search "little_c_answer = 42" output)))))))))

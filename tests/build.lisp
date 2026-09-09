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

(defun build-fixture ()
  "Build the fixture once; every assertion below shares the result."
  (or *fixture-bundle*
      (let ((directory (prepare-fixture)))
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
                                :device device :console t)))
                   (is (search "FIXTURE: hello from Lisp on iOS" output))
                   ;; The image is live even though every function in it was
                   ;; compiled ahead of time.
                   (is (search "defined at runtime" output))
                   ;; And REQUIRE found the linked module rather than hunting
                   ;; for a host .fas under the compiled-in ECLDIR.
                   (is (search "sockets present: T" output)))))))))

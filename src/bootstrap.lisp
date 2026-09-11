;;;; bootstrap.lisp -- get a usable iOS ECL, in one command.
;;;;
;;;; Working out how to build ECL for iOS is most of a day: the host ECL has to
;;;; come from the same tree as the cross builds, fixes are needed that are not
;;;; upstream, and the cross-config and platform flags are not written down
;;;; anywhere obvious. None of that is interesting and nobody should have to
;;;; rediscover it, so it is one function.
;;;;
;;;; The recipe itself lives in tools/build-ecl-ios.sh rather than here. A
;;;; shell script is the readable artefact for a thing that is entirely
;;;; ./configure and make, it can be run by someone who has no Lisp yet, and
;;;; having one copy means the two cannot disagree.

(in-package #:asdf-ios-app)

(defvar *ecl-repository* "https://github.com/lispnik/ecl.git"
  "Where BOOTSTRAP-ECL clones ECL from.

A fork, until its fixes are upstream. Its objc-develop branch is upstream
develop plus three, each on its own branch there for sending on: RTLD_DEFAULT
for the :default module, FFI:CALLBACK returning a closure's entry point rather
than its writable record, and structures by value through SI:CALL-CFUN. Set
this back to https://gitlab.com/embeddable-common-lisp/ecl.git the day they
land.")

(defvar *ecl-revision* "objc-develop"
  "The revision to build.

A moving branch by default, which is a deliberate trade: the fixes this needs
are not upstream, and a pinned commit would have to be revised every time they
land or the surrounding code moves. Pass :REVISION to pin one.")

(defparameter +patch-directory+ "tools/patches/"
  "Relative to this system's source directory.")

(defun system-file (relative)
  (uiop:subpathname (asdf:system-source-directory "asdf-ios-app") relative))

;;; ------------------------------------------------------------------
;;; patches

(defun patch-files ()
  (sort (uiop:directory-files (system-file +patch-directory+) "*.patch")
        #'string< :key #'namestring))

(defun patch-applies-p (tree patch)
  (zerop (nth-value 2 (run (list "/usr/bin/git" "apply" "--check"
                                 (uiop:native-namestring patch))
                           :directory tree :ignore-error-status t))))

(defun patch-already-applied-p (tree patch)
  "Whether the tree already contains this change -- because we applied it on an
earlier run, or because it finally landed upstream.

Reversibility is the test. A patch that applies in reverse is one whose result
is already present, and that is the only question worth asking: this must not
start failing on the day the fix is released."
  (zerop (nth-value 2 (run (list "/usr/bin/git" "apply" "--check" "--reverse"
                                 (uiop:native-namestring patch))
                           :directory tree :ignore-error-status t))))

(defun apply-patches (tree)
  "Apply every patch that is needed and not yet present. Returns their names."
  (let ((applied '()))
    (dolist (patch (patch-files) (nreverse applied))
      (let ((name (file-namestring patch)))
        (cond ((patch-already-applied-p tree patch)
               (note "~a: already present, skipping" name))
              ((patch-applies-p tree patch)
               (note "applying ~a" name)
               (run (list "/usr/bin/git" "apply" (uiop:native-namestring patch))
                    :directory tree)
               (push name applied))
              (t
               (barf "~a does not apply to ~a and is not already present.~%~
                      ECL has moved under it. Pin a revision with :REVISION, ~
                      or refresh the patch."
                     name (uiop:native-namestring tree))))))))

;;; ------------------------------------------------------------------
;;; the source tree

(defun clean-tree-p (tree)
  "Whether TREE has no modifications to tracked files.

Untracked files do not count. An ECL checkout that has ever been built is full
of them -- build/, the install prefixes, generated Makefiles -- and refusing to
proceed on that basis would refuse essentially every real tree. What matters is
whether applying a patch might collide with an edit of the user's own."
  (zerop (length (run (list "/usr/bin/git" "status" "--porcelain"
                            "--untracked-files=no")
                      :directory tree))))

(defun ensure-ecl-source (&key source revision force)
  "A checked-out ECL tree at REVISION, cloned into the cache if none is given."
  (let ((tree (or source (uiop:subpathname (cache-directory) "ecl/"))))
    (cond ((probe-file (uiop:subpathname tree ".git/"))
           (unless (or force (clean-tree-p tree))
             (barf "~a has uncommitted changes. Pass :FORCE T to build it as ~
                    it stands, or point :SOURCE somewhere else."
                   (uiop:native-namestring tree)))
           (when (and revision (not source))
             (note "fetching ~a" revision)
             (run (list "/usr/bin/git" "fetch" "--quiet" "origin") :directory tree)
             (run (list "/usr/bin/git" "checkout" "--quiet" revision)
                  :directory tree)))
          (source
           (barf "~a is not a git checkout of ECL."
                 (uiop:native-namestring source)))
          (t
           (ensure-directories-exist tree)
           (note "cloning ECL into ~a" (uiop:native-namestring tree))
           (run (list "/usr/bin/git" "clone" "--quiet"
                      *ecl-repository* (uiop:native-namestring tree)))
           (when revision
             (run (list "/usr/bin/git" "checkout" "--quiet" revision)
                  :directory tree))))
    (uiop:ensure-directory-pathname tree)))

(defun tree-revision (tree)
  (run (list "/usr/bin/git" "rev-parse" "--short" "HEAD") :directory tree))

;;; ------------------------------------------------------------------
;;; the build

(defun seconds-since (start)
  (/ (- (get-internal-real-time) start) internal-time-units-per-second))

(defun run-build-script (tree root platforms)
  (let ((script (system-file "tools/build-ecl-ios.sh")))
    (dolist (name platforms)
      (let ((start (get-internal-real-time)))
        (note "building ~a" name)
        ;; Output is passed through rather than captured: this takes minutes,
        ;; and a build that prints nothing for four minutes looks hung.
        (uiop:run-program (list "/bin/sh" (uiop:native-namestring script)
                               (uiop:native-namestring tree)
                               (uiop:native-namestring root)
                               name)
                          :output t :error-output t)
        (note "~a took ~,1f s" name (seconds-since start))))))

(defun bootstrap-ecl (&key source revision platforms force)
  "Clone, patch and build the ECLs an iOS build needs. Returns the toolchain.

SOURCE uses an ECL tree you already have instead of cloning one. REVISION
overrides *ECL-REVISION*. PLATFORMS defaults to both. FORCE proceeds on a dirty
tree.

Roughly ten minutes from nothing. The host ECL is much the largest part and is
reused afterwards, so building one more platform later is a few minutes.

This is never run by ASDF:MAKE. Building a compiler is not something a build
should do behind your back."
  (require-darwin "Building ECL for iOS")
  (let* ((platforms (or platforms '(:simulator :device)))
         (names (mapcar (lambda (k) (platform-name (find-platform k))) platforms))
         (root (uiop:subpathname (cache-directory) "ecl-ios/"))
         (tree (ensure-ecl-source :source source
                                  :revision (or revision
                                                (and (not source) *ecl-revision*))
                                  :force force))
         (applied (apply-patches tree)))
    (ensure-directories-exist root)
    ;; The host ECL first and always: the cross builds cannot run without it,
    ;; and the script makes it a no-op when it is already current.
    (run-build-script tree root (cons "host" names))
    (let ((plist (list :host (uiop:subpathname root "host/bin/ecl")
                       :device (uiop:subpathname root "iphoneos/")
                       :simulator (uiop:subpathname root "iphonesimulator/")
                       :source tree
                       :revision (tree-revision tree)
                       :patches applied)))
      ;; Only the platforms actually built are worth recording.
      (dolist (p +platforms+)
        (unless (member (platform-key p) platforms)
          (remf plist (platform-key p))))
      (note "wrote ~a" (uiop:native-namestring (write-toolchain plist)))
      (dolist (key platforms)
        (check-ecl-prefix key))
      plist)))

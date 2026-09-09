;;;; sign.lisp -- codesign.
;;;;
;;;; A statically linked iOS app is one Mach-O with no nested code, so this is
;;;; a single codesign call. The macOS sibling's walk over Frameworks/, helper
;;;; executables and login items has nothing to find here.

(in-package #:asdf-ios-app)

(defparameter +ios-entitlements+
  '(:dict ("get-task-allow" . :true))
  "The minimum for a DEVICE development build. get-task-allow is what lets a
debugger attach, and a distribution build must not have it.")

(defun entitlements-file (spec)
  "The entitlements to sign with, or NIL for none.

:IOS-DEFAULT means none on the simulator and get-task-allow on device. That
asymmetry is not tidiness. iOS validates a binary's entitlements against its
provisioning profile, and a simulator app has no profile -- so an ad-hoc
signature carrying get-task-allow is refused by SpringBoard at launch:

  The request to open \"...\" failed.
  The request was denied by service delegate (SBMainWorkspace).

which says nothing about entitlements and sends you looking at Info.plist. An
Xcode-built simulator app carries no entitlements at all; this matches it."
  (let ((e (spec-entitlements spec)))
    (etypecase e
      (null nil)
      (pathname e)
      (string (pathname e))
      (symbol
       (assert (eq e :ios-default))
       (cond ((platform-simulator-p (spec-platform spec)) nil)
             ((not (spec-get-task-allow-p spec)) nil)
             (t
              ;; Beside the bundle, not inside it: entitlements are an input to
              ;; codesign, and a copy left in the bundle would be signed as a
              ;; resource and shipped for no reason.
              (let ((path (sibling-file (spec-root spec) "entitlements.plist")))
                (lint-plist (write-plist +ios-entitlements+ path))
                path)))))))

(defun sibling-file (directory name)
  (uiop:subpathname (uiop:pathname-parent-directory-pathname
                     (uiop:ensure-directory-pathname directory))
                    name))

(defun effective-identity (spec)
  "The identity to sign with.

:AUTOMATIC means ad hoc on the simulator, which needs no developer account at
all, and a hard error on device, where guessing would produce a bundle that
installs and then refuses to launch."
  (let ((identity (spec-signing-identity spec)))
    (cond ((eq identity :automatic)
           (if (platform-simulator-p (spec-platform spec))
               "-"
               (barf "A device build needs a signing identity. Set ~
                      :CODE-SIGNING-IDENTITY, or build for the simulator, ~
                      which needs no account.")))
          (t identity))))

(defun codesign (path identity &key entitlements)
  (run (append (list "/usr/bin/codesign" "--force" "--sign" identity)
               (when entitlements
                 (list "--entitlements" (uiop:native-namestring entitlements)))
               (list (string-right-trim "/" (uiop:native-namestring path))))
       :echo-error t))

(defun verify-signature (spec)
  (multiple-value-bind (out err code)
      (run (list "/usr/bin/codesign" "--verify" "--strict" "--verbose=2"
                 (string-right-trim "/" (uiop:native-namestring (spec-root spec))))
           :ignore-error-status t)
    (declare (ignore out))
    (unless (zerop code)
      (barf "codesign rejected the bundle:~%~a" err))
    t))

(defun sign-bundle (spec)
  (let ((identity (effective-identity spec)))
    (when identity
      (codesign (spec-root spec) identity
                :entitlements (entitlements-file spec))
      (verify-signature spec))
    identity))

(defun signature-details (path)
  "What codesign thinks of a bundle, for tests and for looking at."
  (nth-value 1 (run (list "/usr/bin/codesign" "-dvvv"
                          (string-right-trim "/" (uiop:native-namestring path)))
                    :ignore-error-status t)))

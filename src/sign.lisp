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
             (t
              ;; Beside the bundle, not inside it: entitlements are an input to
              ;; codesign, and a copy left in the bundle would be signed as a
              ;; resource and shipped for no reason.
              (let ((path (sibling-file (spec-root spec) "entitlements.plist")))
                (lint-plist (write-plist (profile-entitlements-form spec) path))
                path)))))))

(defun sibling-file (directory name)
  (uiop:subpathname (uiop:pathname-parent-directory-pathname
                     (uiop:ensure-directory-pathname directory))
                    name))

;;; ------------------------------------------------------------------
;;; provisioning profiles
;;;
;;; A .mobileprovision is a CMS-signed plist. security unwraps it and plutil
;;; reads values out, which is a lot cheaper than carrying a plist PARSER to
;;; match the writer -- and the only values wanted are a handful of strings.

(defun decode-profile (profile)
  "The profile's plist, as a string."
  (unless (probe-file profile)
    (barf "No provisioning profile at ~a." (uiop:native-namestring profile)))
  (run (list "/usr/bin/security" "cms" "-D" "-i"
             (uiop:native-namestring profile))))

(defun profile-value (decoded key)
  "One value out of a decoded profile, or NIL.

KEY is a plutil key path, so \"Entitlements.application-identifier\" reaches
into the nested dictionary."
  (let ((temp (uiop:tmpize-pathname
               (uiop:subpathname (uiop:temporary-directory) "profile.plist"))))
    (unwind-protect
         (progn
           (with-open-file (out temp :direction :output :if-exists :supersede)
             (write-string decoded out))
           (multiple-value-bind (value err code)
               (run (list "/usr/bin/plutil" "-extract" key "raw" "-o" "-"
                          (uiop:native-namestring temp))
                    :ignore-error-status t)
             (declare (ignore err))
             (and (zerop code) (plusp (length value)) value)))
      (ignore-errors (delete-file temp)))))

(defun application-identifier-matches-p (application-identifier bundle-identifier)
  "Whether a profile's application-identifier covers BUNDLE-IDENTIFIER.

The entitlement is TEAMID.com.example.app, or TEAMID.com.example.* for a
wildcard profile. Getting this wrong produces a bundle that installs and then
refuses to launch, with nothing on screen to say why, so it is worth checking
at build time."
  (let* ((dot (position #\. application-identifier))
         (pattern (and dot (subseq application-identifier (1+ dot)))))
    (cond ((null pattern) nil)
          ((string= pattern "*") t)
          ((uiop:string-suffix-p pattern ".*")
           (let ((prefix (subseq pattern 0 (- (length pattern) 1))))
             (and (>= (length bundle-identifier) (length prefix))
                  (string= prefix bundle-identifier :end2 (length prefix)))))
          (t (string= pattern bundle-identifier)))))

(defun check-provisioning-profile (spec)
  "Read the profile and refuse the obvious mismatches before signing."
  (let ((profile (spec-provisioning-profile spec)))
    (when profile
      (let* ((decoded (decode-profile profile))
             (application-identifier
               (profile-value decoded "Entitlements.application-identifier"))
             (team (profile-value decoded
                                  "Entitlements.com.apple.developer.team-identifier")))
        (unless application-identifier
          (barf "~a has no application-identifier entitlement; it does not look ~
                 like an iOS provisioning profile."
                (uiop:native-namestring profile)))
        (unless (application-identifier-matches-p application-identifier
                                                  (spec-identifier spec))
          (barf "The profile is for ~a but this app is ~a. They must match, or ~
                 the app installs and then refuses to launch."
                application-identifier (spec-identifier spec)))
        (when (and team (spec-team-id spec)
                   (string/= team (spec-team-id spec)))
          (note "profile team is ~a but :DEVELOPMENT-TEAM says ~a"
                team (spec-team-id spec)))
        (list :application-identifier application-identifier :team team)))))

(defun specialised-application-identifier (application-identifier bundle-identifier team)
  "The application-identifier entitlement for THIS app, from the profile's.

A wildcard profile's identifier is a PATTERN -- Q47YS469F2.* -- and a pattern is
not an entitlement. The binary must claim the one app it actually is, which is
what Xcode writes and what the installer compares against:

    Upgrade's application-identifier entitlement string (Q47YS469F2.*) does not
    match installed application's application-identifier string
    (Q47YS469F2.org.example.app); rejecting upgrade.

measured on a device. Copying the pattern through also signs every app built
from one team profile with an identical identifier, which is what keychain
access groups and app groups are keyed on -- so it is wrong in a quieter way
even when nothing rejects it.

An exact profile is returned unchanged: it already names one app, and it has
been checked against this bundle by CHECK-PROVISIONING-PROFILE."
  (let* ((dot (position #\. application-identifier))
         (pattern (and dot (subseq application-identifier (1+ dot))))
         (prefix (and dot (subseq application-identifier 0 dot))))
    (if (and pattern (or (string= pattern "*") (uiop:string-suffix-p pattern ".*")))
        (format nil "~a.~a" (or team prefix) bundle-identifier)
        application-identifier)))

(defun profile-entitlements-form (spec)
  "Entitlements derived FROM the profile rather than guessed.

iOS validates a binary's entitlements against its profile, so the profile is
the authority on what they must be. get-task-allow is ours to choose -- it is
what lets a debugger attach, and a distribution build must not have it."
  (let ((details (check-provisioning-profile spec)))
    (unless details
      (barf "A device build needs :PROVISIONING-PROFILE."))
    `(:dict
      ("application-identifier"
       . ,(specialised-application-identifier
           (getf details :application-identifier)
           (spec-identifier spec)
           (getf details :team)))
      ,@(when (getf details :team)
          `(("com.apple.developer.team-identifier" . ,(getf details :team))))
      ,@(when (spec-get-task-allow-p spec)
          `(("get-task-allow" . :true))))))

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

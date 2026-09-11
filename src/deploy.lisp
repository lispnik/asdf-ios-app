;;;; deploy.lisp -- getting a bundle onto something that runs it.
;;;;
;;;; Not part of a build. A build produces a .app; putting it somewhere is a
;;;; separate act, and one that fails for reasons -- no simulator booted, a
;;;; phone without Developer Mode -- that have nothing to do with the build.

(in-package #:asdf-ios-app)

(defun booted-simulator ()
  "The UDID of a booted simulator, or NIL."
  (let ((out (run (list "/usr/bin/xcrun" "simctl" "list" "devices" "booted")
                  :ignore-error-status t)))
    (loop for line in (uiop:split-string out :separator '(#\Newline))
          for open = (position #\( line :from-end t)
          when (and (search "Booted" line) open)
            return (let ((close (position #\) line :start open)))
                     (and close (subseq line (1+ open) close))))))

(defun require-booted-simulator ()
  (or (booted-simulator)
      (barf "No simulator is booted. Start one with:~%~
             xcrun simctl boot 'iPhone 17'")))

(defun install-in-simulator (bundle &key (device (require-booted-simulator)))
  (run (list "/usr/bin/xcrun" "simctl" "install" device
             (string-right-trim "/" (uiop:native-namestring bundle))))
  device)

(defvar *console-seconds* 15
  "How long LAUNCH-IN-SIMULATOR watches a console launch before giving up.")

(defun launch-in-simulator (bundle identifier
                            &key (device (require-booted-simulator)) console
                                 (seconds *console-seconds*))
  "Launch, and with CONSOLE return what the app writes to stdout and stderr.

The console form has to be run asynchronously and killed. simctl's
--console-pty stays attached until the app exits, and a UIKit app does not
exit -- so calling it synchronously does not capture output, it hangs the
build. Reading the device log instead would avoid that, but it is far harder to
attribute and much slower to appear."
  (install-in-simulator bundle :device device)
  (if (not console)
      (run (list "/usr/bin/xcrun" "simctl" "launch" device identifier))
      (let ((log (uiop:tmpize-pathname
                  (uiop:subpathname (uiop:temporary-directory)
                                    "asdf-ios-app-console.log"))))
        (unwind-protect
             (let ((process (uiop:launch-program
                             (list "/usr/bin/xcrun" "simctl" "launch"
                                   "--console-pty" device identifier)
                             :output log :error-output :output)))
               (unwind-protect (sleep seconds)
                 (ignore-errors (uiop:terminate-process process :urgent t))
                 (ignore-errors (uiop:wait-process process)))
               (if (probe-file log) (uiop:read-file-string log) ""))
          (ignore-errors (delete-file log))))))

(defun terminate-in-simulator (identifier &key (device (require-booted-simulator)))
  (run (list "/usr/bin/xcrun" "simctl" "terminate" device identifier)
       :ignore-error-status t))

(defun parse-device-listing (text)
  "The identifiers of the devices in devicectl's table that can be reached now.

A device that can be installed to reports itself as `available (paired)\'
when it is on the network and `connected\' when it is on a cable; one that
cannot says `unavailable\', which contains the first of those words and is
why the test is not a substring search for it."
  (loop for line in (uiop:split-string text :separator '(#\Newline))
        for fields = (tokens line)
        when (and (or (member "available" fields :test #'string=)
                      (member "connected" fields :test #'string=))
                  (not (member "unavailable" fields :test #'string=)))
          collect (find-if (lambda (token)
                             (and (= (length token) 36)
                                  (char= #\- (char token 8))))
                           fields)))

(defun available-devices ()
  "Physical iOS devices devicectl can install to, as identifiers.

Filtered to iOS by devicectl itself, because a paired Apple Watch appears
in the unfiltered list and sorts before the phone: a build once went to
the watch, and the failure it produced was a network timeout rather than
anything that named the watch."
  (parse-device-listing
   (run (list "/usr/bin/xcrun" "devicectl" "list" "devices"
              "--filter" "hardwareProperties.platform == 'iOS'")
        :ignore-error-status t)))

(defun install-on-device (bundle &key device)
  (let ((device (or device (first (available-devices))
                    (barf "No device available. Plug in an iPhone, unlock it, ~
                           and enable Developer Mode in Settings > Privacy & ~
                           Security."))))
    (run (list "/usr/bin/xcrun" "devicectl" "device" "install" "app"
               "--device" device
               (string-right-trim "/" (uiop:native-namestring bundle)))
         :echo-error t)
    device))

;;; ------------------------------------------------------------------
;;; .ipa
;;;
;;; An .ipa is a zip with the bundle under Payload/ and nothing else required.
;;; It is not a build product here -- it is a repackaging of one -- so it has
;;; its own entry point rather than a slot.

(defun bundle-supported-platform (bundle)
  "The bundle's CFBundleSupportedPlatforms entry, or NIL."
  (let ((plist (uiop:subpathname (uiop:ensure-directory-pathname bundle)
                                 "Info.plist")))
    (unless (probe-file plist)
      (barf "No Info.plist in ~a." (uiop:native-namestring bundle)))
    (multiple-value-bind (value err code)
        (run (list "/usr/bin/plutil" "-extract" "CFBundleSupportedPlatforms.0"
                   "raw" "-o" "-" (uiop:native-namestring plist))
             :ignore-error-status t)
      (declare (ignore err))
      (and (zerop code) (string-trim '(#\Space #\Newline) value)))))

(defun export-ipa (bundle &key output)
  "Package BUNDLE as an .ipa, returning its path.

Refuses a simulator bundle. The two look identical from the outside -- same
layout, same plist keys, an ad-hoc signature that verifies -- and the only
symptom of shipping the wrong one is a rejected upload much later, so the
platform is checked rather than assumed."
  (let* ((bundle (uiop:ensure-directory-pathname bundle))
         (platform (bundle-supported-platform bundle))
         (name (car (last (pathname-directory bundle))))
         (output (uiop:ensure-absolute-pathname
                  (or output
                      (merge-pathnames
                       (make-pathname :name (pathname-name (pathname name))
                                      :type "ipa")
                       (uiop:pathname-parent-directory-pathname bundle)))
                  #'uiop:getcwd)))
    (unless (uiop:directory-exists-p bundle)
      (barf "No bundle at ~a." (uiop:native-namestring bundle)))
    (unless (equal platform "iPhoneOS")
      (barf "~a is a ~a bundle. An .ipa must hold a device build: build with ~
             :BUNDLE-PLATFORMS (:DEVICE)."
            (uiop:native-namestring bundle) (or platform "simulator")))
    (let ((staging (sibling-directory bundle (unique-suffix "ipa"))))
      (unwind-protect
           (let ((payload (uiop:subpathname staging "Payload/")))
             (ensure-directories-exist payload)
             ;; ditto rather than a Lisp copy: the bundle is signed, and a copy
             ;; that drops an extended attribute invalidates the signature.
             (run (list "/usr/bin/ditto"
                        (string-right-trim "/" (uiop:native-namestring bundle))
                        (string-right-trim
                         "/" (uiop:native-namestring
                              (uiop:subpathname payload (format nil "~a/" name))))))
             (when (probe-file output) (delete-file output))
             (run (list "/usr/bin/ditto" "-c" "-k" "--sequesterRsrc" "--keepParent"
                        (string-right-trim "/" (uiop:native-namestring payload))
                        (uiop:native-namestring output)))
             (note "wrote ~a" (uiop:native-namestring output))
             output)
        (ignore-errors (uiop:delete-directory-tree staging :validate t))))))

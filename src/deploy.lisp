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

(defvar *console-seconds* 60
  "How long LAUNCH-IN-SIMULATOR watches a console launch before giving up.

Sixty rather than the fifteen it was, and a deadline rather than a wait: a
simulator that booted a minute ago on a GitHub runner takes longer than
fifteen seconds to launch its first app, and the fixed wait returned an
empty log three runs out of five with nothing wrong but the clock.")

(defun launch-in-simulator (bundle identifier
                            &key (device (require-booted-simulator)) console
                                 (seconds *console-seconds*) until)
  "Launch, and with CONSOLE return what the app writes to stdout and stderr.

UNTIL is a string: once the output contains it the console is released and
the output returned, so a caller waits for what it is looking for and no
longer.  Without it, or if it never appears, the output is whatever arrived
by SECONDS.

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
        (flet ((output ()
                 (if (probe-file log)
                     (ignore-errors (uiop:read-file-string log))
                     "")))
          (unwind-protect
               (let ((process (uiop:launch-program
                               (list "/usr/bin/xcrun" "simctl" "launch"
                                     "--console-pty" device identifier)
                               :output log :error-output :output)))
                 (unwind-protect
                      (loop with deadline = (+ (get-internal-real-time)
                                               (* seconds internal-time-units-per-second))
                            do (sleep 0.5)
                            until (or (>= (get-internal-real-time) deadline)
                                      (and until (search until (or (output) "")))))
                   (ignore-errors (uiop:terminate-process process :urgent t))
                   (ignore-errors (uiop:wait-process process)))
                 (or (output) ""))
            (ignore-errors (delete-file log)))))))

(defun terminate-in-simulator (identifier &key (device (require-booted-simulator)))
  (run (list "/usr/bin/xcrun" "simctl" "terminate" device identifier)
       :ignore-error-status t))

;;; ------------------------------------------------------------------
;;; the console, read back
;;;
;;; The runtime keeps everything the image prints in Documents/console.log
;;; inside the app's own container (see KEEP-CONSOLE in runtime.lisp).  On
;;; the simulator that container is a directory on the Mac; on a phone it
;;; is reached through devicectl's copy.  Either way it is the record the
;;; console attach cannot be relied on for: simctl's pty drops output, and a
;;; devicectl attach relays none at all.

(defun simulator-app-data-container (identifier &key (device (require-booted-simulator)))
  "The app's data container in the simulator, as a directory pathname."
  (uiop:ensure-directory-pathname
   (string-trim '(#\Space #\Newline)
                (run (list "/usr/bin/xcrun" "simctl" "get_app_container"
                           device identifier "data")))))

(defun simulator-console-log (identifier &key (device (require-booted-simulator)))
  "What the app has printed since its last launch, or NIL if nothing yet."
  (let ((file (uiop:subpathname (simulator-app-data-container identifier :device device)
                                "Documents/console.log")))
    (and (probe-file file) (uiop:read-file-string file))))

(defun device-console-log (identifier &key device)
  "The same file, copied off a phone; NIL if the app has not written one.

The phone must be unlocked, as for every devicectl operation."
  (let ((device (or device (first (available-devices))
                    (barf "No device available.")))
        (destination (uiop:tmpize-pathname
                      (uiop:subpathname (uiop:temporary-directory) "console.log"))))
    (unwind-protect
         (multiple-value-bind (out err code)
             (run (list "/usr/bin/xcrun" "devicectl" "device" "copy" "from"
                        "--device" device
                        "--domain-type" "appDataContainer"
                        "--domain-identifier" identifier
                        "--source" "Documents/console.log"
                        "--destination" (uiop:native-namestring destination))
                  :ignore-error-status t)
           (declare (ignore out err))
           (and (zerop code) (probe-file destination)
                (uiop:read-file-string destination)))
      (ignore-errors (delete-file destination)))))

(defun run-in-simulator (system &key (console t) until (seconds *console-seconds*))
  "Build SYSTEM if it needs it, install its simulator bundle, and launch it.

With CONSOLE, the default, returns what the app printed: the console attach
first, and when that pty dropped everything, Documents/console.log out of the
app's container, which the runtime keeps for exactly this."
  (let* ((system (asdf:find-system system))
         (identifier (app-identifier system))
         (bundle (bundle-root-for system (find-platform :simulator)))
         (device (require-booted-simulator)))
    (asdf:make system)
    (terminate-in-simulator identifier :device device)
    (let ((output (launch-in-simulator bundle identifier :device device
                                       :console console :until until
                                       :seconds seconds)))
      (if (and console (or (null output) (zerop (length (string-trim '(#\Space #\Newline) output)))))
          (simulator-console-log identifier :device device)
          output))))

(defun device-identifier-token-p (token)
  "Either spelling devicectl has used for a device's identifier: the
36-character CoreDevice id of Xcode 26 and earlier, or the 25-character
UDID -- eight hex digits, a dash, sixteen -- that Xcode 27's table shows
with `(UDID)\' after it.  devicectl accepts either on --device."
  (or (and (= (length token) 36) (char= #\- (char token 8)))
      (and (= (length token) 25) (char= #\- (char token 8))
           (every (lambda (c) (or (digit-char-p c 16) (char= c #\-))) token))))

(defun parse-device-listing (text)
  "The identifiers of the physical devices in devicectl's table that can be
reached now.

A device that can be installed to reports itself as `available (paired)\'
when it is on the network and `connected\' when it is on a cable; one that
cannot says `unavailable\', which contains the first of those words and is
why the test is not a substring search for it.  Xcode 27's table also lists
simulators, with `simulated\' in a Reality column, and those are not
devices to install to from here."
  (loop for line in (uiop:split-string text :separator '(#\Newline))
        for fields = (tokens line)
        when (and (or (member "available" fields :test #'string=)
                      (member "connected" fields :test #'string=))
                  (not (member "unavailable" fields :test #'string=))
                  (not (member "simulated" fields :test #'string=)))
          collect (find-if #'device-identifier-token-p fields)))

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

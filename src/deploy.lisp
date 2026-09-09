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

(defun available-devices ()
  "Physical devices devicectl can see, as (name . identifier)."
  (let ((out (run (list "/usr/bin/xcrun" "devicectl" "list" "devices")
                  :ignore-error-status t)))
    (loop for line in (uiop:split-string out :separator '(#\Newline))
          for fields = (tokens line)
          when (and (search "available" line) (not (search "unavailable" line)))
            collect (find-if (lambda (token)
                               (and (= (length token) 36)
                                    (char= #\- (char token 8))))
                             fields))))

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

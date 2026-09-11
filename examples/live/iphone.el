;;; iphone.el --- connect SLY to a Lisp running on an iPhone  -*- lexical-binding: t -*-
;;;
;;; The app listens on the phone's loopback interface; iproxy (from
;;; libimobiledevice: `brew install libimobiledevice') carries a local port to
;;; it over the USB cable. This starts the forwarder if it is not already
;;; running, then connects. Load with M-x load-file, then M-x sly-iphone.
;;;
;;; The cable, specifically. Xcode and devicectl reach a paired phone over
;;; Wi-Fi, and it is easy to have one that installs and launches apps while
;;; not being plugged in at all; usbmuxd does not forward to it, and the
;;; symptom is a connection reset with nothing to say why. So the phone is
;;; looked for on USB first, and its absence is reported in words.

(require 'sly)

(defvar sly-iphone-port 4005
  "The port the app's slynk listens on; the same number on both ends.")

(defun sly-iphone--usb-udid ()
  "The UDID of the first phone on the cable, or nil."
  (let ((listing (with-temp-buffer
                   (when (eq 0 (call-process "idevice_id" nil t nil "-l"))
                     (buffer-string)))))
    (and listing (car (split-string listing "\n" t)))))

(defun sly-iphone--forwarding-p ()
  (let ((process (get-process "iproxy")))
    (and process (process-live-p process))))

(defun sly-iphone ()
  "Forward `sly-iphone-port' to the phone over USB and connect SLY to it."
  (interactive)
  (unless (and (executable-find "iproxy") (executable-find "idevice_id"))
    (user-error "iproxy/idevice_id not found: brew install libimobiledevice"))
  (unless (sly-iphone--forwarding-p)
    (let ((udid (sly-iphone--usb-udid)))
      (unless udid
        (user-error "No iPhone on USB. Plug it in and unlock it; Wi-Fi pairing is not enough for iproxy"))
      (start-process "iproxy" "*iproxy*" "iproxy" "-u" udid
                     (format "%d:%d" sly-iphone-port sly-iphone-port))
      ;; iproxy binds at once; the first connection through it is what opens
      ;; the device side, so a moment is all this needs.
      (sit-for 0.5)))
  (sly-connect "localhost" sly-iphone-port))

(defun sly-iphone-stop-forwarding ()
  "Stop the USB forwarder."
  (interactive)
  (when (sly-iphone--forwarding-p)
    (delete-process "iproxy")))

(provide 'iphone)
;;; iphone.el ends here

;;;; probe.lisp -- does SI:MAKE-DYNAMIC-CALLBACK work on iOS?
;;;;
;;;; The belief was that it cannot: a libffi closure needs memory that is
;;;; both writable and executable, and iOS forbids that. But the bundled
;;;; libffi is built with FFI_EXEC_TRAMPOLINE_TABLE for exactly this
;;;; platform -- a page of prebuilt trampolines, remapped rather than
;;;; written -- and the symbol is in the shipped library. What was measured
;;;; earlier was a crash; this measures where.
;;;;
;;;; Three steps, each reported before the next is attempted, because the
;;;; one that fails is the answer:
;;;;
;;;;   1. allocate a closure         -- can libffi get a trampoline at all?
;;;;   2. call it through libffi     -- does the trampoline execute?
;;;;   3. call it from C             -- as a framework would
;;;;   4. a structure each way       -- a CGRect in, an NSRange out, from C
;;;;
;;;; Written to Documents/closure-report.txt line by line, flushed, and
;;;; shown on screen, because a phone is not a terminal.

(defpackage #:closure-probe
  (:use #:cl)
  (:export #:start))

(in-package #:closure-probe)

(defparameter *report* nil)

(defun report-path ()
  (merge-pathnames "closure-report.txt" (user-homedir-pathname)))

(defun say (control &rest arguments)
  (let ((line (apply #'format nil control arguments)))
    (format t "~&~a~%" line)
    (finish-output)
    (when *report*
      (write-line line *report*)
      (finish-output *report*))))

(defun run ()
  (say "closure probe")
  (say "ECL ~a on ~a" (lisp-implementation-version) (machine-type))
  (say "")
  (let ((entry (handler-case
                   (si::make-dynamic-callback (lambda (a b) (+ a b))
                                              'probe-add :int '(:int :int))
                 (error (e)
                   (say "1. make-dynamic-callback signalled:")
                   (say "   ~a" e)
                   nil))))
    (unless entry
      (say "")
      (say "closures cannot be allocated here; nothing further to try")
      (return-from run))
    (say "1. make-dynamic-callback => ~a" entry)
    (say "   (ffi:callback 'probe-add) => ~a" (ffi:callback 'probe-add))
    (let ((via-ffi (si:call-cfun (ffi:callback 'probe-add) :int '(:int :int) '(2 3))))
      (say "2. via si:call-cfun, (probe-add 2 3) => ~a  ~a" via-ffi
           (if (eql via-ffi 5) "correct" "WRONG")))
    (let ((via-c (closure-probe-glue:call-from-c (ffi:callback 'probe-add) 40 2)))
      (say "3. from C, (probe-add 40 2) => ~a  ~a" via-c
           (if (eql via-c 42) "correct" "WRONG")))
    ;; 4. -drawRect: takes a CGRect by value and -rangeOfString: returns an
    ;;    NSRange by value; a closure that does both is every IMP a Lisp class
    ;;    on a phone will ever need.
    (let ((rect '(:struct (:m :double) (:m :double) (:m :double) (:m :double)))
          (range '(:struct (:m :unsigned-long) (:m :unsigned-long))))
      (handler-case
          (progn
            (si::make-dynamic-callback
             (lambda (r)
               ;; The rect arrives as foreign data; the result is foreign data
               ;; libffi copies out after this returns.
               (let ((out (si::allocate-foreign-data :void 16)))
                 (si:foreign-data-set-elt out 0 :unsigned-long
                                          (round (si:foreign-data-ref-elt r 16 :double)))  ; width
                 (si:foreign-data-set-elt out 8 :unsigned-long
                                          (round (si:foreign-data-ref-elt r 24 :double)))  ; height
                 out))
             'probe-rect-to-range range (list rect))
            (let ((result (closure-probe-glue:call-with-rect-from-c
                           (ffi:callback 'probe-rect-to-range) 1d0 2d0 390d0 844d0)))
              (say "4. from C, a CGRect in and an NSRange out => ~a  ~a" result
                   (if (equal result '(390 . 844)) "correct" "WRONG"))))
        (error (e) (say "4. structures through a closure signalled: ~a" e))))
    (say "")
    (say "a libffi closure works on this device")))

(defun start ()
  (with-open-file (out (report-path)
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create)
    (let ((*report* out))
      (handler-case (run)
        (error (e) (say "; the probe itself failed: ~a" e)))))
  (closure-probe-glue:show-text
   (with-open-file (in (report-path))
     (let ((text (make-string (file-length in))))
       (subseq text 0 (read-sequence text in)))))
  (finish-output))

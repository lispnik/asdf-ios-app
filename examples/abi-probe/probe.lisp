;;;; probe.lisp -- can ECL's dynamic FFI pass a CGRect by value?
;;;;
;;;; Written when it could not. ECL's foreign type table (src/c/ffi.d,
;;;; ecl_foreign_type_table) was a closed enum of scalars ending at
;;;; ECL_FFI_VOID, so SI:CALL-CFUN had no way to say CGRect, and the only
;;;; workaround was to decompose a struct into the scalars it is made of --
;;;; which is right exactly when AAPCS64 would have put those fields where that
;;;; many separate scalars go, and silently wrong otherwise. This measures which
;;;; is which, against ground truth produced by the C compiler on the same
;;;; machine, in the same binary, calling the same functions.
;;;;
;;;; lispnik/ecl's dffi-aggregates branch, which BOOTSTRAP-ECL now builds,
;;;; gives SI:CALL-CFUN (:struct ...) designators and lets libffi classify
;;;; them, so none of this is needed there. The measurements stand as the
;;;; record of what decomposition gets wrong, which is why the workaround was
;;;; never safe to keep.

(defpackage #:abi-probe
  (:use #:cl)
  (:local-nicknames)
  (:export #:start))

(in-package #:abi-probe)

(defparameter *report* nil)

(defun report-path ()
  ;; ECLBoot points HOME at Documents; the bundle itself is read-only.
  (merge-pathnames "abi-report.txt" (user-homedir-pathname)))

(defun say (control &rest arguments)
  "Write one line, and flush it.

Flushed rather than buffered because two of these probes are expected to kill
the process. A report that only survives a clean exit would lose exactly the
results worth having."
  (let ((line (apply #'format nil control arguments)))
    (format t "~&~a~%" line)
    (finish-output)
    (when *report*
      (write-line line *report*)
      (finish-output *report*))))

;;; ------------------------------------------------------------------
;;; 1. what ECL's FFI can name

(defparameter +candidate-types+
  '(:char :unsigned-char :short :int :unsigned-int :long :unsigned-long
    :int64-t :float :double :long-double :pointer-void :cstring :object :void
    ;; ...and the things you would need for a CGRect, none of which exist:
    :struct :union :array :cgrect :cgpoint :cgsize :nsrange)
  "Names to ask SI:SIZE-OF-FOREIGN-ELT-TYPE about. The second group is the
point: an aggregate has no name in ECL's FFI, so it cannot appear in a
SI:CALL-CFUN signature at all.")

(defun known-type-p (type)
  (and (ignore-errors (si:size-of-foreign-elt-type type)) t))

(defun report-type-table ()
  (say "1. Types SI:CALL-CFUN can name")
  (say "")
  (let ((known '()) (unknown '()))
    (dolist (type +candidate-types+)
      (if (known-type-p type) (push type known) (push type unknown)))
    (say "   known:   ~{~(~a~)~^ ~}" (reverse known))
    (say "   unknown: ~{~(~a~)~^ ~}" (reverse unknown))
    (say "")
    (say "   Every known type is a scalar. ECL_FFI_VOID ends the enum in")
    (say "   src/c/ffi.d and nothing in it is an aggregate.")
    (say "")))

;;; ------------------------------------------------------------------
;;; 2. the shapes, and what AAPCS64 does with them

(defun report-shapes ()
  (destructuring-bind (hfa4 hfa6 int2 mixed) (abi-probe-glue:struct-sizes)
    (say "2. The four shapes, and how AAPCS64 passes them")
    (say "")
    (say "   hfa4  ~2d bytes  4 doubles, like CGRect         HFA: v0-v3" hfa4)
    (say "   hfa6  ~2d bytes  6 doubles, like CGAffineTransform" hfa6)
    (say "                                                  not an HFA, >16b: BY POINTER")
    (say "   int2  ~2d bytes  2 longs, like NSRange          x0-x1" int2)
    (say "   mixed ~2d bytes  long + double                  x0-x1, double in a GPR" mixed)
    (say "")))

;;; ------------------------------------------------------------------
;;; 3. the probes

(defun attempt (thunk)
  "Run THUNK, returning its value, or a string describing how it failed."
  (handler-case (funcall thunk)
    (error (e) (format nil "~a: ~a" (type-of e) e))))

(defun verdict (truth got)
  (cond ((equalp truth got) "SAME")
        (t "WRONG")))

(defun probe (name truth thunk note)
  (let ((got (attempt thunk)))
    (say "   ~a" name)
    (say "     C compiler : ~s" truth)
    (say "     call-cfun  : ~s   -> ~a" got (verdict truth got))
    (say "     ~a" note)
    (say "")
    (values got (verdict truth got))))

(defun report-returns ()
  (say "3. Returning a struct by value")
  (say "")
  (probe "make_int2 -> {7, 8}, read back as :long"
         (abi-probe-glue:truth-make-int2)
         (lambda () (si:call-cfun (abi-probe-glue:probe-address "make_int2")
                                  :long '() '()))
         "x0 holds the first field and x1 the second. :long can name x0 and there is no way to ask for x1.")

  (probe "make_hfa4 -> {1,2,3,4}, read back as :double"
         (abi-probe-glue:truth-make-hfa4)
         (lambda () (si:call-cfun (abi-probe-glue:probe-address "make_hfa4")
                                  :double '() '()))
         "The HFA comes back in v0-v3. :double reads v0. This is -[UIView bounds] exactly: origin.x and nothing else.")

  (probe "make_mixed -> {7, 8.0}, read back as :long"
         (abi-probe-glue:truth-make-mixed)
         (lambda () (si:call-cfun (abi-probe-glue:probe-address "make_mixed")
                                  :long '() '()))
         "x0 again. The double is in x1, as a bit pattern, and unreachable."))

(defun report-arguments ()
  (say "4. Passing a struct by value, decomposed into scalars")
  (say "")
  (probe "take_hfa4({1,2,3,4}) as four :double"
         (abi-probe-glue:truth-take-hfa4)
         (lambda () (si:call-cfun (abi-probe-glue:probe-address "take_hfa4")
                                  :double '(:double :double :double :double)
                                  '(1d0 2d0 3d0 4d0)))
         "WORKS -- and only by coincidence. An HFA of four doubles occupies v0-v3, which is where four separate doubles go anyway.")

  (probe "take_int2({7,8}) as two :long"
         (abi-probe-glue:truth-take-int2)
         (lambda () (si:call-cfun (abi-probe-glue:probe-address "take_int2")
                                  :long '(:long :long) '(7 8)))
         "WORKS, same coincidence in the general registers. This is why scrollRangeToVisible: is reachable and setFrame: is not.")

  (probe "take_mixed({7, 8.0}) as :long and :double"
         (abi-probe-glue:truth-take-mixed)
         (lambda () (si:call-cfun (abi-probe-glue:probe-address "take_mixed")
                                  :double '(:long :double) '(7 8d0)))
         "The struct is not an HFA, so BOTH halves travel in general registers -- the callee reads the double from x1. The Lisp call put it in v0."))

;;; ------------------------------------------------------------------
;;; 4. indirect passing, which is the dangerous pair
;;;
;;; Run one per launch, named by ABI_PROBE_CASE, and every line flushed --
;;; these two dereference a register the caller never set, so the process may
;;; not survive to write its own conclusion.
;;;
;;; It does survive, as it happens, and that is the finding rather than a
;;; reprieve. Both cases were expected to fault; neither does. What they do
;;; instead is worse, because nothing reports it.

(defun report-indirect (case-name)
  (say "5. Indirect passing -- over 16 bytes and not an HFA")
  (say "")
  (cond
    ((equal case-name "take_hfa6")
     (say "   truth: take_hfa6({1..6}) = ~s" (abi-probe-glue:truth-take-hfa6))
     (say "   Attempting six :double arguments. The callee does not want six")
     (say "   doubles: it wants a POINTER to the struct, in x0, and it will")
     (say "   read 48 bytes through whatever happens to be there.")
     (say "   >>> if this is the last line, the attempt killed the process.")
     ;; Three times, because the answer is not even stable: what gets read
     ;; is whatever the last caller left in x0, so it moves with the shape of
     ;; the surrounding code.
     (let ((results (loop repeat 3
                          collect (si:call-cfun
                                   (abi-probe-glue:probe-address "take_hfa6")
                                   :double
                                   '(:double :double :double :double :double :double)
                                   '(1d0 2d0 3d0 4d0 5d0 6d0)))))
       (say "   Returned ~{~s~^, ~}" results)
       (say "   No fault, no condition, no answer -- a plausible-looking number")
       (say "   read out of unrelated memory. The three agree because the same")
       (say "   code path leaves the same junk in x0; launch the app again and")
       (say "   the number changes.")))
    ((equal case-name "make_hfa6")
     (say "   truth: make_hfa6() = ~s" (abi-probe-glue:truth-make-hfa6))
     (say "   Attempting a :double return. The callee WRITES its 48 bytes")
     (say "   through x8, which a scalar-returning call never sets.")
     (say "   >>> if this is the last line, the attempt killed the process.")
     (let ((got (si:call-cfun (abi-probe-glue:probe-address "make_hfa6")
                              :double '() '())))
       (say "   Returned ~s, and the 48 bytes went somewhere. This is the" got)
       (say "   worst case in the file: a wild write that did not fault")
       (say "   because x8 happened to point at memory about to be discarded.")
       (say "   Surviving it is luck, and luck that is not repeatable.")))
    (t (say "   skipped; set ABI_PROBE_CASE to take_hfa6 or make_hfa6."))))

;;; ------------------------------------------------------------------

(defun run ()
  (say "ECL dynamic FFI vs. struct-by-value, on ~a ~a"
       (lisp-implementation-type) (lisp-implementation-version))
  (say "")
  (report-type-table)
  (report-shapes)
  (report-returns)
  (report-arguments)
  (let ((case-name (ext:getenv "ABI_PROBE_CASE")))
    (when (and case-name (plusp (length case-name)))
      (report-indirect case-name)))
  (say "Conclusion")
  (say "")
  (say "  Without struct designators, a struct can only be smuggled through")
  (say "  SI:CALL-CFUN as the scalars it is made of. That is right exactly")
  (say "  when the ABI puts those fields where the same number of separate")
  (say "  scalars would have gone: an HFA of at most four floats, or an integer")
  (say "  aggregate of at most 16 bytes. NSRange qualifies. CGRect qualifies as")
  (say "  an argument and NOT as a return value, which is the case that matters,")
  (say "  because -bounds and -frame are how you ask a view anything.")
  (say "")
  (say "  Not one failure above is a Lisp error. They are wrong numbers, and in")
  (say "  the indirect cases a read and a write through a register nobody set.")
  (say "  There is no handler to write and nothing to test against at run time.")
  (say "")
  (say "  A compiled trampoline has none of these problems, and not because it")
  (say "  is faster or lower-level: because the C compiler is the thing that")
  (say "  knows AAPCS64, and asking it at build time is the only way to be sure.")
  (say ""))

(defun start ()
  ;; One complete, self-contained report per launch. Appending would interleave
  ;; the runs, and each indirect case needs its own process anyway.
  (progn
    (with-open-file (out (report-path)
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((*report* out))
        (handler-case (run)
          (error (e) (say "; the probe itself failed: ~a" e))))))
  ;; On screen as well as on disk, because a phone is not a terminal.
  (abi-probe-glue:show-text
   (with-open-file (in (report-path))
     (let ((text (make-string (file-length in))))
       (subseq text 0 (read-sequence text in)))))
  (finish-output))

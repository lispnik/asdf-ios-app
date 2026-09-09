;;;; tests/framework.lisp -- just enough to avoid a dependency.
;;;;
;;;; The macOS sibling's framework, plus SKIP. This suite needs one addition it
;;;; does not: it cannot run at all off macOS, and half of it needs a
;;;; cross-compiled ECL prefix that no CI runner has. A test that cannot run
;;;; should say so and be counted, not silently pass.

(defpackage #:asdf-ios-app-tests
  (:use #:cl)
  (:local-nicknames (#:app #:asdf-ios-app))
  (:export #:run-all))

(in-package #:asdf-ios-app-tests)

(defvar *tests* '())
(defvar *failures* 0)
(defvar *checks* 0)
(defvar *skipped* 0)
(defvar *current* nil)

(defmacro deftest (name &body body)
  `(progn
     (defun ,name () ,@body)
     (setf *tests* (append (remove ',name *tests*) (list ',name)))
     ',name))

(defun skip (reason)
  "Abandon the current test, saying why. Counted separately from a pass.

A THROW rather than a condition: skipping means the rest of the test must not
run, and a handler that has to unwind for you is more machinery than this
needs."
  (throw 'skip-test reason))

(defun report-failure (form got)
  (incf *failures*)
  (format t "~&  FAIL ~a~%       ~s~%       => ~s~%" *current* form got))

(defun check (form value)
  (incf *checks*)
  (if value t (progn (report-failure form value) nil)))

(defmacro is (form)
  `(check ',form ,form))

(defmacro is= (expected form &key (test '#'equal))
  (let ((e (gensym)) (a (gensym)))
    `(let ((,e ,expected) (,a ,form))
       (incf *checks*)
       (or (funcall ,test ,e ,a)
           (progn (report-failure '(= ,expected ,form) ,a)
                  (format t "       expected ~s~%" ,e)
                  nil)))))

(defmacro signals (condition &body body)
  `(progn
     (incf *checks*)
     (handler-case (progn ,@body
                          (report-failure '(signals ,condition ,@body) :no-error)
                          nil)
       (,condition () t)
       (error (e) (report-failure '(signals ,condition ,@body) e) nil))))

(defun run-all (&key (verbose t))
  (let ((*failures* 0) (*checks* 0) (*skipped* 0))
    (dolist (name *tests*)
      (let ((*current* name))
        (when verbose (format t "~&; ~a~%" name))
        (let ((reason (catch 'skip-test
                        (handler-case (progn (funcall name) nil)
                          (error (e)
                            (incf *failures*)
                            (format t "~&  ERROR in ~a: ~a~%" name e)
                            nil)))))
          (when reason
            (incf *skipped*)
            (format t "~&  SKIP ~a~%" reason)))))
    (format t "~&~%~d check~:p, ~d failure~:p, ~d skipped~%"
            *checks* *failures* *skipped*)
    (finish-output)
    *failures*))

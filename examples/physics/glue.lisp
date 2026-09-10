;;;; glue.lisp -- the one call that needs a C compiler.
;;;;
;;;; -[UIGestureRecognizer locationInView:] returns a CGPoint by value. Two
;;;; doubles come back in v0 and v1, and SI:CALL-CFUN can name one register or
;;;; the other but has no way to say `both'. Returning a struct is the case
;;;; examples/abi-probe shows is hopeless in every shape, HFA or not.
;;;;
;;;; A :BUNDLE-TRAMPOLINES file is compiled for the target only, which is what
;;;; lets it use FFI:C-INLINE -- and then the C compiler implements AAPCS64,
;;;; which is the only reliable way to have it implemented.

(in-package #:physics-glue)

(ffi:clines "
#include <objc/runtime.h>
#include <objc/message.h>
#include <CoreGraphics/CoreGraphics.h>
")

(defun view-size (view)
  "VIEW's bounds size, as (WIDTH . HEIGHT).

-bounds returns a CGRect, so this needs the C compiler for the same reason
-locationInView: does. There is no dotted-path shortcut: sending a view the
selector \"frame.size.width\" is not reading a field, it is an unrecognised
message and an immediate crash."
  (ffi:c-inline (view) (:pointer-void) :object "{
    CGRect b = ((CGRect(*)(id,SEL))objc_msgSend)(#0, sel_registerName(\"bounds\"));
    @(return) = ecl_cons(ecl_make_double_float(b.size.width),
                         ecl_make_double_float(b.size.height));
  }" :one-liner nil))

(defun location-in-view (recognizer view)
  "Where the gesture is, in VIEW's coordinates, as (X . Y)."
  (ffi:c-inline (recognizer view) (:pointer-void :pointer-void) :object "{
    CGPoint p = ((CGPoint(*)(id,SEL,id))objc_msgSend)(
                  #0, sel_registerName(\"locationInView:\"), #1);
    @(return) = ecl_cons(ecl_make_double_float(p.x),
                         ecl_make_double_float(p.y));
  }" :one-liner nil))

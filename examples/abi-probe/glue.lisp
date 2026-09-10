;;;; glue.lisp -- the C side: four struct shapes, and the truth about them.
;;;;
;;;; Cross-compiled for the target only, which is what lets it use
;;;; FFI:C-INLINE. Everything here is plain C.
;;;;
;;;; The four shapes are chosen to cover the cases AAPCS64 treats differently,
;;;; using the Core Graphics types as the reference:
;;;;
;;;;   hfa4    4 doubles, like CGRect      -- an HFA: v0-v3
;;;;   hfa6    6 doubles, like CGAffineTransform
;;;;                                       -- NOT an HFA (max 4 members) and
;;;;                                          over 16 bytes: passed and
;;;;                                          returned INDIRECTLY, by pointer
;;;;   int2    2 longs, like NSRange       -- 16-byte integer aggregate: x0-x1
;;;;   mixed   long + double               -- 16 bytes, not an HFA: BOTH halves
;;;;                                          go in general registers, so the
;;;;                                          double travels in x1, not v0
;;;;
;;;; Each taker returns a positional checksum, so a mis-passed argument shows
;;;; up as a wrong number rather than only as a crash.

(in-package #:abi-probe-glue)

(ffi:clines "
#include <string.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <CoreGraphics/CoreGraphics.h>

typedef struct { double a, b, c, d; }          probe_hfa4;
typedef struct { double a, b, c, d, e, f; }    probe_hfa6;
typedef struct { long   a, b; }                probe_int2;
typedef struct { long a; double b; }           probe_mixed;

double probe_take_hfa4(probe_hfa4 v)
{ return v.a + 10*v.b + 100*v.c + 1000*v.d; }

double probe_take_hfa6(probe_hfa6 v)
{ return v.a + 10*v.b + 100*v.c + 1000*v.d + 10000*v.e + 100000*v.f; }

long probe_take_int2(probe_int2 v)
{ return v.a + 10*v.b; }

double probe_take_mixed(probe_mixed v)
{ return (double)v.a + 10*v.b; }

probe_hfa4  probe_make_hfa4(void)  { probe_hfa4  v = {1,2,3,4};       return v; }
probe_hfa6  probe_make_hfa6(void)  { probe_hfa6  v = {1,2,3,4,5,6};   return v; }
probe_int2  probe_make_int2(void)  { probe_int2  v = {7,8};           return v; }
probe_mixed probe_make_mixed(void) { probe_mixed v = {7,8.0};         return v; }
")

;;; ------------------------------------------------------------------
;;; addresses
;;;
;;; Taken with &, not looked up with SI:FIND-FOREIGN-SYMBOL. The point being
;;; measured is the calling convention, and a probe that also depended on
;;; dlsym would confuse a failure there with a failure here.

(defun probe-address (name)
  (ffi:c-inline (name) (:cstring) :pointer-void "{
    void *p = 0;
    if      (!strcmp(#0, \"take_hfa4\"))  p = (void *)probe_take_hfa4;
    else if (!strcmp(#0, \"take_hfa6\"))  p = (void *)probe_take_hfa6;
    else if (!strcmp(#0, \"take_int2\"))  p = (void *)probe_take_int2;
    else if (!strcmp(#0, \"take_mixed\")) p = (void *)probe_take_mixed;
    else if (!strcmp(#0, \"make_hfa4\"))  p = (void *)probe_make_hfa4;
    else if (!strcmp(#0, \"make_hfa6\"))  p = (void *)probe_make_hfa6;
    else if (!strcmp(#0, \"make_int2\"))  p = (void *)probe_make_int2;
    else if (!strcmp(#0, \"make_mixed\")) p = (void *)probe_make_mixed;
    @(return) = p;
  }" :one-liner nil))

(defun struct-sizes ()
  "Sizes in bytes. Over 16 and not an HFA is the line AAPCS64 draws."
  (ffi:c-inline () () :object "{
    @(return) = cl_list(4,
      ecl_make_fixnum(sizeof(probe_hfa4)),
      ecl_make_fixnum(sizeof(probe_hfa6)),
      ecl_make_fixnum(sizeof(probe_int2)),
      ecl_make_fixnum(sizeof(probe_mixed)));
  }" :one-liner nil))

;;; ------------------------------------------------------------------
;;; ground truth
;;;
;;; The same calls, made by the C compiler, which knows the ABI. Whatever
;;; these return is the right answer by construction.

(defun truth-take-hfa4 ()
  (ffi:c-inline () () :double
    "{ probe_hfa4 v = {1,2,3,4}; @(return) = probe_take_hfa4(v); }" :one-liner nil))

(defun truth-take-hfa6 ()
  (ffi:c-inline () () :double
    "{ probe_hfa6 v = {1,2,3,4,5,6}; @(return) = probe_take_hfa6(v); }" :one-liner nil))

(defun truth-take-int2 ()
  (ffi:c-inline () () :long
    "{ probe_int2 v = {7,8}; @(return) = probe_take_int2(v); }" :one-liner nil))

(defun truth-take-mixed ()
  (ffi:c-inline () () :double
    "{ probe_mixed v = {7,8.0}; @(return) = probe_take_mixed(v); }" :one-liner nil))

(defun truth-make-hfa4 ()
  (ffi:c-inline () () :object "{
    probe_hfa4 v = probe_make_hfa4();
    @(return) = cl_list(4, ecl_make_double_float(v.a), ecl_make_double_float(v.b),
                           ecl_make_double_float(v.c), ecl_make_double_float(v.d));
  }" :one-liner nil))

(defun truth-make-hfa6 ()
  (ffi:c-inline () () :object "{
    probe_hfa6 v = probe_make_hfa6();
    @(return) = cl_list(6, ecl_make_double_float(v.a), ecl_make_double_float(v.b),
                           ecl_make_double_float(v.c), ecl_make_double_float(v.d),
                           ecl_make_double_float(v.e), ecl_make_double_float(v.f));
  }" :one-liner nil))

(defun truth-make-int2 ()
  (ffi:c-inline () () :object "{
    probe_int2 v = probe_make_int2();
    @(return) = cl_list(2, ecl_make_fixnum(v.a), ecl_make_fixnum(v.b));
  }" :one-liner nil))

(defun truth-make-mixed ()
  (ffi:c-inline () () :object "{
    probe_mixed v = probe_make_mixed();
    @(return) = cl_list(2, ecl_make_fixnum(v.a), ecl_make_double_float(v.b));
  }" :one-liner nil))

;;; ------------------------------------------------------------------
;;; somewhere to put the answer
;;;
;;; This helper is itself an instance of what is being measured: it reads a
;;; CGRect out of -bounds and passes one to -initWithFrame:, which is exactly
;;; what the Lisp side below cannot do.

(defun show-text (string)
  (ffi:c-inline (string) (:cstring) :int "{
    static id tv = 0;
    id app = ((id(*)(Class,SEL))objc_msgSend)(objc_getClass(\"UIApplication\"),
                                              sel_registerName(\"sharedApplication\"));
    id win = ((id(*)(id,SEL))objc_msgSend)(app, sel_registerName(\"keyWindow\"));
    id vc  = ((id(*)(id,SEL))objc_msgSend)(win, sel_registerName(\"rootViewController\"));
    id view = ((id(*)(id,SEL))objc_msgSend)(vc, sel_registerName(\"view\"));
    if (!tv) {
      CGRect b = ((CGRect(*)(id,SEL))objc_msgSend)(view, sel_registerName(\"bounds\"));
      b.origin.x += 6; b.origin.y += 54;
      b.size.width -= 12; b.size.height -= 66;
      tv = ((id(*)(Class,SEL))objc_msgSend)(objc_getClass(\"UITextView\"),
                                            sel_registerName(\"alloc\"));
      tv = ((id(*)(id,SEL,CGRect))objc_msgSend)(tv, sel_registerName(\"initWithFrame:\"), b);
      ((void(*)(id,SEL,BOOL))objc_msgSend)(tv, sel_registerName(\"setEditable:\"), 0);
      id font = ((id(*)(Class,SEL,CGFloat,CGFloat))objc_msgSend)(
                  objc_getClass(\"UIFont\"),
                  sel_registerName(\"monospacedSystemFontOfSize:weight:\"), 9.0, 0.0);
      ((void(*)(id,SEL,id))objc_msgSend)(tv, sel_registerName(\"setFont:\"), font);
      ((void(*)(id,SEL,id))objc_msgSend)(view, sel_registerName(\"addSubview:\"), tv);
    }
    id s = ((id(*)(Class,SEL,const char *))objc_msgSend)(
             objc_getClass(\"NSString\"),
             sel_registerName(\"stringWithUTF8String:\"), #0);
    ((void(*)(id,SEL,id))objc_msgSend)(tv, sel_registerName(\"setText:\"), s);
    @(return) = 1;
  }" :one-liner nil))

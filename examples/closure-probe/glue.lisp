;;;; glue.lisp -- the C side. Cross-compiled for the target only.

(in-package #:closure-probe-glue)

(ffi:clines "
#include <objc/runtime.h>
#include <objc/message.h>
#include <CoreGraphics/CoreGraphics.h>
")

(defun call-from-c (pointer a b)
  "Call POINTER as int (*)(int, int) from C. What a framework would do with
a callback, as opposed to what libffi does when SI:CALL-CFUN invokes it."
  (ffi:c-inline (pointer a b) (:pointer-void :int :int) :int
                "((int (*)(int, int))#0)(#1, #2)" :one-liner t))

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
                  sel_registerName(\"monospacedSystemFontOfSize:weight:\"), 11.0, 0.0);
      ((void(*)(id,SEL,id))objc_msgSend)(tv, sel_registerName(\"setFont:\"), font);
      ((void(*)(id,SEL,id))objc_msgSend)(view, sel_registerName(\"addSubview:\"), tv);
    }
    id s = ((id(*)(Class,SEL,const char *))objc_msgSend)(
             objc_getClass(\"NSString\"),
             sel_registerName(\"stringWithUTF8String:\"), #0);
    ((void(*)(id,SEL,id))objc_msgSend)(tv, sel_registerName(\"setText:\"), s);
    @(return) = 1;
  }" :one-liner nil))

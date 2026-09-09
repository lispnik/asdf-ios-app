;;;; glue.lisp -- the C side, cross-compiled for the target only.
;;;;
;;;; Everything here is plain C. Not a stylistic choice: an ordinary source
;;;; file is compiled natively too, so the cross compiler has its macros, and
;;;; Objective-C does not survive that pass -- ECL drives it as gcc against the
;;;; macOS SDK with no -ObjC. A :BUNDLE-TRAMPOLINES file skips the native pass
;;;; entirely, which is the only reason FFI:C-INLINE can be used at all.
;;;;
;;;; A trampoline is a cast of objc_msgSend to one concrete prototype, and an
;;;; IMP is an ordinary C function. Both are C, and having the C compiler do it
;;;; is what makes CGRect-by-value work where SI:CALL-CFUN cannot express it.

;;; The package itself is declared in glue-package.lisp, an ordinary component,
;;; because this file is never compiled on the host and ordinary sources are.

(in-package #:attractor-glue)

(ffi:clines "
#include <objc/runtime.h>
#include <objc/message.h>
#include <CoreGraphics/CoreGraphics.h>

/* Declared rather than imported: UIGraphicsGetCurrentContext lives in a UIKit
   header, and UIKit headers are Objective-C. The symbol is C and is linked in
   regardless, so a declaration is all that is needed. */
extern CGContextRef UIGraphicsGetCurrentContext(void);

/* The IMP for -[AttractorView drawRect:]. It receives a CGRect BY VALUE, which
   is the whole point: nothing in ECL's FFI type list can name that, so this
   method could not exist without a C compiler at build time. */
static void attractor_draw_rect(id self, SEL cmd, CGRect rect)
{
  cl_object fn = ecl_make_symbol(\"DRAW\", \"ATTRACTOR\");
  if (fn != ECL_NIL && (fn->symbol.gfdef != OBJNULL)) {
    /* si_safe_eval-style safety matters here: a Lisp condition unwinding
       through UIKit's frame would corrupt it. cl_funcall does not offer that,
       so the Lisp side is responsible for not signalling. */
    cl_funcall(3, fn,
               ecl_make_double_float(rect.size.width),
               ecl_make_double_float(rect.size.height));
  }
}
")

(defun install-view-class (encoding)
  "Create AttractorView at runtime and give it a Lisp drawRect:.

ENCODING is passed in rather than written here because no @ may appear in a
C-INLINE body at all -- ECL reads it as the start of its own @(return) syntax,
and an Objective-C type encoding is full of them. The encoding says: returns
void, takes self, _cmd and a CGRect. Getting it wrong does not fail here, it
makes UIKit hand the method garbage."
  (ffi:c-inline (encoding) (:cstring) :int "{
    if (objc_getClass(\"AttractorView\")) { @(return) = 1; }
    else {
      Class super = objc_getClass(\"UIView\");
      Class c = objc_allocateClassPair(super, \"AttractorView\", 0);
      class_addMethod(c, sel_registerName(\"drawRect:\"),
                      (IMP)attractor_draw_rect, #0);
      objc_registerClassPair(c);
      @(return) = 2;
    }
  }" :one-liner nil))

(defun make-view ()
  "[[AttractorView alloc] initWithFrame: UIScreen.mainScreen.bounds]"
  (ffi:c-inline () () :pointer-void "{
    Class screen = objc_getClass(\"UIScreen\");
    id main = ((id(*)(Class,SEL))objc_msgSend)(screen, sel_registerName(\"mainScreen\"));
    CGRect b = ((CGRect(*)(id,SEL))objc_msgSend)(main, sel_registerName(\"bounds\"));
    Class v = objc_getClass(\"AttractorView\");
    id view = ((id(*)(Class,SEL))objc_msgSend)(v, sel_registerName(\"alloc\"));
    view = ((id(*)(id,SEL,CGRect))objc_msgSend)(view, sel_registerName(\"initWithFrame:\"), b);
    @(return) = view;
  }" :one-liner nil))

(defun view-bounds (view)
  "The view's size, as two values. -bounds returns a CGRect by value."
  (ffi:c-inline (view) (:pointer-void) :object "{
    CGRect b = ((CGRect(*)(id,SEL))objc_msgSend)(#0, sel_registerName(\"bounds\"));
    @(return) = ecl_cons(ecl_make_double_float(b.size.width),
                         ecl_make_double_float(b.size.height));
  }" :one-liner nil))

(defun set-root-view (view)
  "Give the key window a view controller whose view is VIEW."
  (ffi:c-inline (view) (:pointer-void) :int "{
    Class appc = objc_getClass(\"UIApplication\");
    id app = ((id(*)(Class,SEL))objc_msgSend)(appc, sel_registerName(\"sharedApplication\"));
    id windows = ((id(*)(id,SEL))objc_msgSend)(app, sel_registerName(\"windows\"));
    long n = ((long(*)(id,SEL))objc_msgSend)(windows, sel_registerName(\"count\"));
    if (n == 0) { @(return) = 0; }
    else {
      id window = ((id(*)(id,SEL,long))objc_msgSend)(windows,
                     sel_registerName(\"objectAtIndex:\"), 0);
      id vc = ((id(*)(id,SEL))objc_msgSend)(
                ((id(*)(Class,SEL))objc_msgSend)(objc_getClass(\"UIViewController\"),
                                                 sel_registerName(\"alloc\")),
                sel_registerName(\"init\"));
      ((void(*)(id,SEL,id))objc_msgSend)(vc, sel_registerName(\"setView:\"), #0);
      ((void(*)(id,SEL,id))objc_msgSend)(window,
                                         sel_registerName(\"setRootViewController:\"), vc);
      @(return) = 1;
    }
  }" :one-liner nil))

(defun draw-points (points count red green blue alpha size)
  "Draw COUNT x,y pairs from POINTS, a (simple-array double-float (*)).

The loop is C because two million CGContextFillRect calls from Lisp would not
be interactive; the POINTS themselves come from Lisp, which is where the
mathematics lives and where it stays editable."
  (ffi:c-inline (points count red green blue alpha size)
                (:object :long :double :double :double :double :double) :int "{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) { @(return) = 0; }
    else {
      double *p = (double *)(#0)->array.self.df;
      CGContextSetRGBFillColor(ctx, #2, #3, #4, #5);
      for (long i = 0; i < #1; i++) {
        CGContextFillRect(ctx, CGRectMake(p[2*i], p[2*i+1], #6, #6));
      }
      @(return) = 1;
    }
  }" :one-liner nil))

;;; ------------------------------------------------------------------
;;; gestures
;;;
;;; UIGestureRecognizer uses target/action, so LispTarget carries it: the
;;; recognizer messages -fire:, which evaluates a Lisp form. The recognizer
;;; itself is stashed on the Lisp side when it is made, so the handler reads
;;; its state from there and never needs the sender -- which is what keeps
;;; LispTarget a one-line contract.

(defun add-recognizer (view class-name form)
  "Attach a CLASS-NAME recognizer to VIEW whose action evaluates FORM.

Returns the recognizer, so Lisp can ask it for its translation or scale later.
LispTarget parks its instances in a class-level set: UIKit holds a target
weakly, and a Lisp variable holding a raw address is not something ARC can see."
  (ffi:c-inline (class-name form) (:cstring :cstring) :pointer-void "{
    id string = ((id(*)(Class,SEL,const char *))objc_msgSend)(
                  objc_getClass(\"NSString\"),
                  sel_registerName(\"stringWithUTF8String:\"), #1);
    id target = ((id(*)(Class,SEL,id))objc_msgSend)(
                  objc_getClass(\"LispTarget\"),
                  sel_registerName(\"targetWithForm:\"), string);
    id r = ((id(*)(Class,SEL))objc_msgSend)(objc_getClass(#0),
                                            sel_registerName(\"alloc\"));
    r = ((id(*)(id,SEL,id,SEL))objc_msgSend)(r,
          sel_registerName(\"initWithTarget:action:\"), target,
          sel_registerName(\"fire:\"));
    @(return) = r;
  }" :one-liner nil))

(defun attach-recognizer (view recognizer)
  (ffi:c-inline (view recognizer) (:pointer-void :pointer-void) :int "{
    ((void(*)(id,SEL,id))objc_msgSend)(#0,
      sel_registerName(\"addGestureRecognizer:\"), #1);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(#0,
      sel_registerName(\"setUserInteractionEnabled:\"), 1);
    @(return) = 1;
  }" :one-liner nil))

(defun pan-translation (recognizer view)
  "The pan's translation since it was last reset, as (dx . dy).

-translationInView: returns a CGPoint by value -- two doubles in two floating
point registers, which is a different ABI path again from CGRect's, and another
thing no Lisp-side FFI on ECL can name."
  (ffi:c-inline (recognizer view) (:pointer-void :pointer-void) :object "{
    CGPoint p = ((CGPoint(*)(id,SEL,id))objc_msgSend)(#0,
                  sel_registerName(\"translationInView:\"), #1);
    @(return) = ecl_cons(ecl_make_double_float(p.x),
                         ecl_make_double_float(p.y));
  }" :one-liner nil))

(defun reset-pan-translation (recognizer view)
  "Zero the translation, so each callback reports a delta rather than a total."
  (ffi:c-inline (recognizer view) (:pointer-void :pointer-void) :int "{
    CGPoint zero = CGPointMake(0.0, 0.0);
    ((void(*)(id,SEL,CGPoint,id))objc_msgSend)(#0,
      sel_registerName(\"setTranslation:inView:\"), zero, #1);
    @(return) = 1;
  }" :one-liner nil))

(defun pinch-scale (recognizer)
  (ffi:c-inline (recognizer) (:pointer-void) :double "{
    @(return) = ((CGFloat(*)(id,SEL))objc_msgSend)(#0, sel_registerName(\"scale\"));
  }" :one-liner nil))

(defun reset-pinch-scale (recognizer)
  (ffi:c-inline (recognizer) (:pointer-void) :int "{
    ((void(*)(id,SEL,CGFloat))objc_msgSend)(#0, sel_registerName(\"setScale:\"), 1.0);
    @(return) = 1;
  }" :one-liner nil))

(defun set-needs-display (view)
  "Ask UIKit to call drawRect: again on the next frame."
  (ffi:c-inline (view) (:pointer-void) :int "{
    ((void(*)(id,SEL))objc_msgSend)(#0, sel_registerName(\"setNeedsDisplay\"));
    @(return) = 1;
  }" :one-liner nil))

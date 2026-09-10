;;;; objc-lite.lisp -- Objective-C from Lisp, with no C compiler involved.
;;;;
;;;; Everything here goes through SI:CALL-CFUN, which means it works in
;;;; compiled code and interpreted code alike -- including at a remote REPL.
;;;; That is the whole appeal, and it comes with one hard boundary: ECL's
;;;; foreign type table holds scalars only, so no message here may take or
;;;; return a struct BY VALUE. -bounds, -frame, -setFrame:, -center are all
;;;; out of reach; examples/abi-probe measures exactly why, and
;;;; :BUNDLE-TRAMPOLINES is the way round it.
;;;;
;;;; In practice that boundary costs less than it sounds, because Auto Layout
;;;; takes its constants as plain CGFloats. A whole interface can be built
;;;; without ever naming a rectangle.

(in-package #:objc-lite)

(defun foreign-function (name)
  (si:find-foreign-symbol name :default :pointer-void 0))

;;; Looked up once. FIND-FOREIGN-SYMBOL goes through dlsym, which is not free,
;;; and objc_msgSend is on every path in this file.
(defvar *msg-send*        (foreign-function "objc_msgSend"))
(defvar *get-class*       (foreign-function "objc_getClass"))
(defvar *register-sel*    (foreign-function "sel_registerName"))
(defvar *allocate-class*  (foreign-function "objc_allocateClassPair"))
(defvar *add-method*      (foreign-function "class_addMethod"))
(defvar *register-class*  (foreign-function "objc_registerClassPair"))
(defvar *object-class*    (foreign-function "object_getClass"))
(defvar *class-name*      (foreign-function "class_getName"))

(defvar *foreign* (make-hash-table :test #'equal))

(defun foreign (name)
  "The address of the C function NAME, looked up once and remembered.

Looked up *lazily*, which matters more than it looks. A DEFVAR whose initialiser
calls SI:FIND-FOREIGN-SYMBOL runs at load time -- including during the child's
native pass, on the Mac, where the application's frameworks are not linked. A
CoreGraphics symbol resolved that way fails the build before it ever reaches
the phone:

    Cross-compilation failed: FIND-FOREIGN-SYMBOL: Could not load foreign
    symbol \"CGPathCreateMutable\" from module :DEFAULT

The msgSend lookups above get away with being eager only because libobjc is in
every macOS process. Anything from a framework you named in :BUNDLE-FRAMEWORKS
should come through here."
  (or (gethash name *foreign*)
      (setf (gethash name *foreign*)
            (si:find-foreign-symbol name :default :pointer-void 0))))

(defvar *classes* (make-hash-table :test #'equal))
(defvar *selectors* (make-hash-table :test #'equal))

(defun cls (name)
  "The Objective-C class called NAME. Memoised: the lookup is a hash of a
string either way, and doing it in Lisp keeps it out of dlsym's."
  (or (gethash name *classes*)
      (setf (gethash name *classes*)
            (si:call-cfun *get-class* :pointer-void '(:cstring) (list name)))))

(defun sel (name)
  "The selector called NAME. Memoised for the same reason."
  (or (gethash name *selectors*)
      (setf (gethash name *selectors*)
            (si:call-cfun *register-sel* :pointer-void '(:cstring) (list name)))))

;;; ------------------------------------------------------------------
;;; sending

(defun argument-type (value)
  "The foreign type to send VALUE as.

Integers travel as :LONG rather than :INT because that is what NSInteger is,
and because a BOOL passed in a 64-bit register is still read from its low byte
-- so one rule covers both. A float is always :DOUBLE: CGFloat is a double on
every 64-bit Apple platform, and passing a single where a double is expected
puts it in the right register with the wrong bits."
  (etypecase value
    (string  :cstring)
    (integer :long)
    (float   :double)
    (t       :pointer-void)))

(defvar *null* (ffi:make-null-pointer :pointer-void)
  "nil, as Objective-C spells it. Handy for the many methods whose last
argument is an optional object -- -loadHTMLString:baseURL: among them.")

(defun coerce-argument (value)
  (cond ((null value) *null*)
        ((floatp value) (float value 1d0))
        (t value)))

(defun %send (object selector arguments return-type)
  (let ((arguments (mapcar #'coerce-argument arguments)))
    (si:call-cfun *msg-send* return-type
                  (list* :pointer-void :pointer-void
                         (mapcar #'argument-type arguments))
                  (list* object (sel selector) arguments))))

(defun send (object selector &rest arguments)
  "Send SELECTOR to OBJECT and return the result as a pointer."
  (%send object selector arguments :pointer-void))

(defun send-long (object selector &rest arguments)
  (%send object selector arguments :long))

(defun send-double (object selector &rest arguments)
  (%send object selector arguments :double))

(defun send-bool (object selector &rest arguments)
  ;; A BOOL is a signed char in the low byte of the return register; the rest
  ;; of that register is not guaranteed to be anything.
  (not (zerop (logand 255 (%send object selector arguments :long)))))

(defun send-string (object selector &rest arguments)
  "Send SELECTOR and read the result as a C string.

COPY-SEQ is load-bearing. :CSTRING hands back a Lisp string that aliases the
foreign buffer, so two of these in a row can quietly become the same text."
  (let ((result (%send object selector arguments :cstring)))
    (and result (copy-seq result))))

;;; ------------------------------------------------------------------
;;; strings

(defun utf-8-bytes (string)
  "STRING's UTF-8 encoding, as a BASE-STRING of one character per octet.

:CSTRING hands the value to ECL's NULL-TERMINATED-BASE-STRING, which refuses
anything outside BASE-CHAR -- so passing a Lisp string containing a theta or an
em dash straight through fails with

    Cannot coerce string ... to a base-string

rather than arriving mangled. Encoding first turns every character into octets
that are base-chars by construction, and -stringWithUTF8String: is expecting
exactly those octets at the other end."
  (map 'base-string #'code-char
       (ext:string-to-octets string :external-format :utf-8)))

(defun nsstr (string)
  (si:call-cfun *msg-send* :pointer-void
                '(:pointer-void :pointer-void :cstring)
                (list (cls "NSString") (sel "stringWithUTF8String:")
                      (utf-8-bytes string))))

(defun lisp-string (nsstring)
  "NSSTRING's contents. The mirror of NSSTR: -UTF8String hands back octets, and
reading them as characters would turn any non-ASCII into mojibake."
  (if (or (null nsstring) (si:null-pointer-p nsstring))
      ""
      (let ((octets (send-string nsstring "UTF8String")))
        (if (null octets)
            ""
            (or (ignore-errors
                 (ext:octets-to-string
                  (map '(vector (unsigned-byte 8)) #'char-code octets)
                  :external-format :utf-8))
                octets)))))

;;; ------------------------------------------------------------------
;;; the usual objects

(defun alloc-init (class-name)
  (send (send (cls class-name) "alloc") "init"))

(defun new (class-name)
  "ALLOC-INIT, with autoresizing translation off -- which is what you want for
every view you are about to constrain, and forgetting it is the single most
common way to get an invisible interface."
  (let ((view (alloc-init class-name)))
    (send view "setTranslatesAutoresizingMaskIntoConstraints:" 0)
    view))

(defun system-button (title)
  "A UIButton of the system type, carrying TITLE.

Not (NEW \"UIButton\"): -init gives the *custom* type, whose title colour is
white. On a white background that is indistinguishable from a button that
failed to appear, and you can lose a while to it."
  (let ((button (send (cls "UIButton") "buttonWithType:" 1)))
    (send button "setTranslatesAutoresizingMaskIntoConstraints:" 0)
    (send button "setTitle:forState:" (nsstr title) 0)
    button))

(defun on-tap (control form)
  "Evaluate FORM, a string, when CONTROL is tapped.

LispTarget ships with asdf-ios-app and covers everything in UIKit that uses
target/action. RETAIN is not optional: UIKit holds a target weakly, and a Lisp
variable holding a raw address is not something ARC can see."
  (send control "addTarget:action:forControlEvents:"
        (retain (send (cls "LispTarget") "targetWithForm:" (nsstr form)))
        (sel "fire:")
        64)                             ; UIControlEventTouchUpInside
  control)

(defun key-window ()
  (send (send (cls "UIApplication") "sharedApplication") "keyWindow"))

(defun root-controller ()
  (send (key-window) "rootViewController"))

(defun root-view ()
  (send (root-controller) "view"))

(defun color (red green blue &optional (alpha 1d0))
  (send (cls "UIColor") "colorWithRed:green:blue:alpha:"
        (float red 1d0) (float green 1d0) (float blue 1d0) (float alpha 1d0)))

(defun system-color (name)
  "A named UIColor, e.g. \"systemBackground\" or \"label\"."
  (send (cls "UIColor") (concatenate 'string name "Color")))

(defun font (size &optional (weight 0d0))
  (send (cls "UIFont") "systemFontOfSize:weight:" (float size 1d0) (float weight 1d0)))

(defun mono-font (size &optional (weight 0d0))
  (send (cls "UIFont") "monospacedSystemFontOfSize:weight:"
        (float size 1d0) (float weight 1d0)))

;;; ------------------------------------------------------------------
;;; auto layout
;;;
;;; Constraints are the reason a struct-free bridge is enough to build a real
;;; interface: an anchor is an object and a constant is a CGFloat, so nothing
;;; on this path is an aggregate.

(defun anchor (view name)
  (send view name))

(defun pin (view name other other-name &optional (constant 0d0))
  "VIEW's NAME anchor equals OTHER's OTHER-NAME anchor, plus CONSTANT.

Both anchor names, always, even when they are the same. A shorter version that
took one name and used it for both looked tidier and was a trap: the two
arities read almost identically at the call site, and getting them confused is
a PROGRAM-ERROR at run time -- which on iOS means an entry point that dies
before anything reaches the screen."
  (send (send (anchor view name) "constraintEqualToAnchor:constant:"
              (anchor other other-name) (float constant 1d0))
        "setActive:" 1))

(defun fix (view name constant)
  "VIEW's NAME dimension anchor equals CONSTANT."
  (send (send (anchor view name) "constraintEqualToConstant:" (float constant 1d0))
        "setActive:" 1))

;;; ------------------------------------------------------------------
;;; defining an Objective-C class whose methods are Lisp
;;;
;;; The class is created at run time and its methods are ordinary C functions
;;; emitted by FFI:DEFCALLBACK. That works because the compiler handles
;;; DEFCALLBACK itself -- see c1-defcallback in src/cmp/cmppass1-ffi.lsp -- and
;;; emits a real function rather than allocating a libffi closure. The closure
;;; path, which is what an interpreted DEFCALLBACK takes, kills the process on
;;; iOS.
;;;
;;; The same mechanism draws the boundary: c1-defcallback resolves every
;;; argument and the return through FOREIGN-ELT-TYPE-CODE, so a method that
;;; takes or returns a struct cannot be written this way. -drawRect: is the
;;; one everybody wants and the one that needs a trampoline.

(defun make-class (name superclass-name)
  (si:call-cfun *allocate-class* :pointer-void
                '(:pointer-void :cstring :long)
                (list (cls superclass-name) name 0)))

(defun add-objc-method (class selector-name imp type-encoding)
  "Give CLASS a method. IMP comes from (FFI:CALLBACK 'name).

TYPE-ENCODING describes the method to the runtime: return type first, then
self and _cmd, then the arguments -- \"l@:@\" is `returns NSInteger, takes an
object'. Getting it wrong is not an error; it makes the runtime hand the
method garbage."
  (si:call-cfun *add-method* :long
                '(:pointer-void :pointer-void :pointer-void :cstring)
                (list class (sel selector-name) imp type-encoding)))

(defun register-class (class)
  (si:call-cfun *register-class* :void '(:pointer-void) (list class))
  class)

(defun define-class (name superclass-name methods)
  "Create NAME under SUPERCLASS-NAME with METHODS, or return it if it exists.

METHODS is a list of (selector-string imp type-encoding). Idempotent, because
a REPL session will evaluate this more than once and objc_allocateClassPair
returns null for a name already taken."
  (let ((existing (cls name)))
    (if (and existing (not (si:null-pointer-p existing)))
        existing
        (let ((class (make-class name superclass-name)))
          (loop for (selector imp encoding) in methods
                do (add-objc-method class selector imp encoding))
          (register-class class)
          ;; The memo was populated with the null from the failed lookup above.
          (remhash name *classes*)
          (cls name)))))

;;; ------------------------------------------------------------------
;;; lifetime
;;;
;;; A Lisp variable holding a raw address is invisible to ARC. Anything the
;;; Objective-C side only holds weakly -- a delegate, a target, a data source
;;; -- has to be kept alive from somewhere it can see.

(defvar *retained* '()
  "Objects held for the lifetime of the image. A prototype may leak; a real
application would want to let go of these.")

(defun retain (object)
  (send object "retain")
  (push object *retained*)
  object)

(defun release-into-the-void (object)
  (setf *retained* (remove object *retained*))
  object)

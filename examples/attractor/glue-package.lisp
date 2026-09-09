;;;; glue-package.lisp -- the package the trampolines live in.
;;;;
;;;; Separate from glue.lisp, and it has to be. A :BUNDLE-TRAMPOLINES file is
;;;; compiled for the target only, so its DEFPACKAGE never runs on the host --
;;;; and ordinary sources ARE compiled on the host, where reading
;;;; ATTRACTOR-GLUE:DRAW-POINTS would then fail with "no package".
;;;;
;;;; So the package is declared in an ordinary component, which is compiled and
;;;; loaded normally, and the functions are defined by the trampoline file
;;;; afterwards. At run time the trampoline module initialises last and its
;;;; definitions are the ones that stand.

(defpackage #:attractor-glue
  (:use #:cl)
  (:export #:install-view-class #:make-view #:set-root-view #:draw-points
           #:view-bounds
           #:add-recognizer #:attach-recognizer #:set-needs-display
           #:pan-translation #:reset-pan-translation
           #:pinch-scale #:reset-pinch-scale))

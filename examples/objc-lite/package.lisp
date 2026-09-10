(defpackage #:objc-lite
  (:use #:cl)
  (:nicknames #:oc)
  (:export
   ;; naming
   #:cls #:sel #:class-name-of #:*null* #:foreign
   ;; sending
   #:send #:send-long #:send-double #:send-string #:send-bool
   ;; strings
   #:nsstr #:lisp-string #:utf-8-bytes
   ;; making things
   #:new #:alloc-init #:system-button #:on-tap #:key-window #:root-view #:root-controller
   #:color #:system-color #:font #:mono-font
   ;; defining an Objective-C class whose methods are Lisp
   #:make-class #:add-objc-method #:register-class #:define-class
   ;; auto layout
   #:pin #:fix #:anchor
   ;; keeping Lisp-side objects alive
   #:retain #:release-into-the-void))

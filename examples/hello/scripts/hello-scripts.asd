;;;; hello-scripts.asd -- the interpreted half of the example.
;;;;
;;;; Shipped as source rather than compiled in, so it can be edited and
;;;; reloaded without rebuilding the application.

(defsystem "hello-scripts"
  :description "Shipped as source: edit it without a rebuild."
  :serial t
  :components ((:file "greeting")))

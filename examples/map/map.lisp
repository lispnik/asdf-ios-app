;;;; map.lisp -- a map, a location, and a route computed in Lisp.
;;;;
;;;; CoreLocation delivers the phone's position to a delegate; MapKit shows
;;;; a map and asks its delegate how to draw each overlay. Both delegates
;;;; are Lisp classes here. The route is Lisp's: a figure of eight walked
;;;; around the location, its coordinates written into a C array for
;;;; MKPolyline. And the region the map is told to show is
;;;; MKCoordinateRegion, a structure of two structures, handed over as a
;;;; vector of two vectors -- the objc bridge writes any declared
;;;; structure from a sequence, nested ones included.

(defpackage #:map-ios
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:*location*))

(in-package #:map-ios)

(defvar *map* nil)
(defvar *status* nil)
(defvar *location* nil "(latitude . longitude), once CoreLocation has said.")
(defvar *manager* nil)

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "MAP: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

;;; ------------------------------------------------------------------
;;; the structures MapKit speaks

(objc:define-objc-struct (coordinate (:foreign-name "CLLocationCoordinate2D"))
  (:latitude :double)
  (:longitude :double))

(objc:define-objc-struct (span (:foreign-name "MKCoordinateSpan"))
  (:latitude-delta :double)
  (:longitude-delta :double))

(objc:define-objc-struct (region (:foreign-name "MKCoordinateRegion"))
  (:center (:struct coordinate))
  (:span (:struct span)))

;;; ------------------------------------------------------------------
;;; the route, and the overlay

(defun figure-of-eight (latitude longitude &key (points 240) (size 0.004))
  "A lemniscate around the location, as (lat . lon) pairs."
  (loop for i below points
        for angle = (* 2 pi (/ i points))
        for k = (/ (* size (cos angle)) (+ 1 (expt (sin angle) 2)))
        collect (cons (+ latitude (* k (sin angle)))
                      (+ longitude (* 1.4 k)))))

(defvar *coordinates* nil "The C array behind the polyline, kept while it is shown.")

(defun show-route ()
  (destructuring-bind (latitude . longitude) *location*
    (let* ((route (figure-of-eight latitude longitude))
           (count (length route)))
      (when *coordinates* (cffi:foreign-free *coordinates*))
      (setf *coordinates* (cffi:foreign-alloc :double :count (* 2 count)))
      (loop for (lat . lon) in route for i from 0
            do (setf (cffi:mem-aref *coordinates* :double (* 2 i)) (float lat 1d0)
                     (cffi:mem-aref *coordinates* :double (1+ (* 2 i))) (float lon 1d0)))
      (objc:invoke *map* "removeOverlays:" (objc:invoke *map* "overlays"))
      (objc:invoke *map* "addOverlay:"
                   (objc:invoke "MKPolyline" "polylineWithCoordinates:count:" *coordinates* count))
      ;; A pin at the location, and the region: two nested structures as
      ;; two nested vectors.
      (objc:invoke *map* "removeAnnotations:" (objc:invoke *map* "annotations"))
      (let ((pin (objc:alloc-init-object "MKPointAnnotation")))
        (objc:invoke pin "setCoordinate:" (vector latitude longitude))
        (objc:invoke pin "setTitle:" "Here, says CoreLocation")
        (objc:invoke *map* "addAnnotation:" pin))
      (objc:invoke *map* "setRegion:animated:"
                   (vector (vector latitude longitude) (vector 0.012d0 0.012d0)) t)
      (say "route of ~d points around ~,4f, ~,4f" count latitude longitude))))

;;; ------------------------------------------------------------------
;;; the two delegates

(objc:define-objc-class map-delegate () ()
  (:objc-class-name "LispMapDelegate")
  (:objc-protocols "MKMapViewDelegate" "CLLocationManagerDelegate"))

(objc:define-objc-method ("mapView:rendererForOverlay:" objc:objc-object-pointer)
    ((self map-delegate) (view objc:objc-object-pointer) (overlay objc:objc-object-pointer))
  (declare (ignore view))
  (let ((renderer (objc:invoke (objc:invoke (objc:invoke "MKPolylineRenderer" "alloc")
                                            "initWithPolyline:" overlay)
                               "autorelease")))
    (objc:invoke renderer "setStrokeColor:" (ui:color 0.9 0.2 0.4))
    (objc:invoke renderer "setLineWidth:" 4d0)
    renderer))

(objc:define-objc-method ("locationManager:didUpdateLocations:" :void)
    ((self map-delegate) (manager objc:objc-object-pointer) (locations objc:objc-object-pointer))
  (declare (ignore manager))
  (let* ((location (objc:invoke locations "lastObject"))
         (coordinate (objc:invoke location "coordinate")))
    ;; CLLocationCoordinate2D, returned by value, read as a vector.
    (setf *location* (cons (aref coordinate 0) (aref coordinate 1)))
    (show-route)))

(objc:define-objc-method ("locationManager:didFailWithError:" :void)
    ((self map-delegate) (manager objc:objc-object-pointer) (error objc:objc-object-pointer))
  (declare (ignore manager))
  (say "location failed: ~a" (objc:ns-string-to-string (objc:invoke error "localizedDescription"))))

;;; ------------------------------------------------------------------
;;; the screen

(defvar *delegate* nil)

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font size))
    (objc:invoke label "setNumberOfLines:" lines)
    label))

(defun start ()
  (objc:ensure-objc-initialized)
  (setf *delegate* (ui:keep (make-instance 'map-delegate)))
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (ui:pin column "bottomAnchor" safe "bottomAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "Where the phone is, with a route from Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "CoreLocation's delegate and MapKit's overlay renderer are Lisp classes; the figure of eight is computed here; the region is a nested structure passed as a vector." :size 13))
    (setf *status* (label "waiting for a location…" :size 12))
    (objc:invoke column "addArrangedSubview:" *status*)
    (setf *map* (ui:new "MKMapView"))
    (objc:invoke (objc:invoke *map* "layer") "setCornerRadius:" 12)
    (objc:invoke *map* "setDelegate:" (objc:objc-object-pointer *delegate*))
    (objc:invoke column "addArrangedSubview:" *map*)
    (setf *manager* (ui:keep (objc:alloc-init-object "CLLocationManager")))
    (objc:invoke *manager* "setDelegate:" (objc:objc-object-pointer *delegate*))
    (objc:invoke *manager* "requestWhenInUseAuthorization")
    (objc:invoke *manager* "startUpdatingLocation")
    (values)))

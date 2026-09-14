;;;; compute.lisp -- the GPU, from Lisp.
;;;;
;;;; Metal's compute path, with no shader file in the bundle: the kernel is
;;;; a string here, compiled by the device at run time. Lisp picks the Julia
;;;; set's parameter, writes it into a buffer, dispatches the threadgroups
;;;; -- MTLSize is a structure of three integers, passed by value as a
;;;; vector -- waits, and reads the pixels back out of the output buffer to
;;;; make an image. The macOS example draws with Metal; this computes with
;;;; it, and the simulator's Metal is real.

(defpackage #:compute
  (:use #:cl)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:render #:*c*))

(in-package #:compute)

(defparameter +side+ 512)

(defparameter +kernel+ "
#include <metal_stdlib>
using namespace metal;

struct Params { float cr; float ci; uint side; };

kernel void julia(device uchar4 *out [[buffer(0)]],
                  constant Params &p [[buffer(1)]],
                  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= p.side || gid.y >= p.side) return;
  float zr = 3.0 * (float(gid.x) / p.side - 0.5);
  float zi = 3.0 * (float(gid.y) / p.side - 0.5);
  uint n = 0;
  for (; n < 200; n++) {
    float r2 = zr * zr, i2 = zi * zi;
    if (r2 + i2 > 4.0) break;
    zi = 2.0 * zr * zi + p.ci;
    zr = r2 - i2 + p.cr;
  }
  float t = n / 200.0;
  out[gid.y * p.side + gid.x] =
    uchar4(uchar(255 * pow(t, 0.5)), uchar(255 * t * t), uchar(255 * (1.0 - t)), 255);
}
")

(objc:define-objc-struct (mtl-size (:foreign-name "MTLSize"))
  (:width (:unsigned :long-long))
  (:height (:unsigned :long-long))
  (:depth (:unsigned :long-long)))

(defvar *device* nil)
(defvar *pipeline* nil)
(defvar *queue* nil)
(defvar *image-view* nil)
(defvar *status* nil)
(defvar *c* (cons -0.8 0.156) "The Julia parameter, real and imaginary.")

(defun say (format &rest arguments)
  (let ((text (apply #'format nil format arguments)))
    (format t "COMPUTE: ~a~%" text)
    (finish-output)
    (objc:invoke *status* "setText:" text)))

(defun ensure-pipeline ()
  "The device, the kernel compiled from its source, and a queue: once."
  (unless *pipeline*
    (setf *device* (si:call-cfun (cffi:foreign-symbol-pointer "MTLCreateSystemDefaultDevice")
                                 :pointer-void '() '()))
    (when (cffi:null-pointer-p *device*) (error "no Metal device"))
    (ui:keep *device*)
    (let ((library (objc:invoke *device* "newLibraryWithSource:options:error:" +kernel+ nil nil)))
      (when (cffi:null-pointer-p library) (error "the kernel did not compile"))
      (let ((function (objc:invoke library "newFunctionWithName:" "julia")))
        (setf *pipeline* (ui:keep (objc:invoke *device* "newComputePipelineStateWithFunction:error:" function nil)))))
    (setf *queue* (ui:keep (objc:invoke *device* "newCommandQueue"))))
  *pipeline*)

(defun render ()
  "One dispatch: the parameter in, the pixels out, an image on screen."
  (ensure-pipeline)
  (let* ((start (get-internal-real-time))
         (bytes (* +side+ +side+ 4))
         (output (objc:invoke *device* "newBufferWithLength:options:" bytes 0))
         (params (objc:invoke *device* "newBufferWithLength:options:" 16 0))
         (contents (objc:invoke params "contents")))
    ;; struct Params { float cr; float ci; uint side; }, written by hand.
    (setf (cffi:mem-ref contents :float 0) (float (car *c*) 1.0)
          (cffi:mem-ref contents :float 4) (float (cdr *c*) 1.0)
          (cffi:mem-ref contents :uint32 8) +side+)
    (let* ((commands (objc:invoke *queue* "commandBuffer"))
           (encoder (objc:invoke commands "computeCommandEncoder"))
           (w (objc:invoke *pipeline* "threadExecutionWidth"))
           (h (floor (objc:invoke *pipeline* "maxTotalThreadsPerThreadgroup") w)))
      (objc:invoke encoder "setComputePipelineState:" *pipeline*)
      (objc:invoke encoder "setBuffer:offset:atIndex:" output 0 0)
      (objc:invoke encoder "setBuffer:offset:atIndex:" params 0 1)
      ;; Two MTLSize by value, each a vector: the grid in threadgroups, and
      ;; the threadgroup in threads.
      (objc:invoke encoder "dispatchThreadgroups:threadsPerThreadgroup:"
                   (vector (ceiling +side+ w) (ceiling +side+ h) 1)
                   (vector w h 1))
      (objc:invoke encoder "endEncoding")
      (objc:invoke commands "commit")
      (objc:invoke commands "waitUntilCompleted"))
    ;; The pixels, straight out of the shared buffer, into a CGImage.
    (let* ((data (objc:invoke "NSData" "dataWithBytes:length:" (objc:invoke output "contents") bytes))
           (provider (si:call-cfun (cffi:foreign-symbol-pointer "CGDataProviderCreateWithCFData")
                                   :pointer-void '(:pointer-void) (list data)))
           (space (si:call-cfun (cffi:foreign-symbol-pointer "CGColorSpaceCreateDeviceRGB") :pointer-void '() '()))
           (image (si:call-cfun (cffi:foreign-symbol-pointer "CGImageCreate") :pointer-void
                                '(:unsigned-long :unsigned-long :unsigned-long :unsigned-long :unsigned-long
                                  :pointer-void :unsigned-int :pointer-void :pointer-void :int :int)
                                (list +side+ +side+ 8 32 (* 4 +side+) space (logior 1 (ash 4 12)) provider
                                      (cffi:null-pointer) 0 0)))
           (ms (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second)))
      (objc:invoke *image-view* "setImage:" (objc:invoke "UIImage" "imageWithCGImage:" image))
      (say "Julia set for c = ~,3f ~,3@fi: ~dx~d in ~d ms on ~a"
           (car *c*) (cdr *c*) +side+ +side+ ms
           (objc:ns-string-to-string (objc:invoke *device* "name"))))))

(defparameter +parameters+
  '((-0.8 . 0.156) (0.285 . 0.01) (-0.4 . 0.6) (-0.7269 . 0.1889) (0.355 . 0.355)))

(defun another ()
  (setf *c* (nth (mod (1+ (or (position *c* +parameters+ :test #'equal) -1)) (length +parameters+))
                 +parameters+))
  (render))

(defun label (text &key (size 15) (lines 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setFont:" (ui:font size))
    (objc:invoke label "setNumberOfLines:" lines)
    label))

(defun start ()
  (objc:ensure-objc-initialized)
  (let* ((root (ui:root-view))
         (safe (objc:invoke (ui:root-controller) "safeAreaLayoutGuide"))
         (column (ui:new "UIStackView"))
         (button (ui:system-button "Another c")))
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (objc:invoke column "setAxis:" 1)
    (objc:invoke column "setSpacing:" 10)
    (objc:invoke root "addSubview:" column)
    (ui:pin column "topAnchor" safe "topAnchor" 16)
    (ui:pin column "leadingAnchor" safe "leadingAnchor" 16)
    (ui:pin column "trailingAnchor" safe "trailingAnchor" -16)
    (objc:invoke column "addArrangedSubview:" (label "The GPU, from Lisp" :size 20))
    (objc:invoke column "addArrangedSubview:"
                 (label "A Metal kernel compiled from a string at run time; the parameter, the buffers and the threadgroup sizes from Lisp; the pixels read back into an image." :size 13))
    (setf *image-view* (ui:new "UIImageView"))
    (objc:invoke *image-view* "setContentMode:" 1)
    (objc:invoke (objc:invoke *image-view* "layer") "setCornerRadius:" 12)
    (objc:invoke *image-view* "setClipsToBounds:" t)
    (objc:invoke column "addArrangedSubview:" *image-view*)
    (ui:fix *image-view* "heightAnchor" 360)
    (ui:pin *image-view* "widthAnchor" column "widthAnchor")
    (setf *status* (label "" :size 12 :lines 2))
    (objc:invoke *status* "setFont:" (ui:mono-font 11))
    (objc:invoke column "addArrangedSubview:" *status*)
    (ui:on-tap button (lambda (sender) (declare (ignore sender)) (another)))
    (objc:invoke column "addArrangedSubview:" button)
    (handler-case (render)
      (error (condition) (say "Metal failed: ~a" condition)))
    (values)))

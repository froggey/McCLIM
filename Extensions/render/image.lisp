(in-package #:mcclim-render-internals)

;;; Image

(defun draw-image* (medium image x y
                    &rest args
                    &key clipping-region transformation)
  (declare (ignorable clipping-region transformation args))
  (climi::with-medium-options (medium args)
    (draw-pattern* medium image x y)))

(clim-internals::def-graphic-op draw-image* (image x y))

;;; Image operations

(defun make-image (width height)
  "Create an empty transparent image of size WIDTH x HEIGHT."
  ;; XXX: something in text rendering depends image being transparent by
  ;; default. This should be fixed.
  (make-instance 'clime:image-pattern :array (make-argb-pixel-array width height)))

;;; Unsafe versions of COPY-IMAGE. Caller must ensure that all arguments are
;;; valid and arrays are of proper type.
(macrolet
    ((define-copy-image (name backwardp)
       `(progn
          (declaim (inline ,name))
          (defun ,name (src-array dst-array x1s y1s x1d y1d x2 y2)
            (declare (type image-index x1s y1s x1d y1d x2 y2)
                     (type argb-pixel-array src-array dst-array)
                     (optimize (speed 3) (safety 0)))
            (do-regions ((src-j dest-j y1s y1d y2)
                         (src-i dest-i x1s x1d x2) ,@(when backwardp
                                                       `(:backward t)))
              (setf (aref dst-array dest-j dest-i)
                    (aref src-array src-j src-i)))))))
  (define-copy-image %copy-image nil)
  (define-copy-image %copy-image* t))

;;; XXX: We should unify it with COPY-AREA and MEDIUM-COPY-AREA. That means that
;;; raster images should be mediums on their own rights (aren't they?).
(defun copy-image (src-image sx sy width height dst-image dx dy
                   &aux
                   (sx (round sx))
                   (sy (round sy))
                   (dx (round dx))
                   (dy (round dy))
                   (width (round width))
                   (height (round height))
                   (src-array (climi::pattern-array src-image))
                   (dst-array (climi::pattern-array dst-image)))
  "Copy SRC-IMAGE to DST-IMAGE region-wise. Both may be the same image."
  (unless (%check-coords src-array dst-array sx sy dx dy width height)
    (return-from copy-image nil))
  (let ((max-x (+ dx width -1))
        (max-y (+ dy height -1)))
    (declare (fixnum max-x max-y))
    (cond ((not (eq src-array dst-array))
           #1=(%copy-image src-array dst-array sx sy dx dy max-x max-y))
          ((> sy dy) #1#)
          ((< sy dy) #2=(%copy-image* src-array dst-array sx sy dx dy max-x max-y))
          ((> sx dx) #1#)
          ((< sx dx) #2#)
          (t nil)))
  (make-rectangle* (1- dx) (1- dy) (+ dx width) (+ dy height)))

(macrolet
    ((define-blend-image (name backwardp)
       `(progn
          (declaim (inline ,name))
          (defun ,name (src-array dst-array x1s y1s x1d y1d x2 y2)
            (declare (type image-index x1s y1s x1d y1d x2 y2)
                     (type argb-pixel-array src-array dst-array)
                     (optimize (speed 3) (safety 0)))
            (do-regions ((src-j dest-j y1s y1d y2)
                         (src-i dest-i x1s x1d x2) ,@(when backwardp
                                                       `(:backward t)))
              (let-rgba ((r.fg g.fg b.fg a.fg) (aref src-array src-j src-i))
                (let-rgba ((r.bg g.bg b.bg a.bg) (aref dst-array dest-j dest-i))
                  (setf (aref dst-array dest-j dest-i)
                        (octet-blend-function* r.fg g.fg b.fg a.fg
                                               r.bg g.bg b.bg a.bg)))))))))
  (define-blend-image %blend-image nil)
  (define-blend-image %blend-image* t))

(defun blend-image (src-image sx sy width height dst-image dx dy
                    &aux
                    (sx (round sx))
                    (sy (round sy))
                    (dx (round dx))
                    (dy (round dy))
                    (width (round width))
                    (height (round height))
                    (src-array (climi::pattern-array src-image))
                    (dst-array (climi::pattern-array dst-image)))
  "Blend SRC-IMAGE into DST-IMAGE region-wise. Both may be the same image."
  (unless (%check-coords src-array dst-array sx sy dx dy width height)
    (return-from blend-image nil))
  (let ((max-x (+ dx width -1))
        (max-y (+ dy height -1)))
    (cond ((eq src-array dst-array)
           #1=(%blend-image src-array dst-array sx sy dx dy max-x max-y))
          ((> sy dy) #1#)
          ((< sy dy) #2=(%blend-image* src-array dst-array sx sy dx dy max-x max-y))
          ((> sx dx) #1#)
          ((< sx dx) #2#)
          (t nil)))
  (make-rectangle* (1- dx) (1- dy) (+ dx width) (+ dy height)))

(defun clone-image (image)
  (let ((src-array (climi::pattern-array image)))
    (declare (type argb-pixel-array src-array))
    (make-instance 'climi::%rgba-pattern :array (alexandria:copy-array src-array))))

(defun fill-image (image design &key (x 0) (y 0)
                                     (width (pattern-width image))
                                     (height (pattern-height image))
                                     stencil (stencil-dx 0) (stencil-dy 0)
                                     clip-region)
  "Blends DESIGN onto IMAGE with STENCIL and a CLIP-REGION."
  (declare (optimize (speed 3) (safety 0) (debug 0))
           (type image-index x y width height)
           (type (signed-byte 33) stencil-dx stencil-dy))
  ;; Disregard CLIP-REGION if x,y,width,height is entirely contained.
  (when clip-region
    (let ((region (make-rectangle* x y (+ x width) (+ y height))))
      (cond ((region-contains-region-p clip-region region) ; TODO we create almost this rectangle as our return value
             (setf clip-region nil))
            ((bounding-rectangle-p clip-region)
             (with-bounding-rectangle* (x1 y1 x2 y2)
                 (region-intersection clip-region region)
               (setf x (floor x1) y (floor y1) width (ceiling (- x2 x1)) height (ceiling (- y2 y1))
                     clip-region nil))))))
  (let* ((dst-array (climi::pattern-array image))
         (dst-width (array-dimension dst-array 1))
         (stencil-array (and stencil (climi::pattern-array stencil)))
         (stencil-height (when stencil-array
                           (array-dimension stencil-array 0)))
         (stencil-width (when stencil-array
                          (array-dimension stencil-array 1)))
         (X2 (+ x width -1))
         (y2 (+ y height -1))
         old-alpha alpha
         old-ink ink (ink-rgba 0)
         (static-ink-p t #+TODO (static-ink-p design))
         mode
         source-rgba source-r source-g source-b source-a)
    (declare (type argb-pixel-array dst-array)
             (type argb-pixel       ink-rgba))
    (flet ((update-alpha (x y)
             ;; Set ALPHA according to STENCIL-ARRAY. Set to NIL
             ;; (transparent) if x,y is outside STENCIL-ARRAY or the
             ;; array element is #xff, indicating full transparency.
             (locally (declare (type stencil-array stencil-array)
                               (type fixnum stencil-width stencil-height))
               (let ((stencil-x (+ stencil-dx x))
                     (stencil-y (+ stencil-dy y)))
                 (setf alpha
                       (if (and (<= 0 stencil-y stencil-height)
                                (<= 0 stencil-x stencil-width))
                           (let ((value (aref stencil-array stencil-y stencil-x)))
                             (if (= #xff value)
                                 nil
                                 value))
                           nil)))))
           (update-ink (i j)
             (when (or (not ink) (not static-ink-p))
               (setf ink      (clime:design-ink design i j)
                     ink-rgba (typecase ink
                                (standard-flipping-ink
                                 (let ((d1 (slot-value ink 'climi::design1))
                                       (d2 (slot-value ink 'climi::design2)))
                                   (logior (logxor (climi::%rgba-value d1)
                                                   (climi::%rgba-value d2))
                                           #xff)))
                                (t
                                 (climi::%rgba-value ink)))))
             (when (and (eq old-ink ink) (eql old-alpha alpha))
               (return-from update-ink))

             (cond ((typep ink 'standard-flipping-ink)
                    ;; TODO this can be cached
                    (let-rgba ((r.fg g.fg b.fg a.fg) ink-rgba)
                      (setf source-r r.fg
                            source-g g.fg
                            source-b b.fg)
                      (if alpha
                          (setf source-a (octet-mult a.fg alpha)
                                mode     :flipping/blend)
                          (setf source-a    #x00
                                source-rgba (%vals->rgba source-r source-g source-b #xff)
                                mode        :flipping))))
                   ((not alpha)
                    (if (= #xff (logand #xff ink-rgba))
                        (setf source-rgba ink-rgba
                              mode        :copy)
                        (let-rgba ((r g b a) ink-rgba)
                          (setf source-r r
                                source-g g
                                source-b b
                                source-a a
                                mode     :blend))))
                   (t
                    (let-rgba ((r.fg g.fg b.fg a.fg) ink-rgba)
                      (setf source-r r.fg
                            source-g g.fg
                            source-b b.fg
                            source-a (octet-mult a.fg alpha)
                            mode     (case source-a
                                       (0
                                        nil)
                                       (255
                                        (setf source-rgba ink-rgba)
                                        :copy)
                                       (t
                                        :blend))))))))
      (do-region-pixels ((dst-width (di  dx dy) :x1 x :x2 x2 :y1 y :y2 y2)
                         (nil       (nil sx sy) :x1 x        :y1 y))
        (when (or (null clip-region)
                  (region-contains-position-p clip-region sx sy))
          (when stencil-array
            (update-alpha sx sy))
          (update-ink sx sy)
          (setf old-alpha alpha
                old-ink   ink)

          (case mode
            (:flipping
             (setf (row-major-aref dst-array di)
                   (logxor source-rgba (row-major-aref dst-array di))))
            (:flipping/blend
             (let-rgba ((r.bg g.bg b.bg a.bg) (row-major-aref dst-array di))
                       (setf (row-major-aref dst-array di)
                             (octet-blend-function*
                              (color-octet-xor source-r r.bg)
                              (color-octet-xor source-g b.bg)
                              (color-octet-xor source-b g.bg)
                              source-a
                              r.bg g.bg b.bg a.bg))))
            (:copy
             (setf (row-major-aref dst-array di) source-rgba))
            (:blend
             (let-rgba ((r.bg g.bg b.bg a.bg) (row-major-aref dst-array di))
               (setf (row-major-aref dst-array di)
                     (octet-blend-function*
                      source-r source-g source-b source-a
                      r.bg     g.bg     b.bg     a.bg)))))))))
  ;; XXX These #'1- are fishy. We don't capture correct region (rounding
  ;; issue?). This problem is visible when scrolling.
  (make-rectangle* (1- x) (1- y) (+ x width) (+ y height)))

#+old (defun fill-image (image design &key (x 0) (y 0)
                                     (width (pattern-width image))
                                     (height (pattern-height image))
                                     stencil (stencil-dx 0) (stencil-dy 0)
                                     clip-region
				&aux
				(dst-array (climi::pattern-array image))
				(x2 (+ x width -1))
				(y2 (+ y height -1)))
  "Blends DESIGN onto IMAGE with STENCIL and a CLIP-REGION."
  (let ((stencil-array (and stencil (climi::pattern-array stencil))))
    (do-regions ((src-j j y y y2)
                 (src-i i x x x2))
      (when (or (null clip-region)
                (region-contains-position-p clip-region src-i src-j))
        (let ((alpha (if stencil-array
                         (let ((stencil-x (+ stencil-dx i))
                               (stencil-y (+ stencil-dy j)))
                           (if
                            (array-in-bounds-p stencil-array stencil-y stencil-x)
                            (aref stencil-array stencil-y stencil-x)
                            #xff))
                         #xff))
              (ink (clime:design-ink design src-i src-j)))
          (if (typep ink 'standard-flipping-ink)
              (let-rgba ((r.fg g.fg b.fg a.fg) (let ((d1 (slot-value ink 'climi::design1))
                                                     (d2 (slot-value ink 'climi::design2)))
                                                 (logior (logxor (climi::%rgba-value d1)
                                                                 (climi::%rgba-value d2))
                                                         #xff)))
                (let-rgba ((r.bg g.bg b.bg a.bg) (aref dst-array j i))
                  (setf (aref dst-array j i)
                        (octet-blend-function* (color-octet-xor r.fg r.bg)
                                               (color-octet-xor g.fg g.bg)
                                               (color-octet-xor b.fg b.bg)
                                               (octet-mult a.fg alpha)
                                               r.bg g.bg b.bg a.bg))))
              (let-rgba ((r.fg g.fg b.fg a.fg) (climi::%rgba-value ink))
                (let-rgba ((r.bg g.bg b.bg a.bg) (aref dst-array j i))
                  (setf (aref dst-array j i)
                        (octet-blend-function* r.fg g.fg b.fg (octet-mult a.fg alpha)
                                               r.bg g.bg b.bg a.bg)))))))))
  ;; XXX These #'1- are fishy. We don't capture correct region (rounding
  ;; issue?). This problem is visible when scrolling.
  (make-rectangle* (1- x) (1- y) (+ x width) (+ y height)))

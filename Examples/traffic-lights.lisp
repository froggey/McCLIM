;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Package: CLIM-DEMO; Base: 10; Lowercase: Yes -*-

;; $fiHeader: calcuator.lisp,v 1.0 22/08/200 $

;;;  (c) copyright 2001 by 
;;;           Julien Boninfante (boninfan@emi.u-bordeaux.fr)

;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the 
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330, 
;;; Boston, MA  02111-1307  USA.


;;; How to use the possibilities of the traffic-lights, you have two
;;; possibilites :
;;; 1 - Click on a toggle-button : the color of the light-pane
;;;     will change
;;; 2 - Click on the orange or green toggle-button, then move your
;;;     mouse-pointer on the light-pane, and wait a few seconds.


(in-package :clim-internals)

(export 'clim::light-pane '#:clim)      ;Hugh?! --GB

;; example gadget definition
(defclass light-pane (standard-gadget) ())

(defmethod dispatch-repaint ((pane light-pane) region)
  (repaint-sheet pane region))

(defmethod repaint-sheet ((pane light-pane) region)
  (declare (ignore region))
  (multiple-value-bind (x1 y1 x2 y2) (bounding-rectangle* (sheet-region pane))
    (display-gadget-background pane (gadget-current-color pane) 0 0 (- x2 x1) (- y2 y1))))

(defmethod handle-event ((pane light-pane) (event window-repaint-event))
  (declare (ignorable event))
  (dispatch-repaint pane (sheet-region pane)))

(in-package :clim-demo)

;; callback functions

(defmethod handle-event :after ((pane clim-internals::light-pane) (event pointer-event))
  (declare (ignorable event))
  (let ((label (clim-internals::gadget-label (clim-internals::radio-box-current-selection
					      (slot-value *application-frame* 'radio-box)))))
    (cond ((string= label "O")
	   (progn
	     (sleep 3)
	     (simulate-user-action (third (frame-panes *application-frame*)))))
	  ((string= label "G")
	   (progn
	     (sleep 5)
	     (simulate-user-action (first (frame-panes *application-frame*)))))
	  (t nil))))

(defmethod simulate-user-action ((pane toggle-button))
  (handle-event pane
		(make-instance 'pointer-button-press-event))
  (handle-event pane
		(make-instance 'pointer-button-release-event)))

(defun callback-red (gadget value)
  (declare (ignorable gadget))
  (when value
    (setf (clim-internals::gadget-current-color (slot-value *application-frame* 'light))
	  (clim-internals::gadget-normal-color (slot-value *application-frame* 'light)))))

(defun callback-orange (gadget value)
  (declare (ignore gadget))
  (when value 
    (setf (clim-internals::gadget-current-color (slot-value *application-frame* 'light))
	  (clim-internals::gadget-highlighted-color (slot-value *application-frame* 'light)))))

(defun callback-green (gadget value)
  (declare (ignore gadget))
  (when value
    (setf (clim-internals::gadget-current-color (slot-value *application-frame* 'light))
	  (clim-internals::gadget-pushed-and-highlighted-color (slot-value *application-frame* 'light)))))

;; test functions

(defun traffic-lights ()
  (loop for port in climi::*all-ports*
      do (destroy-port port))
  (setq climi::*all-ports* nil)
  (run-frame-top-level (make-application-frame 'traffic-lights)))

(defmethod traffic-lights-frame-top-level ((frame application-frame))
  (setf (slot-value *application-frame* 'light) (car (last (frame-panes *application-frame*)))
	(slot-value *application-frame* 'radio-box)
	(with-radio-box ()
	 (first (frame-panes *application-frame*))
	 (second (frame-panes *application-frame*))
	 (radio-box-current-selection (third (frame-panes *application-frame*)))))
  (loop (event-read (frame-pane frame))))

(define-application-frame traffic-lights ()
  ((radio-box :initform nil)
   (light :initform nil))
  (:panes
   (light     :light
	      :width 30
	      :normal +red+
	      :highlighted +orange+
	      :pushed-and-highlighted +green+)
   (red-light :toggle-button
	      :label "R"
	      :value t
	      :width 30
	      :height 30
	      :normal +red+
	      :highlighted +red+
	      :pushed-and-highlighted +red+
	      :value-changed-callback 'callback-red)
   (green-light :toggle-button
		:label "G"
		:value nil
		:height 30
		:normal +green+
		:highlighted +green+
		:pushed-and-highlighted +green+
	        :value-changed-callback 'callback-green)
   (orange-light :toggle-button
		 :label "O"
		 :value nil
		 :height 30
		 :normal +orange+
		 :highlighted +orange+
		 :pushed-and-highlighted +orange+
		 :value-changed-callback 'callback-orange))
   (:layouts
    (default (horizontally () (vertically () red-light orange-light green-light) light)))
   (:top-level (traffic-lights-frame-top-level . nil)))

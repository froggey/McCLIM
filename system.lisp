;;; -*- Mode: Lisp; Package: User -*-

;;;  (c) copyright 1998,1999,2000 by Michael McDonald (mikemac@mikemac.com)
;;;  (c) copyright 2000 by 
;;;           Robert Strandh (strandh@labri.u-bordeaux.fr)

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

(in-package :common-lisp-user)

(defparameter *clim-directory* (directory-namestring *load-truename*))

#+cmu
(progn
  (unless (fboundp 'ext:stream-read-char)
    (unless (ignore-errors (ext:search-list "gray-streams:"))
      (setf (ext:search-list "gray-streams:")
	'("target:pcl/" "library:subsystems/")))
    (if (fboundp 'without-package-locks)
	(without-package-locks
	 (load "gray-streams:gray-streams-library"))
      (load "gray-streams:gray-streams-library")))
  #-clx
  (require :clx)
  #-(or mk-defsystem asdf)
  (load "library:subsystems/defsystem")
  #+mp (when (eq mp::*initial-process* mp::*current-process*)
	 (format t "~%~%You need to run (mp::startup-idle-and-top-level-loops) to start up the multiprocessing support.~%~%")))

(pushnew :clim *features*)
(pushnew :mcclim *features*)

#+mk-defsystem (use-package "MK")

(defmacro clim-defsystem ((module &key depends-on) &rest components)
  `(progn
     #+mk-defsystem
     (defsystem ,module
       :source-pathname *clim-directory*
       :source-extension "lisp"
       ,@(and depends-on `(:depends-on ,depends-on))
        :components
	(:serial
	 ,@components))
     #+asdf
     (asdf:defsystem ,module
	 ,@(and depends-on
		`(:depends-on ,depends-on))
	 :serial t
	 :components
	 (,@(loop for c in components
		  for p = (merge-pathnames
			   (parse-namestring c)
			   (make-pathname :type "lisp"
					  :defaults *clim-directory*))
		  collect `(:file ,(pathname-name p) :pathname ,p))))
     #-(or mk-defsystem asdf)
     (defsystem ,module ()
       (:serial
	,@depends-on
	,@components))))

(clim-defsystem (:clim-lisp)
  ;; First possible patches
  "patch"
  #+cmu       "Lisp-Dep/fix-cmu"
  #+excl      "Lisp-Dep/fix-acl"
  #+sbcl      "Lisp-Dep/fix-sbcl"
  #+openmcl   "Lisp-Dep/fix-openmcl"
  #+lispworks "Lisp-Dep/fix-lispworks"
  "package")

(clim-defsystem (:clim-core :depends-on (:clim-lisp))
   "decls"

   #.(or
      #+(and :cmu :mp (not :pthread))  "Lisp-Dep/mp-cmu"

      ;; Rumor is that SB-THREAD is a feature test for the presence of
      ;; multithreading in SBCL.

      #+sb-thread               "Lisp-Dep/mp-sbcl"
      #+excl                    "Lisp-Dep/mp-acl"
      #+openmcl                 "Lisp-Dep/mp-openmcl"
      #+lispworks               "Lisp-Dep/mp-lw"
      #| fall back |#           "Lisp-Dep/mp-nil")
   "utils"
   "defresource"
   "setf-star"
   
   "design"
   "X11-colors"
   "coordinates"
   "transforms"
   "regions"

   "sheets"
   "pixmap"
   
   "events"

   "ports" ; depends on events
   "grafts"
   "medium"
   "output"

   "input"
   "repaint"
   "graphics"
   "views"
   "stream-output"
   "recording"
   "encapsulate"
   "stream-input"			; depends on WITH-ENCAPSULATING-STREAM
)

(clim-defsystem (:goatee-core :depends-on (:clim-core))
  "Goatee/conditions"
  "Goatee/dbl-list"
  "Goatee/flexivector"
  "Goatee/buffer"
  "Goatee/editable-buffer"
  "Goatee/editable-area"
  "Goatee/clim-area"
  "Goatee/kill-ring"
  "Goatee/goatee-command"
  "Goatee/editing-stream"
  "Goatee/presentation-history"
  )

;;; CLIM-PostScript is not a backend in the normal sense.
;;; It is an extension (Chap. 35.1 of the spec) and is an
;;; "included" part of McCLIM. Hence the defsystem is here.
(clim-defsystem (:clim-postscript :depends-on (:clim-core))
   "Backends/PostScript/package"
   "Backends/PostScript/paper"
   "Backends/PostScript/class"
   "Backends/PostScript/font"
   "Backends/PostScript/graphics"
   "Backends/PostScript/sheet"
   "Backends/PostScript/afm"
   "Backends/PostScript/standard-metrics"
   )

(clim-defsystem (:clim :depends-on (:clim-core :goatee-core :clim-postscript))
   "text-formatting"
   "input-editing"
   "presentations"
   "presentation-defs"
   "pointer-tracking" ; depends on WITH-INPUT-CONTEXT
   "commands"
   "frames"
   "incremental-redisplay"
   "panes"
   "gadgets"
   "menu"
   "table-formatting"
   "graph-formatting"
   "bordered-output"
   "dialog" ; depends on table formatting
   "builtin-commands" ; need dialog before commands are defined
   "describe"
   "Experimental/menu-choose" ; depends on table formatting, presentations
   "Goatee/presentation-history"
   )

(load (merge-pathnames "Backends/CLX/system" *clim-directory*))
#+gl(load (merge-pathnames "Backends/OpenGL/system" *clim-directory*))

(clim-defsystem (:clim-looks :depends-on (#+clx :clim-clx #+gl :clim-opengl))
  "Looks/pixie")

;;; Will depend on :goatee soon...
;;; name of :clim-clx-user chosen by mikemac for no good reason
(clim-defsystem (:clim-clx-user :depends-on (:clim :clim-clx)))

;;; CLIM-Examples depends on having at least one backend loaded.
;;; Which backend is the user's choice.
(clim-defsystem (:clim-examples :depends-on (:clim #+clx :clim-looks))
   "Examples/calculator"
   "Examples/colorslider"
   "Examples/menutest"
   "Examples/address-book"
   "Examples/traffic-lights"
   "Examples/clim-fig"
   "Examples/postscript-test"
   ;; "Examples/puzzle"
   "Examples/transformations-test"
   ;; "Examples/sliderdemo"
   "Examples/stream-test"
   "Examples/presentation-test"
   #+clx "Examples/gadget-test"
   "Goatee/goatee-test")




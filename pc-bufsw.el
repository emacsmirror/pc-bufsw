;;; pc-bufsw.el -- switch buffers in mru/lru order

;; Author: Igor Bukanov <igor@mir2.org>
;; Maintainer: Igor Bukanov
;; Version 3.0
;; Keywords: buffer
;; URL: https://github.com/ibukanov/emacs-pc-bufsw

;; Anyone is free to copy, modify, publish, use, compile, sell, or
;; distribute this software, either in source code form or as a compiled
;; binary, for any purpose, commercial or non-commercial, and by any
;; means.
;; 
;; In jurisdictions that recognize copyright laws, the author or authors
;; of this software dedicate any and all copyright interest in the
;; software to the public domain. We make this dedication for the benefit
;; of the public at large and to the detriment of our heirs and
;; successors. We intend this dedication to be an overt act of
;; relinquishment in perpetuity of all present and future rights to this
;; software under copyright law.
;; 
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;; IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
;; OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
;; ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;; OTHER DEALINGS IN THE SOFTWARE.

;;; Commentary:

;; This switches Emacs buffers according to
;; most-recently-used/least-recently-used order that is similar to one
;; that is often available in Windows or Linux PC applications. The
;; main idea here is that a user chooses two key combinations like
;; C-tab/C-S-tab that switch between buffers according to most or
;; least recently used order. After the final choice is made the last
;; selected buffer becomes the most recently used one.


;;; ChangeLog:

;; 2015-09-17 (3.0 release)
;; Using pc-bufsw- and pc-bufsw--, not non-standard pc-bufsw:: prefix for function names.

;; 2007-06-27
;; Removal of window switching facility making pc-bufsw to switch only between
;; buffers. Emacs and window managers provides enough key bindings to switch
;; between windows and frames.

;; 2005-08-25
;; Introduction of pc-bufsw--keep-focus-window mode. This is not the
;; start of the feature creep as the old mode is kept for compatibility
;; as users may not appreciate the new behavior.

;; 2005-08-17 (1.3 release)
;; * Use buffer-display-time to construct buffer list in proper least
;;   recently used order to defeat bury-buffer abuse by various tools.
;; * When switching from initial window, restore the original buffer
;;   there.
;; * Fix frame switching using select-frame-set-input-focus. It does
;;   not resolve all the issue, but at least it works.

;;; Code:

(provide 'pc-bufsw)

(defvar pc-bufsw-quite-time 3
  "*Quite time to automaticaly terminate buffer switch mode.  If there
is no input during quite-time seconds makes the last choosen buffer
current." )

; Variable to store data vector during buffers change. Each element is buffer
; to show after i-th switch. It is supposed that buffers in the vector are
; odered according to the most recently used oder.
(defvar pc-bufsw--walk-vector nil)

(defun pc-bufsw--get-buf (index)
  (aref pc-bufsw--walk-vector index))

; Index of currently selected buffer in pc-bufsw--walk-vector.
(defvar pc-bufsw--cur-index 0)

; The initial buffer list.  When a user stops the selection, the new buffer
; order much the list except the selected buffer that is moved on the top.
(defvar pc-bufsw--start-buf-list nil)

(defun pc-bufsw--previous ()
  (interactive)
  (pc-bufsw--walk 1))

(defun pc-bufsw--lru ()
  (interactive)
  (pc-bufsw--walk -1))

;;;###autoload
(defun pc-bufsw-bind-keys (key1 key2)
  "Bind key1 and key2 to switch buffers in most or least recently used
oder.  Pressing key1 or key2 would switch to most or least recently
used buffer and enter switch mode. In this mode subsequent pressing of
key1 or key2 would go father in buffer list shown in echo area.

Pressing any other key or no input during the period indicated by
'pc-bufsw-quite-time' variable closes the mode and makes the last
selected buffer current.  If newly selected buffer is shown in some
window that would be used to show the buffer. Otherwise it will be
displayed in the initial window.

Typical usage in .emacs file:

  (require 'pc-bufsw)
  (pc-bufsw-bind-keys [C-tab] [C-S-tab])

Or like the following which also works with non-graphical terminals when
C-Tab and S-C-Tab are not available:

  (require 'pc-bufsw)
  (pc-bufsw-bind-keys [f12] [f11])
"
  (global-set-key key1 'pc-bufsw--previous)
  (global-set-key key2 'pc-bufsw--lru))

;;;###autoload
(defun pc-bufsw-bind-keys-default ()
  "Bind [C-tab] and [C-S-tab] to switch buffers according to most or least recently used order."
  (pc-bufsw-bind-keys [C-tab] [C-S-tab])

  (if window-system
      ;; Workarounds for some Linux GUI setups
      (global-set-key [C-S-iso-lefttab] 'pc-bufsw--lru)
    ;; Workaround for Cygiwn terminal
    (pc-bufsw-bind-keys "\e[1;5I" "\e[1;6I")))

; Main loop. It does 4 things.
; First, select new buffer and/or windows according to user input.
; Second, it selects the newly choosen buffer/windows/frame.
; Third, it draw in the echo area line with buffer names.
; Forth, it waits for a timeout to terminate the switching.
(defun pc-bufsw--walk (direction)
  (when (and (null pc-bufsw--walk-vector) (pc-bufsw--can-start))
    (setq pc-bufsw--start-buf-list (buffer-list))
    (setq pc-bufsw--cur-index 0)
    (setq pc-bufsw--walk-vector (pc-bufsw--get-walk-vector))
    (add-hook 'pre-command-hook 'pc-bufsw--switch-hook))
  (when pc-bufsw--walk-vector
    (let ((prev-index pc-bufsw--cur-index))
      (pc-bufsw--choose-next-index direction)
      (when (not (= pc-bufsw--cur-index prev-index))
	(switch-to-buffer (pc-bufsw--get-buf pc-bufsw--cur-index) t))
      (pc-bufsw--show-buffers-names)
      (when (sit-for pc-bufsw-quite-time)
	(pc-bufsw--finish)))))

(defun pc-bufsw--can-start ()
  (not (window-minibuffer-p (selected-window))))

(defun pc-bufsw--get-buffer-display-time (buffer)
  (save-excursion
    (set-buffer buffer)
    buffer-display-time))

(defun pc-bufsw--set-buffer-display-time (buffer time)
  (save-excursion
    (set-buffer buffer)
    (setq buffer-display-time time)))

;; Hook to access next input from user.
(defun pc-bufsw--switch-hook ()
  (when (or (null pc-bufsw--walk-vector)
	    (not (or (eq 'pc-bufsw--lru this-command)
		     (eq 'pc-bufsw--previous this-command)
		     (eq 'handle-switch-frame this-command))))
    (pc-bufsw--finish)))

;; Construct main buffer vector.
(defun pc-bufsw--get-walk-vector()
  (let* ((cur-buf (current-buffer))
	 (assembled (list cur-buf)))
    (mapc (lambda (buf)
	    (when (and (pc-bufsw--can-work-buffer buf)
		       (not (eq buf cur-buf)))
	      (setq assembled (cons buf assembled))))
	  pc-bufsw--start-buf-list)
    (setq assembled (nreverse assembled))
    (apply 'vector assembled)))

;;Return nill if buffer is not sutable for switch
(defun pc-bufsw--can-work-buffer (buffer)
  (let ((name (buffer-name buffer)))
    (not (char-equal ?\  (aref name 0)))))

;; Echo buffer list. Current buffer marked by <>.
(defun pc-bufsw--show-buffers-names()
  (let* ((width (frame-width))
	 (n (pc-bufsw--find-first-visible width))
	 (str (pc-bufsw--make-show-str n width)))
    (message "%s" str)))

(defun pc-bufsw--find-first-visible(width)
  (let ((first-visible 0)
	(i 1)
	(visible-length (pc-bufsw--show-name-len 0 t)))
    (while (<= i pc-bufsw--cur-index)
      (let ((cur-length (pc-bufsw--show-name-len i (= first-visible i))))
	(setq visible-length (+ visible-length cur-length))
	(when (> visible-length width)
	  (setq first-visible i)
	  (setq visible-length cur-length)))
      (setq i (1+ i)))
    first-visible))

(defun pc-bufsw--show-name-len(i at-left-edge)
  (+ (if at-left-edge 2 3)
     (length (buffer-name (pc-bufsw--get-buf i)))))

(defun pc-bufsw--make-show-str (first-visible width)
  (let* ((i (1+ first-visible))
	 (count (length pc-bufsw--walk-vector))
	 (str (pc-bufsw--show-name first-visible t))
	 (visible-length (length str))
	 (continue-loop (not (= i count))))
    (while continue-loop
      (let* ((name (pc-bufsw--show-name i nil))
	     (name-len (length name)))
	(setq visible-length (+ visible-length name-len))
	(if (> visible-length width)
	    (setq continue-loop nil)
	  (setq str (concat str name))
	  (setq i (1+ i))
	  (when (= i count)
	    (setq continue-loop nil)))))
    str))

(defun pc-bufsw--show-name(i at-left-edge)
  (let ((name (buffer-name (pc-bufsw--get-buf i))))
    (cond
     ((= i pc-bufsw--cur-index) (concat (if at-left-edge "<" " <") name ">"))
     (at-left-edge (concat " " name " "))
     (t (concat "  " name " ")))))

(defun pc-bufsw--choose-next-index (direction)
  (setq pc-bufsw--cur-index
	(mod (+ pc-bufsw--cur-index direction)
	     (length pc-bufsw--walk-vector))))

;; Called on switch mode close
(defun pc-bufsw--finish()
  (pc-bufsw--restore-order (pc-bufsw--get-buf pc-bufsw--cur-index)
			   pc-bufsw--start-buf-list)
  (remove-hook 'pre-command-hook 'pc-bufsw--switch-hook)
  (setq pc-bufsw--walk-vector nil)
  (setq pc-bufsw--cur-index 0)
  (setq pc-bufsw--start-buf-list nil)
  (message nil))

;; Put buffers in Emacs buffer list according to oder indicated by list
;; except put chosen-buffer to the first place.
(defun pc-bufsw--restore-order(chosen-buffer list)
  (mapc (lambda (buf)
	  (when (not (eq buf chosen-buffer))
	    (bury-buffer buf)))
	list))


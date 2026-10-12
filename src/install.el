;;; install.el --- Install EP3C configuration -*- lexical-binding: t -*-
;;
;;; Commentary:
;;
;; Installation routines for EP3C.
;;
;;; Code:

;; Load core.el from the same directory this file was loaded from.
;; Fall back to the repository layout via `default-directory' when
;; `load-file-name' is not bound (e.g. byte-compiling).
(require 'core
         (expand-file-name "core" (file-name-directory
                                   (or load-file-name buffer-file-name
                                       default-directory))))

(defun ep3c--set-modules (sym value)
  "Setter for ep3c-modules.
SYM is the custom variable being set.
VALUE is the new value being assigned."
  (let* ((modules-dir (file-name-concat default-directory "src" "modules"))
         (value (or (ep3c--migrate-modules-value value) value))
         (value (ep3c--valid-modules value modules-dir)))
    (put sym 'custom-type (ep3c--modules-custom-type modules-dir))
    (put sym 'standard-value (list value))
    (set-default sym value)))

(defun ep3c--modules-default ()
  "Return default value for ep3c-modules."
  (let* ((custom-file (if (boundp 'custom-file) custom-file
                        (file-name-concat user-emacs-directory "custom.el")))
         (saved (and (file-exists-p custom-file)
                     (get 'ep3c-modules 'customized-value))))
    (if saved
        (ep3c--migrate-modules-value (car (cdr saved)))
      '())))

(defun ep3c--install (init-package core-package modules-wildcard)
  "Main Installation routine.
INIT-PACKAGE contains the path to init.el, CORE-PACKAGE the path to
core.el while MODULES-WILDCARD matches the available module paths"
  (let* ((modules (file-expand-wildcards modules-wildcard))
	 (modules-target-directory (file-name-as-directory (file-name-concat
							    user-emacs-directory
							    "modules"))))
    (unless (file-directory-p modules-target-directory)
      (make-directory modules-target-directory))

    (copy-file init-package user-emacs-directory t)
    (copy-file core-package user-emacs-directory t)

    (dolist (module modules)
      (when (file-exists-p module)
	(message (format "INSTALLING EP3C module: '%s' to %s directory"
			 module
			 modules-target-directory))
	(copy-file module modules-target-directory t)))
    (file-expand-wildcards (file-name-concat modules-target-directory "*.org"))))


(defun ep3c--setup ()
  "Install EP3C configuration to `user-emacs-directory'."
  (unless (file-directory-p user-emacs-directory)
    (make-directory user-emacs-directory))

  (setq custom-file (file-name-concat user-emacs-directory "custom.el"))

  (let* ((source-directory (file-name-concat default-directory "src"))
	 (init-package (file-name-concat source-directory "init.el"))
	 (core-package (file-name-concat source-directory "core.el"))
	 (modules-wildcard (file-name-concat source-directory "modules" "*.org")))
    (ep3c--install init-package core-package modules-wildcard))

  (defcustom ep3c-modules
    (ep3c--modules-default)
    "List of EP3C modules to load. Check modules to enable them."
    :type '(set :greedy t (const :tag "dummy" nil))
    :set #'ep3c--set-modules
    :group 'ep3c)

  ;; Validate modules after defcustom is defined
  (let ((modules-dir (file-name-concat default-directory "src/modules")))
    (put 'ep3c-modules 'custom-type
         (ep3c--modules-custom-type modules-dir))
    (set-default 'ep3c-modules
                 (ep3c--valid-modules (default-value 'ep3c-modules)
                                      modules-dir)))

  (customize-option 'ep3c-modules))

(provide 'install)
;;; install.el ends here
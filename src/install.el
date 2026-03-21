;;; install.el --- Install EP3C configuration -*- lexical-binding: t -*-
;;
;;; Commentary:
;;
;; Installation routines for EP3C.
;;
;;; Code:

(defun ep3c--install (init-package modules-wildcard)
  "Main Installation routine.
INIT-PACKAGE contain the path to init.el while MODULES-WILDCARD matches
the available module paths"
  (let* ((modules (file-expand-wildcards modules-wildcard))
	 (modules-target-directory (file-name-as-directory (file-name-concat
							    user-emacs-directory
							    "modules"))))
    (when (file-directory-p modules-target-directory)
      (delete-directory modules-target-directory t))
    (make-directory modules-target-directory)
    (copy-file init-package user-emacs-directory t)

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
	 (modules-wildcard (file-name-concat source-directory "modules" "*.org")))
    (setq installed-modules (ep3c--install init-package modules-wildcard)))

  (defcustom ep3c-modules
    installed-modules
    "List of available EP3C modules. Disable any module by deleting it from this list."
    :type '(repeat (file :must-match nil))
    :group 'ep3c)

  (customize-option 'ep3c-modules))

(provide 'install)
;;; install.el ends here

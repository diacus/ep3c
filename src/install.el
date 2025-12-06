(defun install-ep3c (init-package modules-wildcard)
  "Main Installation rutine"
  (let* ((modules (file-expand-wildcards modules-wildcard))
	 (modules-target-directory (file-name-as-directory (file-name-concat
							    user-emacs-directory
							    "modules"))))
    (when (file-directory-p modules-target-directory)
      (delete-directory modules-target-directory t))
    (make-directory modules-target-directory)
    (copy-file init-package user-emacs-directory)

    (dolist (module modules)
      (when (file-exists-p module)
	(message (format "INSTALLING EP3C module: '%s' to %s directory"
			 module
			 modules-target-directory))
	(copy-file module modules-target-directory t)))
    (file-expand-wildcards (file-name-concat modules-target-directory "*.org"))))

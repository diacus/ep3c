;;; install.el --- Install EP3C configuration -*- lexical-binding: t -*-
;;
;;; Commentary:
;;
;; Installation routines for EP3C.
;;
;;; Code:

(require 'cl-lib)

(defun ep3c--migrate-modules-value (value)
  "Convert VALUE to new symbol-based format if needed."
  (cond
   ((and (listp value) (symbolp (car value))) value)
   ((and (listp value) (stringp (car value)))
    (mapcar (lambda (s)
              (intern (file-name-base s)))
            value))
   (t nil)))

(defun ep3c--modules-custom-type (modules)
  "Generate custom type for MODULES list."
  `(set :greedy t
        :value (,@(mapcar (lambda (module)
                            `(const :tag ,(format "%s" module) ,module))
                          modules))))

(defun ep3c--set-modules (sym value)
  "Setter for ep3c-modules.
SYM is the custom variable being set.
VALUE is the new value being assigned."
  (let* ((value (or (ep3c--migrate-modules-value value) value))
         (available-modules
          (mapcar #'intern
                  (mapcar #'file-name-base
                          (file-expand-wildcards
                           (file-name-concat default-directory "src/modules/*.org")))))
         (value (delq nil (mapcar (lambda (m)
                                    (if (memq m available-modules) m))
                                  value))))
    (put sym 'custom-type (ep3c--modules-custom-type available-modules))
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
      (mapcar #'intern
              (mapcar #'file-name-base
                      (file-expand-wildcards
                       (file-name-concat default-directory "src/modules/*.org")))))))

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
    (ep3c--install init-package modules-wildcard))

  (defcustom ep3c-modules
    (ep3c--modules-default)
    "List of EP3C modules to load. Check modules to enable them."
    :type '(set :greedy t (const :tag "dummy" nil))
    :set #'ep3c--set-modules
    :group 'ep3c)

  ;; Validate modules after defcustom is defined
  (let* ((modules-dir (file-name-concat default-directory "src/modules"))
         (available-modules
          (mapcar #'intern
                  (mapcar #'file-name-base
                          (file-expand-wildcards
                           (file-name-concat modules-dir "*.org")))))
         (current-value (default-value 'ep3c-modules))
         (valid-modules
          (cl-remove-if-not (lambda (m) (memq m available-modules)) current-value)))
    (put 'ep3c-modules 'custom-type
         (ep3c--modules-custom-type available-modules))
    (set-default 'ep3c-modules valid-modules))

  (customize-option 'ep3c-modules))

(provide 'install)
;;; install.el ends here
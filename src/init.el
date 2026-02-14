;;; init --- Init file for Emacs -*- lexical-binding: t -*-
;;
;;; Commentary:
;;
;; Simple minimal configuration and module loading
;;
;; Local Variables:
;; byte-compile-warnings: (not free-vars)
;; End:
;;
;;; Code:
(defmacro init--with-ensure-frame-ready (fn &rest args)
  "Call FN is called with optional ARGS when a graphical frame is ready.

First verifies if Emacs runs in daemon mode, in that case adds FN to
`after-make-frame-functions' hook to ensure it runs when the GUI is ready.

Executes FN right away otherwise."
  `(if (daemonp)
       (add-hook 'after-make-frame-functions
		 (lambda (frame)
		   (with-selected-frame frame
		     (message (format "Executing %s in daemon mode" ,fn))
		     ,(if (null args) `(funcall ,fn)
			`(apply ,fn (list ,@args)))))
		 t)
     (message (format "No daemon mode enabled, executing %s right away" ,fn))
     ,(if (null args) `(funcall ,fn)
	`(apply ,fn (list ,@args)))))

(defun init--setup-minimal-ui ()
  "Set up nimial UI."
  (when (display-graphic-p)
    (set-scroll-bar-mode nil)
    (tool-bar-mode 0)
    (when (eq system-type 'windows-nt)
      (menu-bar-mode 0))))

(init--with-ensure-frame-ready #'init--setup-minimal-ui)

(setq column-number-mode t)
(setq ring-bell-function'ignore)
(setq warning-minimum-level :error)

(package-initialize)
(require 'package)

(add-to-list 'package-archives '("gnu"    . "https://elpa.gnu.org/packages/") t)
(add-to-list 'package-archives '("org"    . "http://orgmode.org/elpa/") t)
(add-to-list 'package-archives '("melpa"  . "https://melpa.org/packages/") t)

(when (< emacs-major-version 30)
  (setq package-archive-priorities
	'(("gnu"    . 20)
	  ("org"    . 15)
	  ("melpa"  . 5))))

(package-refresh-contents t)

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(use-package quelpa :ensure t)
(quelpa '(quelpa-use-package
	  :fetcher git
	  :url "https://github.com/quelpa/quelpa-use-package.git"))
(require 'quelpa-use-package)

(setq custom-file
      (file-name-concat user-emacs-directory "custom.el"))
(when (file-exists-p custom-file)
  (load custom-file))

(unless (boundp 'ep3c-modules)
  (let ((modules-wildcard (file-name-concat user-emacs-directory "modules" "*.org")))
    (defcustom ep3c-modules
      (file-expand-wildcards modules-wildcard)
      "List of available EP3C modules. Disable any module by deleting it from this list"
      :type '(repeat (file :must-match nil))
      :group 'ep3c)))

(mapcar 'org-babel-load-file ep3c-modules)

(provide 'init)
;;; init.el ends here

;;; init --- Init file for Emacs
;;; Commentary: simple minimal configuration and module loading
;;; Code:
(when (display-graphic-p)
  (progn
    (set-scroll-bar-mode nil)
    (tool-bar-mode 0)))
(setq column-number-mode t)
(setq ring-bell-function 'ignore)
(setq warning-minimum-level :error)

(defconst org-settings-directory
  (file-name-concat user-emacs-directory "org-settings")
  "Directory containing 'org-mode' settings modules.")

(package-initialize)
(require 'package)

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(add-to-list 'package-archives '("org" . "http://orgmode.org/elpa/") t)
(add-to-list 'package-archives '("gnu" . "https://elpa.gnu.org/packages/") t)

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
;;; init.el

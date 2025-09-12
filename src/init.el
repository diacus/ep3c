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


(defun init/load-settings-module (file)
  "Execute 'org-babel-load-file' FILE only if file is executable."
  (when (file-executable-p file)
      (org-babel-load-file file)))

(let* ((modules-wildcard (file-name-concat user-emacs-directory
					   "modules"
					   "*.org"))
       (modules (file-expand-wildcards modules-wildcard)))
  (mapc 'init/load-settings-module modules))

(provide 'init)
;;; init.el

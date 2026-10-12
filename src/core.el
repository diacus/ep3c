;;; core.el --- Core helpers for EP3C -*- lexical-binding: t -*-
;;
;;; Commentary:
;;
;; Helpers shared by src/install.el (install time) and src/init.el
;; (runtime, from `user-emacs-directory').  Definitions only, no side
;; effects at load time.
;;
;;; Code:

(defun ep3c--module-title (module-file)
  "Read the #+TITLE: property from MODULE-FILE.
If not found, return a fallback based on the module name."
  (with-temp-buffer
    (insert-file-contents module-file)
    (goto-char (point-min))
    (if (re-search-forward "^#\\+TITLE:[ \t]*\\(.*\\)" nil t)
        (match-string 1)
      (capitalize (replace-regexp-in-string "-" " " (file-name-base module-file))))))

(defun ep3c--migrate-modules-value (value)
  "Convert VALUE to new symbol-based format if needed."
  (cond
   ((and (listp value) (symbolp (car value))) value)
   ((and (listp value) (stringp (car value)))
    (mapcar (lambda (s)
              (intern (file-name-base s)))
            value))
   (t nil)))

(defun ep3c--available-modules (modules-dir)
  "Return the list of EP3C module symbols available in MODULES-DIR."
  (mapcar #'intern
          (mapcar #'file-name-base
                  (file-expand-wildcards
                   (file-name-concat modules-dir "*.org")))))

(defun ep3c--modules-custom-type (modules-dir)
  "Generate the Customize type describing the modules in MODULES-DIR."
  `(set :greedy t
        ,@(mapcar (lambda (m)
                    (let ((module-file (expand-file-name
                                        (format "%s.org" m) modules-dir)))
                      `(const :tag ,(format "%-20s - %s"
                                            m
                                            (ep3c--module-title module-file))
                              ,m)))
                  (ep3c--available-modules modules-dir))))

(defun ep3c--valid-modules (value modules-dir)
  "Filter VALUE keeping only modules available in MODULES-DIR."
  (delq nil (mapcar (lambda (m)
                      (if (memq m (ep3c--available-modules modules-dir)) m))
                    value)))

(provide 'core)
;;; core.el ends here
;; Local Variables:
;; flycheck-disabled-checkers: (emacs-lisp-checkdoc)
;; End:
(defvar settings-file
  (if (member system-type '(ms-dos windows-nt cygwin))
      (file-name-concat (getenv "HOME") "OneDrive - Microsoft" "emacs" "settings.org")
    (file-name-concat user-emacs-directory  "settings.org"))
  "Path to the settings file")
(org-babel-load-file settings-file)

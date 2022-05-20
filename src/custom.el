(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ansi-color-faces-vector
   [default default default italic underline success warning error])
 '(ansi-color-names-vector
   ["#242424" "#e5786d" "#95e454" "#cae682" "#8ac6f2" "#333366" "#ccaa8f" "#f6f3e8"])
 '(custom-enabled-themes '(nord))
 '(custom-safe-themes
   '("37768a79b479684b0756dec7c0fc7652082910c37d8863c35b702db3f16000f8" default))
 '(lsp-java-server-install-dir "/Users/diego.guzman/opt/eclipse-jdt-server")
 '(org-agenda-files
   '("~/org/personal.org" "~/org/wizeline.org" "~/org/sunpower.org" "~/org/okr.org"))
 '(org-capture-templates
   '(("w" "Wizeline Templates")
     ("wi" "Capture an interview session" entry
      (file+headline "~/org/wizeline.org" "Interviews")
      (file "~/org/templates/wizeline-interview.txt"))
     ("wt" "TODO entry" entry
      (file+headline "~/org/wizeline.org" "Capture")
      (file "~/org/templates/todo.txt"))
     ("s" "Sunpower EDP Project")
     ("ss" "Sunpower Story from Pivotal Traker" entry
      (file+headline "~/org/sunpower.org" "Pivotal Tracker")
      (file "~/org/templates/pivotal-tracker.txt"))))
 '(org-export-backends '(ascii html icalendar latex md odt))
 '(org-refile-allow-creating-parent-nodes 'confirm)
 '(org-refile-targets '((org-agenda-files :maxlevel . 2)))
 '(org-refile-use-outline-path 'file)
 '(package-selected-packages
   '(helm-lsp which-key yasnippet flycheck projectile emojify exec-path-from-shell fzf vterm ob-http lsp-ui lsp-java lsp-ivy dap-mode csv-mode company magit ivy gradle-mode helm evil lsp-mode jq-mode nord-theme))
 '(scroll-bar-mode nil)
 '(tool-bar-mode nil)
 '(tooltip-mode nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

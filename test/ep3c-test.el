;;; ep3c-test.el --- Tests for EP3C -*- lexical-binding: t -*-
;;
;;; Commentary:
;;
;; Tests for the EP3C configuration.  Loaded by test/run.el; do not
;; invoke directly.
;;
;; Covered:
;;
;; - module integrity: every src/modules/*.org tangles into valid
;;   Emacs Lisp (replicating the tangling org-babel-load-file does
;;   at startup), and carries the house metadata (#+TITLE, #+AUTHOR,
;;   #+STARTUP: overview).
;; - symbol integrity: every house (ep3c-*) symbol the tangled
;;   modules reference is defined by the sources, so void-symbol
;;   typos in hooks or calls fail instead of only misbehaving at
;;   runtime.
;; - install smoke test: ep3c--setup installs init.el, core.el and
;;   every module into a throwaway user-emacs-directory, and the
;;   module-set validation drops unknown modules.
;; - functional vterm test: C-x C-e (vterm--edit-command-line)
;;   round-trips the shell's command line against a real /bin/bash
;;   vterm process; skipped when vterm/evil are not installed.
;;
;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'org)

(defconst ep3c-test-root
  (expand-file-name
   ".."
   (file-name-as-directory
    (file-name-directory
     (or load-file-name buffer-file-name))))
  "Repository root the tests are run against.")

(defconst ep3c-test-modules
  (directory-files
   (expand-file-name "src/modules" ep3c-test-root) t "\\.org\\'")
  "Absolute path of every EP3C module.")

;; Load the code under test.
(load-file (expand-file-name "src/install.el" ep3c-test-root))

(defun ep3c-test--tangle-module (module)
  "Tangle a copy of MODULE in a temporary directory.
Replicates the tangling `org-babel-load-file' performs when init.el
loads a module: every `emacs-lisp' code block is tangled, regardless
of per-block :tangle overrides (modules set none).  Returns the list
of tangled buffers' contents.  The temporary copy is always deleted."
  (let* ((dir (make-temp-file "ep3c-tangle-" 'directory))
         (copy (expand-file-name (file-name-nondirectory module) dir)))
    (unwind-protect
        (let (tangled)
          (copy-file module copy)
          ;; Keep org chatter ("Tangled N code blocks...") out of the
          ;; batch output; failures come through ERT, not messages.
          (cl-letf (((symbol-function 'message) #'ignore))
            (let ((org-babel-default-header-args
                   (cons '(:tangle . "yes")
                         (assq-delete-all
                          :tangle (copy-alist org-babel-default-header-args)))))
              (setq tangled (org-babel-tangle-file copy nil "emacs-lisp"))))
          (mapcar (lambda (file)
                    (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
                  tangled))
      (delete-directory dir t))))

(defun ep3c-test--elisp-valid-p (elisp)
  "Return t when ELISP is syntactically valid Emacs Lisp.
Otherwise return a description of the syntax problem."
  (with-temp-buffer
    (insert elisp)
    (emacs-lisp-mode)
    (condition-case err
        (progn
          (check-parens)
          ;; Read forms until the buffer is exhausted; balanced
          ;; parens and strings end in an `end-of-file' condition.
          (while t (read (current-buffer)))
          t)
      (end-of-file t)
      (error (format "%S" (error-message-string err))))))

(ert-deftest ep3c-test-modules-tangle-to-valid-elisp ()
  "Every module tangles without error into balanced Emacs Lisp.
All modules are checked even when some fail; the accumulated
failures are reported together at the end."
  (let (failures)
    (dolist (module ep3c-test-modules)
      (let ((tangled (ep3c-test--tangle-module module)))
        (unless (consp tangled)
          (push (format "%s: tangling produced no code blocks" module)
                failures))
        (dolist (elisp tangled)
          (let ((valid (ep3c-test--elisp-valid-p elisp)))
            (unless (eq valid t)
              (push (format "%s: invalid tangle output: %s"
                            (file-name-nondirectory module) valid)
                    failures))))))
    (should-not (nreverse failures))))

(defconst ep3c-test-house-prefix "ep3c-"
  "Prefix of the symbols the EP3C sources themselves define.")

(defconst ep3c-test-defining-forms
  '(defun defun* cl-defun defsubst defmacro defvar defvar-local
    defconst defcustom defface defalias define-minor-mode)
  "Special forms whose cadr is the symbol they define.")

(defun ep3c-test--house-symbol-p (obj)
  "Return t when OBJ is a symbol starting with the house prefix."
  (and (symbolp obj)
       (string-prefix-p ep3c-test-house-prefix (symbol-name obj))))

(defun ep3c-test--merge-house-symbols (results)
  "Merge the (REFERENCES . DEFINITIONS) pairs RESULTS into one."
  (cons (apply #'append (mapcar #'car results))
        (apply #'append (mapcar #'cdr results))))

(defun ep3c-test--house-symbols (form)
  "Return \(REFERENCES . DEFINITIONS) of the house symbols in FORM.

Definitions through the special forms in
`ep3c-test-defining-forms' (defun, defcustom, ...) register in
DEFINITIONS.  Quoted data is skipped -- a symbol in data position
(an invisibility spec tag, a :after package list) is not something
the reader can demand a definition of -- but the target of
`function' (that is, #') is and registers as a reference.  Descends
into improper tails too, so an unquoted dotted `:hook' pair's tail
symbol counts as a reference."
  (cond
   ((symbolp form)
    (cons (when (ep3c-test--house-symbol-p form) (list form)) nil))
   ((consp form)
    (let ((head (car form)))
      (cond
       ((memql head ep3c-test-defining-forms)
        (let ((rest (ep3c-test--merge-house-symbols
                     (mapcar #'ep3c-test--house-symbols (cddr form)))))
          (cons (car rest)
                (append (when (ep3c-test--house-symbol-p (cadr form))
                          (list (cadr form)))
                        (cdr rest)))))
       ((eq head 'quote) '(nil . nil))
       ((eq head 'function)
        (let ((rest (ep3c-test--house-symbols (cddr form))))
          (cons (append (when (ep3c-test--house-symbol-p (cadr form))
                          (list (cadr form)))
                        (car rest))
                (cdr rest))))
       (t
        (ep3c-test--merge-house-symbols
         (list (ep3c-test--house-symbols (car form))
               (ep3c-test--house-symbols (cdr form))))))))))

(defun ep3c-test--read-forms (elisp)
  "Read every top-level form in the string ELISP."
  (let (forms)
    (with-temp-buffer
      (insert elisp)
      (goto-char (point-min))
      ;; Reading to exhaustion ends in the `end-of-file' condition;
      ;; see `ep3c-test--elisp-valid-p'.
      (condition-case err
          (while t (push (read (current-buffer)) forms))
        (end-of-file (nreverse forms))
        (error (error "%s" (error-message-string err)))))))

(defun ep3c-test--file-forms (file)
  "Read every top-level form in the source file FILE."
  (ep3c-test--read-forms
   (with-temp-buffer
     (insert-file-contents file)
     (buffer-string))))

(ert-deftest ep3c-test-house-symbols-defined ()
  "Every house (ep3c-*) symbol the tangled code references has a definition.
Definitions and references are collected across the whole tree --
modules tangle independently at startup, so a helper may live in
core.el or another module."
  (let (defs failures)
    ;; The Elisp sources are checked too, with a per-file reference
    ;; set for the failure messages.
    (dolist (file '("src/core.el" "src/install.el" "src/init.el"))
      (let ((el (expand-file-name file ep3c-test-root)) (refs))
        (when (file-exists-p el)
          (dolist (form (ep3c-test--file-forms el))
            (let ((found (ep3c-test--house-symbols form)))
              (dolist (ref (car found)) (cl-pushnew ref refs))
              (dolist (def (cdr found)) (cl-pushnew def defs))))
          (dolist (ref refs)
            (unless (memql ref defs)
              (push (format "%s: no definition among the sources for `%s'"
                            (file-name-nondirectory el) ref)
                    failures))))))
    ;; ...and every module's tangled output.
    (dolist (module ep3c-test-modules)
      (let ((refs))
        (dolist (elisp (ep3c-test--tangle-module module))
          (let ((found (ep3c-test--merge-house-symbols
                        (mapcar #'ep3c-test--house-symbols
                                (ep3c-test--read-forms elisp)))))
            (dolist (ref (car found)) (cl-pushnew ref refs))
            (dolist (def (cdr found)) (cl-pushnew def defs))))
        ;; A reference only fails when nothing defines it anywhere.
        (dolist (ref refs)
          (unless (memql ref defs)
            (push (format "%s: no definition among the sources for `%s'"
                          (file-name-nondirectory module) ref)
                  failures)))))
    (should-not (nreverse failures))))

(ert-deftest ep3c-test-modules-have-title ()
  "Every module declares a non-empty #+TITLE: property."
  (dolist (module ep3c-test-modules)
    (ert-info ((format "Module %s" module))
      (with-temp-buffer
        (insert-file-contents module)
        (goto-char (point-min))
        (should (re-search-forward
                 "^#\\+TITLE:[ \t]*\\(.+\\)$" nil t))))))

(ert-deftest ep3c-test-modules-have-author ()
  "Every module declares a non-empty #+AUTHOR: property.

Used by install.el for the Customize display of `ep3c-modules'."
  (dolist (module ep3c-test-modules)
    (ert-info ((format "Module %s" module))
      (with-temp-buffer
        (insert-file-contents module)
        (goto-char (point-min))
        (should (re-search-forward
                 "^#\\+AUTHOR:[ \t]*\\(.+\\)$" nil t))))))

(ert-deftest ep3c-test-modules-startup-overview ()
  "Every module starts up with folded headlines (overview)."
  (dolist (module ep3c-test-modules)
    (ert-info ((format "Module %s" module))
      (with-temp-buffer
        (insert-file-contents module)
        (goto-char (point-min))
        (should (re-search-forward
                 "^#\\+STARTUP:.*\\boverview\\b" nil t))))))

(ert-deftest ep3c-test-install-smoke ()
  "Run the installer into a throwaway user-emacs-directory.

Checks that init.el, core.el and every module end up installed and
that the module-set validation keeps only known modules."
  (let ((user-emacs-directory (file-name-as-directory
                               (make-temp-file "ep3c-install-" 'directory)))
        (default-directory ep3c-test-root))
    (unwind-protect
        (progn
          ;; Keep the installer's per-module progress lines out of the
          ;; batch output; failures come through ERT, not messages.
          (cl-letf (((symbol-function 'message) #'ignore))
            (ep3c--setup))
          (should (file-exists-p (expand-file-name "init.el" user-emacs-directory)))
          (should (file-exists-p (expand-file-name "core.el" user-emacs-directory)))
          (should (equal
                   (sort (mapcar #'file-name-nondirectory
                                 (directory-files
                                  (expand-file-name "modules" user-emacs-directory)
                                  t "\\.org\\'"))
                         #'string<)
                   (sort (mapcar #'file-name-nondirectory ep3c-test-modules)
                         #'string<)))
          ;; The :set setter migrates legacy string values to symbols...
          (ep3c--set-modules 'ep3c-modules '("evil.org" "yaml.org"))
          (should (equal (default-value 'ep3c-modules) '(evil yaml)))
          ;; ...and drops modules that are not available.
          (ep3c--set-modules 'ep3c-modules '(evil bogus-module yaml))
          (should (equal (default-value 'ep3c-modules) '(evil yaml))))
      (delete-directory user-emacs-directory t))))

;;; Functional test -- C-x C-e in vterm edits the shell command line
;;;
;;; Unlike the tests above this one exercises a real vterm process, so
;;; it needs the runtime packages (vterm, evil) installed for this
;;; user and a /bin/bash.  When any of them is missing it skips; a
;;; bare CI environment is therefore unaffected.

(defun ep3c-test--put-elpa-on-load-path (packages)
  "Extend `load-path' with the installed directories of PACKAGES.
Globs the subdirectories of `package-user-dir' by package name, in
the same environment the user's Emacs runs its daemons in."
  (require 'package)
  (when (file-directory-p package-user-dir)
    (dolist (package packages)
      (dolist (dir (directory-files
                    package-user-dir t
                    (format "\\`%s\\(?:-[0-9.]+\\)?\\'"
                            (regexp-quote (symbol-name package)))))
        (when (file-directory-p dir)
          (add-to-list 'load-path dir))))))

(defun ep3c-test--vterm-functional-ready-p ()
  "Return t when the functional vterm test can run on this machine.
Puts the runtime packages on the `load-path' as a side effect, so
the callers only require what fails to load when this returns t."
  (and (executable-find "/bin/bash")
       (progn
         (ep3c-test--put-elpa-on-load-path
          ;; multi-vterm only because the tangled shell module
          ;; mentions it; the actual exercise needs vterm and evil.
          '(vterm evil multi-vterm))
         (and (require 'vterm nil t)
              (require 'use-package nil t)
              (require 'evil nil t)))))

(defvar ep3c-test--vterm-module-file nil
  "Temporary file the tangled shell.org module was loaded from.")

(defun ep3c-test--load-vterm-module ()
  "Load the tangled shell.org module once into the suite's Emacs.
The runtime pieces are already ensured by
`ep3c-test--vterm-functional-ready-p', which the test calls first."
  (unless ep3c-test--vterm-module-file
    (setq ep3c-test--vterm-module-file
          (make-temp-file "ep3c-vterm-" nil ".el"))
    (with-temp-file ep3c-test--vterm-module-file
      (insert
       (mapconcat #'identity
                  (ep3c-test--tangle-module
                   (expand-file-name "src/modules/shell.org" ep3c-test-root))
                  "\n")))
    (load ep3c-test--vterm-module-file nil t)))

(defun ep3c-test--vterm-open ()
  "Start a /bin/bash vterm process in a new buffer; return the buffer."
  (let ((buffer (generate-new-buffer " *ep3c-test-vterm*")))
    (with-current-buffer buffer
      (let ((vterm-shell "/bin/bash"))
        (vterm-mode)))
    buffer))

(defun ep3c-test--vterm-wait (buffer pattern)
  "Wait up to ten seconds for the command line in BUFFER to match PATTERN.
The shell output and redisplay settle asynchronously, so the
waiters sleep instead of polling in a tight loop; they signal when
the match never appears."
  (let ((deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (not (ignore-errors
                       (with-current-buffer buffer
                         (string-match-p pattern
                                         (vterm--edit-read-line))))))
      (sleep-for 0.2))
    (with-current-buffer buffer
      (should (string-match-p pattern (vterm--edit-read-line))))))

(defun ep3c-test--vterm-find-edit ()
  "Return the youngest *vterm edit* buffer, or nil when none live."
  (cl-find "*vterm edit " (buffer-list)
           :test #'string-prefix-p :key #'buffer-name))

(ert-deftest ep3c-test-vterm-edit-command-line ()
  "Round-trip `vterm--edit-command-line' with a real shell.

Checks against a live /bin/bash in vterm: the C-x C-e binding in
the mode map, prompt-excluded extraction, the entry point wiring
(fresh edit buffer backed by this vterm, no frame in batch mode),
accepting an edit on the prompt, and that aborting leaves the
prompt untouched."

  (skip-unless (ep3c-test--vterm-functional-ready-p))
  (ep3c-test--load-vterm-module)
  (let* ((vterm-buffer (ep3c-test--vterm-open))
         (edit-buffer nil))
    (unwind-protect
        (with-current-buffer vterm-buffer
          ;; The feature binding shadows the global eval-last-sexp.
          (should (eq (lookup-key vterm-mode-map (kbd "C-x C-e"))
                      'vterm--edit-command-line))
          ;; A fresh prompt edits as an empty line...
          (should (string= (vterm--edit-read-line) ""))
          ;; ...and whatever is typed is extracted, prompt left out
          ;; (this works without any shell prompt tracking).
          (vterm-insert "echo hello world")
          (ep3c-test--vterm-wait vterm-buffer (regexp-quote
                                               "echo hello world"))
          (should (string= (vterm--edit-read-line) "echo hello world"))
          ;; The entry point wires a fresh edit buffer back to this
          ;; vterm; batch mode has no graphic display, so no frame.
          (vterm--edit-command-line)
          (setq edit-buffer (ep3c-test--vterm-find-edit))
          (should (bufferp edit-buffer))
          (should (eq (buffer-local-value 'vterm--edit-source edit-buffer)
                      vterm-buffer))
          (should (null (buffer-local-value 'vterm--edit-frame
                                            edit-buffer)))
          (with-current-buffer edit-buffer
            (should (where-is-internal 'vterm--edit-accept
                                       (list (current-local-map))))
            (should (where-is-internal 'vterm--edit-abort
                                       (list (current-local-map))))
            (erase-buffer)
            (insert "echo edited by the suite\n")
            (vterm--edit-accept))
          ;; The prompt carries the edit without the trailing newline.
          (ep3c-test--vterm-wait vterm-buffer (regexp-quote
                                               "echo edited by the suite"))
          (with-current-buffer vterm-buffer
            (should (string= (vterm--edit-read-line)
                             "echo edited by the suite")))
          ;; Accepting kills the edit buffer.
          (should (null (buffer-live-p edit-buffer)))
          ;; Aborting leaves the prompt exactly as it was.
          (with-current-buffer vterm-buffer
            (vterm-send-key "a" nil nil t)
            (vterm-send-key "k" nil nil t)
            (sleep-for 0.5)
            (vterm-insert "echo keep me")
            (ep3c-test--vterm-wait vterm-buffer (regexp-quote
                                                 "echo keep me"))
            (vterm--edit-command-line))
          (setq edit-buffer (ep3c-test--vterm-find-edit))
          (should (bufferp edit-buffer))
          (with-current-buffer edit-buffer
            (erase-buffer)
            (insert "must never reach the prompt")
            (vterm--edit-abort))
          (sleep-for 0.5)
          (with-current-buffer vterm-buffer
            (should (string= (vterm--edit-read-line) "echo keep me")))
          (should (null (buffer-live-p edit-buffer))))
      (when (buffer-live-p edit-buffer)
        (with-current-buffer edit-buffer
          (remove-hook 'kill-buffer-hook #'vterm--edit-close-frame))
        (kill-buffer edit-buffer))
      (when (buffer-live-p vterm-buffer)
        (kill-buffer vterm-buffer)))))

(provide 'ep3c-test)
;;; ep3c-test.el ends here
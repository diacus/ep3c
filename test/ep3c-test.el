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
;; - key binding integrity: every function a module binds to a key
;;   that the modules define themselves carries an (interactive)
;;   form, so a binding to a plain function (a `commandp' failure at
;;   runtime) cannot ship.
;; - comment toggle: `ep3c-comment-toggle' (the global `SPC ;' /
;;   `C-c ;' comment chord) resolves the comment syntax of the
;;   buffer's major mode, including org-mode, and toggles the
;;   region when one is active, the current line otherwise.
;; - no raw `evil-define-key' macro calls outside evil.org: the
;;   macro only expands against a loaded evil, and a call reached
;;   through a hook lambda crashes every buffer the hook fires for
;;   when evil is disabled (the orgmode.org terminal-TAB incident).
;; - README leader notation: keybinding tables document leader
;;   chords as =LEADER x y= (the placeholder for
;;   `ep3c-evil-leader'/`ep3c-non-evil-leader'), never literally as
;;   =SPC x y=.
;; - leader-key tree conventions: the leader `o' subtree is bound
;;   by orgmode.org only (haskell's old `LEADER o r' REPL binding
;;   predates the org-only convention), and language modules
;;   override leaves of the `p' run subtree inside their modes
;;   (`LEADER p r r' = the language's REPL).
;; - install smoke test: ep3c--setup installs init.el, core.el and
;;   every module into a throwaway user-emacs-directory, and the
;;   module-set validation drops unknown modules.
;; - functional shell tests: C-x C-e round-trips the shell's command
;;   line against a real /bin/bash in a vterm, in a term (char and
;;   line mode), in an eshell (no pty needed) and in an comint shell;
;;   skipped when vterm/evil are not installed.
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

(defun ep3c-test--visit-forms (fn form)
  "Call FN on FORM, then recursively on its car and its cdr.
FORM may be an atom, a cons, or an improper list."
  (funcall fn form)
  (when (consp form)
    (ep3c-test--visit-forms fn (car form))
    (ep3c-test--visit-forms fn (cdr form))))

(defun ep3c-test--find-bindings (form)
  "Return the (FN . KEY-STRING) pairs the form FORM binds to keys.

Recognizes `evil-define-key', `ep3c-define-key' (leader-relative
keys), `global-set-key', `define-key', `local-set-key' and the
use-package `:bind'/`:bind-keymap'/`:map' plists.  The KEY-STRING
is nil for keyspecs this reader does not understand (for example
an event vector); those pairs are dropped."
  (let (out)
    (cl-labels
        ((do-bind (keyform defform)
           (let ((fn (pcase defform
                       ((pred symbolp) defform)
                       ((or `(quote ,sym) `(function ,sym))
                        (and (symbolp sym) sym))))
                 (key (pcase keyform
                        ((pred stringp) keyform)
                        (`(kbd ,k) (and (stringp k) k)))))
             (when (and fn key)
               (push (cons fn key) out))))
         (bind-plist (value)
           (cond
            ((and (consp value) (eq (car value) :map))
             (dolist (pair (cddr value)) (bind-plist pair)))
            ((and (consp value) (stringp (car value)))
             (do-bind (car value) (cdr value)))
            ((consp value)
             (dolist (sub value) (bind-plist sub)))))
         (visit (f)
           (pcase f
             (`(evil-define-key . ,args)
              ;; Drop the STATE and MAP arguments.
              (setq args (cddr args))
              ;; Alternate (KEYSPEC . DEF) pairs.
              (while (cadr args)
                (do-bind (car args) (cadr args))
                (setq args (cddr args))))
             (`(ep3c-define-key . ,args)
              ;; Drop the STATE and MAP arguments.
              (setq args (cddr args))
              ;; Alternate (KEYSPEC . DEF) pairs.
              (while (cadr args)
                (do-bind (car args) (cadr args))
                (setq args (cddr args))))
             (`(global-set-key ,key ,def) (do-bind key def))
             (`(local-set-key ,key ,def) (do-bind key def))
             (`(define-key . ,_)
              (when (>= (safe-length f) 4)
                (do-bind (nth 2 f) (nth 3 f))))
             (`(use-package ,_ . ,tail)
              (let ((rest (cdr tail)))
                (while (keywordp (car-safe rest))
                  (when (memq (car rest) '(:bind :bind-keymap :map))
                    (bind-plist (cadr rest)))
                  (setq rest (cddr rest))))
              ;; The body may nest its own binding forms.
              (dolist (sub tail) (visit sub)))
             (_ (when (consp f)
                  (visit (car f))
                  (visit (cdr f)))))))
      (visit form)
      (nreverse out))))

(ert-deftest ep3c-test-bound-functions-are-commands ()
  "Every module-defined function bound to a key is an interactive command.

A binding to a function without an (interactive) form fails at
command execution with `wrong-type-argument (commandp ...)'.  Only
functions the modules define themselves are checked: for
third-party commands, commandness belongs to the package."
  (let ((commands (make-hash-table :test #'eq))
        bindings failures)
    ;; Definitions first (a binding may live in a module other than
    ;; the one that defines its target function).
    (dolist (module ep3c-test-modules)
      (dolist (elisp (ep3c-test--tangle-module module))
        (dolist (form (ep3c-test--read-forms elisp))
          (ep3c-test--visit-forms
           (lambda (f)
             (when (and (memql (car-safe f)
                               '(defun defun* cl-defun defsubst))
                        (symbolp (cadr f)))
               (puthash (cadr f)
                        (memq 'interactive (mapcar #'car-safe (cddr f)))
                        commands)))
           form))))
    ;; Then the key bindings, annotated with the module that binds.
    (dolist (module ep3c-test-modules)
      (dolist (elisp (ep3c-test--tangle-module module))
        (dolist (form (ep3c-test--read-forms elisp))
          (dolist (binding (ep3c-test--find-bindings form))
            (push (cons (file-name-nondirectory module) binding)
                  bindings)))))
    ;; A bound function the modules define must carry (interactive).
    (dolist (entry bindings)
      (pcase-let ((`(,module . (,fn . ,key)) entry))
        (let ((state (gethash fn commands 'absent)))
          (when (and (listp state) (not state))
            (push (format "%s: `%s' is bound `%s', which is not a \
command -- add (interactive) to its defun"
                          module key fn)
                  failures)))))
    (should-not (nreverse failures))))

(ert-deftest ep3c-test-define-key-plain-regime ()
  "Multi-pair `ep3c-define-key' calls take in the plain regime.

`define-key' is not variadic, and a single-pair smoke would hide an
arity bug -- one pair is exactly `define-key's three arguments --
so this binds several pairs per call, in the leader map and in a
mode map.  The evil branch needs the evil package, which the
offline suite cannot install; it is verified by hand, as recorded
in ERT-SUITE-LIMITATIONS.md."
  (unless (fboundp 'ep3c-define-key)
    (load-file (expand-file-name "src/core.el" ep3c-test-root)))
  (ep3c-define-key 'normal 'global
    "j" 'counsel-git-grep
    "k" 'counsel-ag
    "t v" #'eshell)
  (should (eq (lookup-key ep3c-leader-map (vector ?j)) 'counsel-git-grep))
  (should (eq (lookup-key ep3c-leader-map (vector ?k)) 'counsel-ag))
  (should (eq (lookup-key ep3c-leader-map (vector ?t ?v)) #'eshell))
  (should (eq (lookup-key global-map (vector 3)) ep3c-leader-map))
  (let ((mode-map (make-sparse-keymap)))
    (ep3c-define-key '(normal visual) mode-map
      "c c" #'haskell-compile
      "o r" 'haskell-interactive-bring)
    (should (eq (lookup-key mode-map (vector 3 ?c ?c)) #'haskell-compile))
    (should (eq (lookup-key mode-map (vector 3 ?o ?r))
                'haskell-interactive-bring))))

(ert-deftest ep3c-test-comment-toggle ()
  "`ep3c-comment-toggle' resolves the comment syntax of the mode.

The command is the global comment chord (`SPC ;' with evil, `C-c ;'
without it), so it must adapt to the major mode it runs in:
`comment-start' and friends are buffer-local and org-mode swaps in
its own `org-comment-or-uncomment-region'.  The defun is lifted out
of prog-mode.org's tangle (the rest of the module wants packages),
and both branches are exercised: the current line without a region,
and a selection with one.  A cursor parked on the trailing empty
line must toggle the real last line.  Toggle/untoggle round-trips
are asserted rather than exact paddings, which `comment-add' owns."
  (let ((defun-form))
    (catch 'found
      (dolist (elisp (ep3c-test--tangle-module
                      (expand-file-name "src/modules/prog-mode.org"
                                        ep3c-test-root)))
        (dolist (form (ep3c-test--read-forms elisp))
          (when (and (eq (car-safe form) 'defun)
                     (eq (cadr form) 'ep3c-comment-toggle))
            (setq defun-form form)
            (throw 'found t)))))
    (should defun-form)
    (eval defun-form t)
    ;; Line branch, in a mode where comment-start is ";".
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "plain\n")
      (let ((original (buffer-string)))
        (goto-char (point-max))
        (call-interactively #'ep3c-comment-toggle)
        (should-not (string= (buffer-string) original))
        (should (string-match-p "\\`\;.*plain" (buffer-string)))
        (call-interactively #'ep3c-comment-toggle)
        (should (string= (buffer-string) original))))
    ;; Org mode resolves to its `#' syntax.
    (with-temp-buffer
      (org-mode)
      (insert "plain\n")
      (let ((original (buffer-string)))
        (call-interactively #'ep3c-comment-toggle)
        (should (string-match-p "\\`#" (buffer-string)))
        (call-interactively #'ep3c-comment-toggle)
        (should (string= (buffer-string) original))))
    ;; Line branch again, with the cursor on the trailing empty line
    ;; a down-motion or C-e in evil can leave it on.
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "plain\n")
      (goto-char (point-max))
      (call-interactively #'ep3c-comment-toggle)
      (should (string-match-p "plain" (buffer-string))))
    ;; Region branch.  `transient-mark-mode' is forced on globally:
    ;; in batch, a `push-mark' activation inside a fresh temporary
    ;; buffer does not survive `point' motion, and the dispatcher
    ;; would (correctly) take the line branch.
    (transient-mark-mode 1)
    (with-temp-buffer
      (emacs-lisp-mode)
      (insert "one\ntwo\n")
      (let ((original (buffer-string)))
        (goto-char (point-min))
        (push-mark nil 'nomessage 'activate)
        (forward-line 2)
        (call-interactively #'ep3c-comment-toggle)
        (should (string-match-p ";;? one" (buffer-string)))
        (should (string-match-p ";;? two" (buffer-string)))
        (should-not (string= (buffer-string) original))
        (call-interactively #'ep3c-comment-toggle)
        (should (string= (buffer-string) original))))))

(ert-deftest ep3c-test-modules-do-not-call-evil-define-key-macro ()
  "No module outside evil.org calls the `evil-define-key' macro.

The incident that motivates this check is invisible to an offline
suite: orgmode.org's terminal-TAB hook called the macro from an
anonymous hook lambda, which fires for every org-mode buffer the
daemon creates before a GUI frame exists -- and crashes with
`void-function evil-define-key' when the evil.org module is
disabled.  House rule: leader bindings go through
`ep3c-define-key'; direct mode-map bindings in an evil-regime
runtime path use the plain-function form `evil-define-key*'
explicitly guarded by `(featurep 'evil)'.  The macro itself is
reserved to evil.org, which only loads with evil."
  (let (failures)
    (dolist (module ep3c-test-modules)
      (unless (string-suffix-p "evil.org" module)
        (dolist (elisp (ep3c-test--tangle-module module))
          (dolist (form (ep3c-test--read-forms elisp))
            (ep3c-test--visit-forms
             (lambda (f)
               (when (eq (car-safe f) 'evil-define-key)
                 (push (format "%s: raw `evil-define-key' call -- use \
`ep3c-define-key' for leader bindings, or `evil-define-key*' under \
a `(featurep 'evil)' guard for direct ones"
                               (file-name-nondirectory module))
                       failures)))
             form)))))
    (should-not (nreverse failures))))

(ert-deftest ep3c-test-readme-leader-notation ()
  "README.org lists leader chords with the LEADER placeholder.

The leader is `ep3c-evil-leader' (default SPC) with the evil
module and `ep3c-non-evil-leader' (default C-c) without it, so no
keybinding documentation can say \"SPC\" unconditionally.  The
README declares the convention once (the intro names both
defcustoms and states that =LEADER x y= means the regime's leader)
and every leader chord in a table is written =LEADER x y=.  A
literal =SPC- table cell here means a newly documented chord
skipped the convention."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "README.org" ep3c-test-root))
    (goto-char (point-min))
    (let (failures)
      ;; (a) every leader key cell in a table uses the placeholder.
      (while (search-forward-regexp "^| *=SPC" nil t)
        (push (format "README:%d: literal =SPC- key cell -- use =LEADER"
                      (line-number-at-pos (match-beginning 0)))
              failures))
      ;; (b) both regimes' defcustoms are named.
      (dolist (var '("ep3c-evil-leader" "ep3c-non-evil-leader"))
        (goto-char (point-min))
        (unless (search-forward var nil t)
          (push (format "README does not mention `%s'" var) failures)))
      ;; (c) the convention itself is declared.
      (goto-char (point-min))
      (unless (search-forward-regexp "=LEADER x y=" nil t)
        (push "README declares no =LEADER x y= convention" failures))
      (should-not (nreverse failures)))))

(ert-deftest ep3c-test-leader-o-is-org-only ()
  "The leader's `o' subtree is org's, everywhere but orgmode.org.

The `LEADER o r' haskell REPL binding predates the org-only
convention: the module carried the old \"o = open\" meaning with
no documentation anywhere, and nothing caught the drift -- the
README could say =SPC o= is org only while the key still lived on
the leader in a haskell buffer.  This test greps every module's
bindings (orgmode.org excepted) for the `o' subtree: leader-
relative keys straight out of `ep3c-define-key' (\"o r\", \"o c\")
and direct chords (kbd \"SPC o ...\", \"C-c o ...\")."
  (let (failures)
    (dolist (module ep3c-test-modules)
      (unless (string-suffix-p "orgmode.org" module)
        (dolist (elisp (ep3c-test--tangle-module module))
          (dolist (form (ep3c-test--read-forms elisp))
            (dolist (binding (ep3c-test--find-bindings form))
              (let ((key (cdr binding)))
                (when (and (stringp key)
                           (or (string-match-p "\\`o[ \\t]" key)
                               (string-match-p "\\`SPC[ ]+o[ \\t]" key)
                               (string-match-p "\\`C-c[ ]+o[ \\t]" key)))
                  (push (format "%s: binding `%s' on key %S -- the \
leader `o' subtree belongs to orgmode.org"
                                (file-name-nondirectory module)
                                (car binding) key)
                        failures))))))))
    (should-not (nreverse failures))))

(defun ep3c-test--quote-deref (x)
  "Unwrap every QUOTE wrapper off X (returns X when not quoted).
`ep3c-define-key' takes its arguments as quoted symbols or quoted
lists, so the tangle reads a (quote ...) form on top."
  (while (and (consp x) (eq (car x) 'quote))
    (setq x (cadr x)))
  x)

(defun ep3c-test--scan-forms (form)
  "Every `ep3c-define-key' call node anywhere inside FORM.
Walks cons cells CAR and CDR recursively: dotted lists are common
in tangled code (alist entries, `use-package' :hook pairs), and
recursing on both cons fields is the only way to bottom out on
every shape.  Recursion depth is bounded by cons-cell count per
branch -- module lists are a handful of elements deep."
  (cond
   ((not (consp form)) ())
   ((eq (car form) 'ep3c-define-key) (list form))
   (t (append (ep3c-test--scan-forms (car form))
              (ep3c-test--scan-forms (cdr form))))))

(ert-deftest ep3c-test-global-leader-states ()
  "Global leader bindings live in evil normal and visual states, only.

The (normal visual) policy keeps the leader uniform across the two
states whose keys are commands.  `emacs' state is deliberately out
of it: there `SPC' is a literal space, so a global SPC-prefixed
tree turns prose typing into undefined-prefix aborts in the
buffers evil holds in emacs state (Custom, calc, ediff,
debugger-mode, gdb-*, ...).  Where a mode's buffers genuinely want
the leader keys in emacs state, the binding belongs on that mode's
map -- dap's (normal visual emacs) call on `dap-mode-map' is the
one in-house case; mode-map calls are all out of this check's
scope.  For every `ep3c-define-key' form whose map is 'global: a
state list drawn from normal/visual/emacs must be exactly
(normal visual); any other state (treemacs.org's `treemacs`-state
rebind, say) is by construction a mode-state binding of its own
and passes."
  (let ((failures ()))
    (dolist (module ep3c-test-modules)
      (dolist (form (apply #'append
                           (mapcar #'ep3c-test--read-forms
                                   (ep3c-test--tangle-module module))))
        (dolist (call (ep3c-test--scan-forms form))
          (pcase call
            (`(ep3c-define-key ,raw-states ,map . ,_rest)
             (when (eq (ep3c-test--quote-deref map) 'global)
               (let ((states (ep3c-test--quote-deref raw-states)))
                 (when (and (listp states)
                            (cl-every (lambda (s)
                                        (memq s '(normal visual emacs)))
                                      states))
                   (unless (and (= 2 (length states))
                                (memq 'normal states)
                                (memq 'visual states))
                     (push (format "%s: 'global `ep3c-define-key' with state(s) %S -- the policy is (normal visual); emacs state only via mode maps (see dap)"
                                   (file-name-nondirectory module)
                                   states)
                           failures))))))))))
    (should-not failures)))

(defun ep3c-test--leader-chords ()
  "Every leader-relative key `ep3c-define-key' binds, as SPC-prefixed chords.
Only `ep3c-define-key' forms count: their keys are leader-relative
by contract.  Raw `define-key'/`global-set-key' chords are the
non-leader surface (README tables them separately) and are not
collected here."
  (let (chords)
    (dolist (module ep3c-test-modules)
      (dolist (elisp (ep3c-test--tangle-module module))
        (dolist (form (ep3c-test--read-forms elisp))
          (dolist (call (ep3c-test--scan-forms form))
            (let ((args (cddr call)))
              (while (and (cadr args) (stringp (car args)))
                (cl-pushnew (concat "SPC " (car args)) chords
                            :test #'equal)
                (setq args (cddr args))))))))
    chords))

(ert-deftest ep3c-test-readme-documents-leader-bindings ()
  "Every leader chord the modules bind has a =LEADER …= row in README.
Keybinding tables drift quietly: a chord added to a module is
invisible to anyone reading the README only.  Chords collected by
`ep3c-test--leader-chords' must each appear in the README as
=LEADER key=."
  (let ((readme (with-temp-buffer
                  (insert-file-contents
                   (expand-file-name "README.org" ep3c-test-root))
                  (buffer-string)))
        missing)
    (dolist (chord (ep3c-test--leader-chords))
      (let ((row (concat "=LEADER " (substring chord 4) "=")))
        (unless (string-search row readme)
          (push (format "leader chord %S has no README row %S" chord row)
                missing))))
    (should-not missing)))

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

;;; Functional tests -- C-x C-e edits the shell command line
;;;
;;; Unlike the tests above these exercise real shell processes, so
;;; they need the shell-edit package as installed by quelpa for this
;;; user (the editor is not vendored in this repo; the suite exercises
;;; the installed package), vterm for the vterm test, and a
;;; /bin/bash.  When any of them is missing it skips; a bare CI
;;; environment is therefore unaffected.

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

(defun ep3c-test--shell-ready-p ()
  "Return t when the functional shell tests can run on this machine.
Puts the runtime packages on the `load-path' and requires them as
a side effect; the callers only skip when this returns nil."
  (and (executable-find "/bin/bash")
       (progn
         (ep3c-test--put-elpa-on-load-path '(vterm shell-edit))
         (and (require 'vterm nil t)
              (require 'shell-edit nil t)))))

(defun ep3c-test--vterm-open ()
  "Start a /bin/bash vterm process in a new buffer; return the buffer.
Rests only when the shell has drawn its first prompt: driving the
readline bindings earlier sends keys the shell has not asked for
yet, and the redraw race that follows is the one flake that
matters."
  (let ((buffer (generate-new-buffer " *ep3c-test-vterm*"))
        (deadline (+ (float-time) 10)))
    (with-current-buffer buffer
      (let ((vterm-shell "/bin/bash"))
        (vterm-mode)))
    (while (and (< (float-time) deadline)
                (<= (buffer-size buffer) 40))
      (sleep-for 0.2))
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
                                         (shell-edit-vterm-read-line))))))
      (sleep-for 0.2))
    (with-current-buffer buffer
      (should (string-match-p pattern (shell-edit-vterm-read-line))))))

(defun ep3c-test--eshell-wait-prompt (buffer)
  "Wait up to ten seconds until the eshell BUFFER accepts input.
The readiness predicate is `shell-edit--eshell-prompting-p' itself --
the prompt on the buffer's tail is what the feature needs."
  (let ((deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (not (with-current-buffer buffer
                       (shell-edit--eshell-prompting-p))))
      (sleep-for 0.2))
    (with-current-buffer buffer
      (should (shell-edit--eshell-prompting-p)))))

(defun ep3c-test--shell-find-edit ()
  "Return the young *shell edit* buffer, or nil when none live."
  (cl-find "*shell edit " (buffer-list)
           :test #'string-prefix-p :key #'buffer-name))

(ert-deftest ep3c-test-vterm-edit-command-line ()
  "Round-trip `shell-edit-vterm' with a real shell.

Checks against a live /bin/bash in vterm: the C-x C-e binding in
the mode map, prompt-excluded extraction, the entry point wiring
(fresh edit buffer backed by this vterm, no frame in batch mode),
accepting an edit on the prompt, and that aborting leaves the
prompt untouched."

  (skip-unless (ep3c-test--shell-ready-p))
  (let* ((vterm-buffer (ep3c-test--vterm-open))
         (edit-buffer nil))
    (unwind-protect
        (with-current-buffer vterm-buffer
          ;; The feature binding shadows the global eval-last-sexp.
          (should (eq (lookup-key vterm-mode-map (kbd "C-x C-e"))
                      'shell-edit-vterm))
          ;; A fresh prompt edits as an empty line...
          (should (string= (shell-edit-vterm-read-line) ""))
          ;; ...and whatever is typed is extracted, prompt left out
          ;; (this works without any shell prompt tracking).
          (vterm-insert "echo hello world")
          (ep3c-test--vterm-wait vterm-buffer (regexp-quote
                                               "echo hello world"))
          (should (string= (shell-edit-vterm-read-line) "echo hello world"))
          ;; The entry point wires a fresh edit buffer back to this
          ;; vterm; batch mode has no graphic display, so no frame.
          (shell-edit-vterm)
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (should (eq (buffer-local-value 'shell-edit--source edit-buffer)
                      vterm-buffer))
          (should (null (buffer-local-value 'shell-edit--frame
                                            edit-buffer)))
          (with-current-buffer edit-buffer
            (should (where-is-internal 'shell-edit-accept
                                       (list (current-local-map))))
            (should (where-is-internal 'shell-edit-abort
                                       (list (current-local-map))))
            (erase-buffer)
            (insert "echo edited by the suite\n")
            (shell-edit-accept))
          ;; The prompt carries the edit without the trailing newline.
          (ep3c-test--vterm-wait vterm-buffer (regexp-quote
                                               "echo edited by the suite"))
          (with-current-buffer vterm-buffer
            (should (string= (shell-edit-vterm-read-line)
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
            (shell-edit-vterm))
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (with-current-buffer edit-buffer
            (erase-buffer)
            (insert "must never reach the prompt")
            (shell-edit-abort))
          (sleep-for 0.5)
          (with-current-buffer vterm-buffer
            (should (string= (shell-edit-vterm-read-line) "echo keep me")))
          (should (null (buffer-live-p edit-buffer))))
      (when (buffer-live-p edit-buffer)
        (with-current-buffer edit-buffer
          (remove-hook 'kill-buffer-hook #'shell-edit--close-frame))
        (kill-buffer edit-buffer))
      (when (buffer-live-p vterm-buffer)
        (kill-buffer vterm-buffer)))))

(ert-deftest ep3c-test-eshell-edit-command-line ()
  "Round-trip `shell-edit-eshell' with a real eshell.
Unlike the vterm test this needs no pty -- eshell is a Lisp
interpreter -- but it still loads the shell-edit package under
test, so it rides on the same readiness check.  Checks the C-x C-e binding,
the marker-based extraction, the edit buffer wiring, accepting an
edit on the prompt (which then runs through RET), the guard
against editing while a command runs, and that aborting leaves
the input intact."

  (skip-unless (ep3c-test--shell-ready-p))
  ;; eshell is required before let-binding `eshell-buffer-name':
  ;; in this lexical-binding file the let would otherwise capture
  ;; the variable lexically, and the defcustom inside `(eshell)'
  ;; then errors with "Defining as dynamic an already lexical var".
  (require 'eshell)
  (let* ((eshell-buffer (let ((eshell-buffer-name " *ep3c-test-eshell*"))
                          (eshell)))
         (edit-buffer nil))
    (unwind-protect
        (with-current-buffer eshell-buffer
          ;; The feature binding shadows the global eval-last-sexp.
          (should (eq (lookup-key eshell-mode-map (kbd "C-x C-e"))
                      'shell-edit-eshell))
          ;; A fresh prompt has an empty pending input...
          (ep3c-test--eshell-wait-prompt eshell-buffer)
          (should (string= (shell-edit-eshell-read-line) ""))
          ;; ...and typing lands in it, prompt excluded.
          (goto-char (point-max))
          (insert "echo hello from eshell")
          (should (string= (shell-edit-eshell-read-line)
                           "echo hello from eshell"))
          ;; The edit buffer is wired back to this eshell buffer.
          (shell-edit-eshell)
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (should (eq (buffer-local-value 'shell-edit--source edit-buffer)
                      eshell-buffer))
          (should (null (buffer-local-value 'shell-edit--frame
                                            edit-buffer)))
          (with-current-buffer edit-buffer
            (should (where-is-internal 'shell-edit-accept
                                       (list (current-local-map))))
            (should (where-is-internal 'shell-edit-abort
                                       (list (current-local-map))))
            (erase-buffer)
            (insert "echo edited in eshell")
            (shell-edit-accept))
          ;; The prompt now carries the edit, and pressing RET runs
          ;; it: the put-back left a submittable line.
          (with-current-buffer eshell-buffer
            (goto-char (point-max))
            (should (string= (shell-edit-eshell-read-line)
                             "echo edited in eshell"))
            (funcall (key-binding "\r"))
            ;; Wait for the command's own output to land in the
            ;; buffer, and the fresh prompt afterwards.
            (let ((deadline (+ (float-time) 10)))
              (while (and (< (float-time) deadline)
                          (not (and (string-match-p "edited in eshell"
                                                    (buffer-string))
                                    (shell-edit--eshell-prompting-p))))
                (sleep-for 0.2))
              (should (string-match-p "edited in eshell" (buffer-string)))
              (should (shell-edit--eshell-prompting-p))))
          (should (null (buffer-live-p edit-buffer)))
          ;; Editing is refused while a command runs: while eshell
          ;; is busy the pending input region is empty and
          ;; unprompted, and the next prompt only appears once the
          ;; command completes.
          (with-current-buffer eshell-buffer
            (goto-char (point-max))
            (insert "sleep 2")
            (funcall (key-binding "\r"))
            (should-error (shell-edit-eshell)
                          :type 'user-error)
            (sleep-for 2.5)
            (ep3c-test--eshell-wait-prompt eshell-buffer))
          ;; Aborting leaves the pending input exactly as it was.
          (with-current-buffer eshell-buffer
            (goto-char (point-max))
            (insert "echo keep me")
            (shell-edit-eshell))
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (with-current-buffer edit-buffer
            (erase-buffer)
            (insert "must never reach the prompt")
            (shell-edit-abort))
          (with-current-buffer eshell-buffer
            (goto-char (point-max))
            (should (string= (shell-edit-eshell-read-line) "echo keep me")))
          (should (null (buffer-live-p edit-buffer))))
      (when (buffer-live-p edit-buffer)
        (with-current-buffer edit-buffer
          (remove-hook 'kill-buffer-hook #'shell-edit--close-frame))
        (kill-buffer edit-buffer))
      (when (buffer-live-p eshell-buffer)
        (kill-buffer eshell-buffer)))))

(defun ep3c-test--wait-output (buffer pattern)
  "Wait up to ten seconds until BUFFER's text matches PATTERN.
The shell output settles asynchronously, so the waiter sleeps
instead of polling in a tight loop; it signals when the match
never appears."
  (let ((deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (not (with-current-buffer buffer
                       (string-match-p pattern (buffer-string)))))
      (sleep-for 0.2))
    (with-current-buffer buffer
      (should (string-match-p pattern (buffer-string))))))

(defun ep3c-test--shell-wait-prompt (buffer)
  "Wait up to ten seconds until the comint BUFFER accepts input.
The readiness predicate is the one the editor itself relies on:
the pending input region is empty, which only happens with a
fresh prompt on the buffer's tail.  When the wait is over, the
editor's extraction starts there."
  (let ((deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (not (with-current-buffer buffer
                       (and (shell-edit--comint-process-live-p)
                            (eq (point-max)
                                (shell-edit--comint-input-start))))))
      (sleep-for 0.2))
    (with-current-buffer buffer
      (should (eq (point-max)
                  (marker-position (shell-edit--comint-input-start)))))))

(defun ep3c-test--term-open (name char-mode)
  "Start a term buffer named after NAME running /bin/bash.
CHAR-MODE decides which term mode the buffer rests in -- `term'
itself enters char mode when it spawns the shell.  The wait rests
only when the shell has drawn its first prompt."
  (with-current-buffer (make-term name "/bin/bash")
    (when char-mode (term-char-mode)))
  (let ((buffer (concat "*" name "*"))
        (deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (<= (buffer-size (get-buffer buffer)) 5))
      (sleep-for 0.2))
    (get-buffer buffer)))

(defun ep3c-test--term-wait-empty (buffer)
  "Wait up to ten seconds until term BUFFER waits for input again.
The extraction's own readiness predicate: an empty command line,
which only happens on a prompt with nothing typed yet.  The
extraction moves the shell's cursor, so the waiter polls through
it -- harmless, since C-a on an input line never redraws it."
  (let ((deadline (+ (float-time) 10)))
    (while (and (< (float-time) deadline)
                (not (with-current-buffer buffer
                       (string= (shell-edit-term-read-line) ""))))
      (sleep-for 0.2))
    (with-current-buffer buffer
      (should (string= (shell-edit-term-read-line) "")))))

(ert-deftest ep3c-test-comint-edit-command-line ()
  "Round-trip `shell-edit-comint' with a real M-x shell.
Like the eshell test this needs no pty -- the pending input lives
in the buffer itself -- but it still loads the shell-edit package
under test, so it rides on the same readiness check.  Checks the C-x C-e
binding in the comint mode map, prompt-excluded extraction, the
edit buffer wiring, accepting an edit on the prompt (which then
runs through RET), the `comint-accumulate' lines being part of the
edit, the dead-process guard, and that aborting leaves the input
intact."

  (skip-unless (ep3c-test--shell-ready-p))
  (require 'shell)
  (let* ((shell-buffer (let ((explicit-shell-file-name "/bin/bash"))
                         (shell "ep3c-test-comint")))
         (edit-buffer nil))
    (unwind-protect
        (with-current-buffer shell-buffer
          ;; The feature binding shadows the global eval-last-sexp.
          (should (eq (lookup-key comint-mode-map (kbd "C-x C-e"))
                      'shell-edit-comint))
          ;; A fresh prompt edits as an empty line -- process-mark
          ;; rests at the end of the prompt, nothing is pending...
          (ep3c-test--shell-wait-prompt shell-buffer)
          (should (string= (shell-edit-comint-read-line) ""))
          ;; ...and typed-ahead input is extracted, prompt left out.
          (goto-char (point-max))
          (insert "echo comint-$((41+1))")
          (should (string= (shell-edit-comint-read-line)
                           "echo comint-$((41+1))"))
          ;; The entry point wires a fresh edit buffer back to this
          ;; shell; batch mode has no graphic display, so no frame.
          (shell-edit-comint)
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (should (eq (buffer-local-value 'shell-edit--source edit-buffer)
                      shell-buffer))
          (should (null (buffer-local-value 'shell-edit--frame
                                            edit-buffer)))
          (with-current-buffer edit-buffer
            (should (where-is-internal 'shell-edit-accept
                                       (list (current-local-map))))
            (should (where-is-internal 'shell-edit-abort
                                       (list (current-local-map))))
            (erase-buffer)
            (insert "echo edited in comint && echo COMINT-$((40+3))")
            (shell-edit-accept))
          ;; The prompt carries the edit, and RET runs it: the
          ;; arithmetic output appears only once the shell ran the
          ;; edited line.
          (with-current-buffer shell-buffer
            (should (string= (shell-edit-comint-read-line)
                             "echo edited in comint && echo COMINT-$((40+3))"))
            (funcall (key-binding "\r"))
            (ep3c-test--wait-output shell-buffer "COMINT-43"))
          (should (null (buffer-live-p edit-buffer)))
          ;; Lines accumulated by M-RET are part of the same edit:
          ;; they rest after the process mark too, the region
          ;; comint-send-input runs on RET.
          (with-current-buffer shell-buffer
            (ep3c-test--shell-wait-prompt shell-buffer)
            (goto-char (point-max))
            (insert "echo first")
            (comint-accumulate)
            (should (string= (shell-edit-comint-read-line) "echo first\n"))
            (goto-char (point-max))
            (insert "echo second")
            (should (string= (shell-edit-comint-read-line)
                             "echo first\necho second"))
            (shell-edit-comint))
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (should (eq (buffer-local-value 'shell-edit--source edit-buffer)
                      shell-buffer))
          (with-current-buffer edit-buffer
            (erase-buffer)
            (insert "echo THIRD-$((41+1))\necho FOURTH-$((41+1))")
            (shell-edit-accept))
          (with-current-buffer shell-buffer
            (should (string= (shell-edit-comint-read-line)
                             "echo THIRD-$((41+1))\necho FOURTH-$((41+1))"))
            (funcall (key-binding "\r"))
            (ep3c-test--wait-output shell-buffer "THIRD-42")
            (ep3c-test--wait-output shell-buffer "FOURTH-42")
            (ep3c-test--shell-wait-prompt shell-buffer))
          (should (null (buffer-live-p edit-buffer)))
          ;; Aborting leaves the pending input exactly as it was.
          (with-current-buffer shell-buffer
            (ep3c-test--shell-wait-prompt shell-buffer)
            (goto-char (point-max))
            (insert "echo keep me")
            (shell-edit-comint))
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (with-current-buffer edit-buffer
            (erase-buffer)
            (insert "must never reach the prompt")
            (shell-edit-abort))
          (with-current-buffer shell-buffer
            (should (string= (shell-edit-comint-read-line) "echo keep me")))
          (should (null (buffer-live-p edit-buffer)))
          ;; A dead shell process refuses to edit.
          (with-current-buffer shell-buffer
            (delete-process (get-buffer-process (current-buffer)))
            (should-error (shell-edit-comint) :type 'user-error)))
      (when (buffer-live-p edit-buffer)
        (with-current-buffer edit-buffer
          (remove-hook 'kill-buffer-hook #'shell-edit--close-frame))
        (kill-buffer edit-buffer))
      (when (buffer-live-p shell-buffer)
        (kill-buffer shell-buffer)))))

(ert-deftest ep3c-test-term-edit-command-line ()
  "Round-trip `shell-edit-term' with a real /bin/bash term.
Both term modes are exercised against live term processes: char
mode -- the one `term' enters when it spawns -- drives readline
through the pty the way the vterm test does, and line mode edits
the buffer the way the comint test does.  Checks the C-x C-e
bindings in both mode maps, that the other raw C-x chords still
reach the pty, the edit buffer wiring, accepting an edit (which
then runs through RET), and that aborting leaves the prompt
untouched."

  (skip-unless (ep3c-test--shell-ready-p))
  (require 'term)
  (let ((char-buffer (ep3c-test--term-open "ep3c-test-term" t))
        (line-buffer nil)
        (edit-buffer nil))
    (unwind-protect
        (progn
          (with-current-buffer char-buffer
            ;; The feature binding shadows the global
            ;; eval-last-sexp in both term modes.
            (should (eq (lookup-key term-raw-map (kbd "C-x C-e"))
                        'shell-edit-term))
            (should (eq (lookup-key term-mode-map (kbd "C-x C-e"))
                        'shell-edit-term))
            ;; In char mode every other C-x chord still reaches the
            ;; pty through the default binding of the same prefix.
            (should (eq (key-binding (vconcat "\C-x" "\C-e") t)
                        'shell-edit-term))
            (should (eq (key-binding (vconcat "\C-x" "\C-s") t)
                        'shell-edit--term-send-raw-keys))
            ;; A fresh prompt edits as an empty line...
            (should (string= (shell-edit-term-read-line) ""))
            ;; ...and typing through the pty is extracted, prompt
            ;; left out.
            (term-send-raw-string "echo term-$((41+1))")
            (ep3c-test--wait-output char-buffer
                                    (regexp-quote "echo term-$((41+1))"))
            (should (string= (shell-edit-term-read-line) "echo term-$((41+1))"))
            ;; The entry point wires a fresh edit buffer back to
            ;; this term; batch mode has no graphic display, so no
            ;; frame.
            (shell-edit-term)
            (setq edit-buffer (ep3c-test--shell-find-edit))
            (should (bufferp edit-buffer))
            (should (eq (buffer-local-value 'shell-edit--source edit-buffer)
                        char-buffer))
            (should (null (buffer-local-value 'shell-edit--frame
                                              edit-buffer)))
            (with-current-buffer edit-buffer
              (should (where-is-internal 'shell-edit-accept
                                         (list (current-local-map))))
              (should (where-is-internal 'shell-edit-abort
                                         (list (current-local-map))))
              (erase-buffer)
              (insert "echo edited in term && echo TERM-$((40+2))")
              (shell-edit-accept))
            ;; The pty echoes the edit back on the line, and RET
            ;; runs it: the arithmetic output is the one the shell
            ;; computed, not the echoed line itself.
            (ep3c-test--wait-output char-buffer
                                    (regexp-quote "echo edited in term"))
            (should (string= (shell-edit-term-read-line)
                             "echo edited in term && echo TERM-$((40+2))"))
            (term-send-raw-string "\r")
            (ep3c-test--wait-output char-buffer "TERM-42")
            (ep3c-test--term-wait-empty char-buffer))
          (should (null (buffer-live-p edit-buffer)))
          ;; Aborting leaves the typed line exactly as it was.
          (with-current-buffer char-buffer
            (term-send-raw-string "echo keep me")
            (ep3c-test--wait-output char-buffer (regexp-quote "echo keep me"))
            (shell-edit-term)
            (setq edit-buffer (ep3c-test--shell-find-edit))
            (should (bufferp edit-buffer))
            (with-current-buffer edit-buffer
              (erase-buffer)
              (insert "must never reach the prompt")
              (shell-edit-abort))
            (sleep-for 0.5)
            (should (string= (shell-edit-term-read-line) "echo keep me")))
          (should (null (buffer-live-p edit-buffer)))
          ;; Line mode, against a fresh term: the pending input is
          ;; entirely a buffer edit there, and nothing is sent -- the
          ;; arithmetic output only appears through RET.
          (setq line-buffer (ep3c-test--term-open "ep3c-test-term-line" nil))
          (with-current-buffer line-buffer
            (should (eq (lookup-key term-mode-map (kbd "C-x C-e"))
                        'shell-edit-term))
            (ep3c-test--term-wait-empty line-buffer)
            (goto-char (point-max))
            (insert "echo line-$((41+1))")
            (should (string= (shell-edit-term-read-line) "echo line-$((41+1))"))
            (shell-edit-term))
          (setq edit-buffer (ep3c-test--shell-find-edit))
          (should (bufferp edit-buffer))
          (should (eq (buffer-local-value 'shell-edit--source edit-buffer)
                      line-buffer))
          (with-current-buffer edit-buffer
            (erase-buffer)
            (insert "echo edited in line mode && echo LINE-$((40+2))")
            (shell-edit-accept))
          (with-current-buffer line-buffer
            (should (string= (shell-edit-term-read-line)
                             "echo edited in line mode && echo LINE-$((40+2))"))
            (term-send-input)
            (ep3c-test--wait-output line-buffer "LINE-42"))
          (should (null (buffer-live-p edit-buffer))))
      (when (buffer-live-p edit-buffer)
        (with-current-buffer edit-buffer
          (remove-hook 'kill-buffer-hook #'shell-edit--close-frame))
        (kill-buffer edit-buffer))
      (when (buffer-live-p char-buffer)
        (kill-buffer char-buffer))
      (when (buffer-live-p line-buffer)
        (kill-buffer line-buffer)))))

(provide 'ep3c-test)
;;; ep3c-test.el ends here
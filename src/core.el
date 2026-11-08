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

;;; Key bindings

(defgroup ep3c nil
  "EP3C, Emacs Pretty Personal Portable Configuration."
  :group 'convenience)

(defcustom ep3c-evil-leader "SPC"
  "Leader key prefix for `ep3c-define-key' bindings when the evil
module (evil.org) is enabled."
  :group 'ep3c
  :type 'string)

(defcustom ep3c-non-evil-leader "C-c"
  "Leader key prefix for `ep3c-define-key' bindings when the evil
module is disabled.  \"C-c <letter>\" is the user-reserved space of
the manual, and major/minor mode maps shadow it, so local C-c C-x
chords keep working underneath."
  :group 'ep3c
  :type 'string)

(defvar ep3c-leader-map (make-sparse-keymap)
  "Sparse keymap where `ep3c-define-key' puts every leader-relative
binding when evil is not running; bound to `ep3c-non-evil-leader'
in `global-map', so the whole tree hangs from one prefix binding
and is fully visible to which-key.")

(defun ep3c--evil-p ()
  "Non-nil when evil is up and running."
  (and (featurep 'evil) (fboundp 'evil-define-key*)))

(defun ep3c--leader-pairs (keys-defs leader)
  "Return KEYS-DEFS with every key prefixed with \"LEADER \".
KEYS-DEFS is the KEY DEF pair list `evil-define-key' takes; the
trailing malformed pair, if any, is silently skipped."
  (ep3c--kbd-pairs keys-defs (lambda (key) (concat leader " " key))))

(defun ep3c--kbd-pairs (keys-defs prefix)
  "Return KEYS-DEFS with every key kbd'ed after applying PREFIX.
PREFIX is a function of the leader-relative key, returning the key
string; keys are then turned into their kbd form.  The trailing
malformed pair, if any, is silently skipped."
  (let (out)
    (while (cadr keys-defs)
      (setq out (nconc out
                       (list (kbd (funcall prefix (car keys-defs)))
                             (cadr keys-defs)))
            keys-defs (cddr keys-defs)))
    out))

(defun ep3c--define-pairs (map keys-defs prefix)
  "Define every KEYS-DEFS pair into MAP, `define-key' at a time.
PREFIX is applied to the leader-relative key before `kbd', same as
in `ep3c--kbd-pairs'.  Like the pair builders, a trailing
malformed pair is silently skipped."
  (while (cadr keys-defs)
    (define-key map (kbd (funcall prefix (car keys-defs))) (cadr keys-defs))
    (setq keys-defs (cddr keys-defs))))

(defun ep3c-define-key (states map &rest keys-defs)
  "Bind KEYS-DEFS relative to the EP3C leader key, with or without evil.

STATES is the list of evil states the binding applies to ('normal,
'visual, '(normal visual) ...); MAP is the symbol `global' for
bindings available in any buffer, or the keymap (symbol or object)
of a mode.  KEYS-DEFS are KEY DEF pairs as `evil-define-key' takes
them, with KEY written *leader-relative*: \"t v\", not \"SPC t v\".

With evil up, this is the `evil-define-key*' form of the
`evil-define-key' call the module wrote before, with
`ep3c-evil-leader' prepended to every KEY.

Without evil the STATES argument cannot be emulated and is ignored:
the keys land in `ep3c-leader-map', bound to `ep3c-non-evil-leader'
in `global-map', or directly into MAP -- keymaps local to a mode
already shield their buffers from others.

Modules tangle alphabetically, so some come before evil.org: those
get the plain bindings right away, and when evil arrives later the
same KEYS-DEFS are redone through its states, so no module has to
defer its call.  If evil never loads, the deferred hook never
fires and the plain bindings are all there is."
  (if (ep3c--evil-p)
      ;; `evil-define-key' is a macro and cannot be `apply''d; its
      ;; runtime form is `evil-define-key*' -- same `global'/keymap
      ;; handling, minus the `evil-with-delay' deferral, which is
      ;; irrelevant here (mode-map callers run from hooks, where the
      ;; keymap already exists).
      (apply #'evil-define-key* states map
             (ep3c--leader-pairs keys-defs ep3c-evil-leader))
    (if (eq map 'global)
        ;; The leader map already hangs from the leader key, so its
        ;; own entries are the un-prefixed, leader-relative keys.
        ;; `define-key' is not variadic: unlike
        ;; `evil-define-key*', it takes no &rest bindings, hence
        ;; the one-at-a-time loop below.
        (progn
          (define-key global-map (kbd ep3c-non-evil-leader) ep3c-leader-map)
          (ep3c--define-pairs ep3c-leader-map keys-defs #'identity))
      ;; Mode maps, on the other hand, are not the leader map, so
      ;; there the keys carry the leader with them.
      (ep3c--define-pairs map keys-defs
                          (lambda (key)
                            (concat ep3c-non-evil-leader " " key))))
    ;; The plain bindings above are already live; when evil shows up
    ;; (or has been all along) the keys are defined through it as
    ;; well.  The plain leader-map bindings stay.
    (with-eval-after-load 'evil
      (apply #'evil-define-key* states map
             (ep3c--leader-pairs keys-defs ep3c-evil-leader)))))

(provide 'core)
;;; core.el ends here
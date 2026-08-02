# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

EP3C (Emacs Pretty Personal Portable Configuration) is a modular, batteries-included Emacs configuration. It is **not a typical software project**: there is no build system, no test suite, no package manifest beyond what `package.el`/`quelpa`/`use-package` fetch at install time. The repository's purpose is to be cloned by users, then installed into their `user-emacs-directory` via the installer.

## Repository layout

```
.
├── README.org                # User-facing docs (org-mode source)
├── LICENSE
└── src/
    ├── install.el            # One-shot installer — copies files into user-emacs-directory
    ├── init.el               # Loaded by Emacs on every startup (after install)
    └── modules/              # Org-mode modules, each tangling into a .el file at load time
        ├── environment.org   # exec-path-from-shell, envrc, .env file mappings
        ├── theme.org         # Doom Nord (Linux/BSD), timu-macos (macOS), nimbus (Windows), doom-modeline
        ├── evil.org          # evil-mode + evil-collection
        ├── orgmode.org       # org, org-bullets, org-modern, evil-org, babel languages
        ├── completion.org    # company-mode
        ├── minibuffer.org    # vertico, marginalia, ivy, counsel, consult, orderless, which-key
        ├── lsp.org           # lsp-mode, dap-mode, dap-ui, yasnippet, dap-cpptools
        ├── prog-mode.org     # prog-mode-hook settings: ansi-color, flycheck, hl-line, line numbers
        ├── version-control.org # magit
        ├── projectile.org    # projectile + vterm integration
        ├── treemacs.org      # treemacs + treemacs-{evil,projectile,magit,icons-dired,persp,tab-bar}
        ├── dashboard.org     # emacs-dashboard
        ├── dired.org         # dired + all-the-icons-dired
        ├── display-buffer.org # display-buffer-alist rules
        ├── windows.org       # Windows-specific (powershell, kql-mode)
        ├── environment.org   # PATH, direnv
        ├── shell.org         # vterm, multi-vterm, eshell
        ├── web.org           # typescript-mode, rjsx-mode, treesit-auto, nodejs-repl
        ├── python.org        # pyenv, pyvenv, elpy, dap-python
        ├── c-cpp.org         # c-mode/c++-mode → lsp, clangd flags
        ├── haskell.org       # haskell-mode, lsp-haskell, flycheck nesting workaround
        ├── perl.org          # cperl-mode, inf-perl, perl debugger
        ├── dotnet.org        # omnisharp for csharp-mode
        ├── yaml.org          # yaml-mode
        ├── rest.org          # restclient + ob-restclient
        ├── pdf-tools.org     # pdf-tools + custom `pdf:` org link
        ├── tex.org           # AUCTeX
        ├── ledger.org        # ledger-mode
        ├── apheleia.org      # Async formatter (AWK uses spaces; ts/tsx → prettier)
        ├── gptel.org         # LLM client (Ollama + OpenAI examples)
        ├── engine-mode.org   # web search bindings (GoodReads, DuckDuckGo)
        ├── password-store.org # GnuPG pinentry + WSL pass wrapper
        ├── docker.org        # docker, dockerfile-mode
        └── .gitignore        # Ignores tangled *.el + ltximg/
```

Each module is a single `.org` file with `#+begin_src emacs-lisp … #+end_src` blocks. There are no `.el` files checked in for modules — `org-babel-load-file` tangles and loads them at startup.

## Architecture: install vs. runtime

There are two distinct lifecycles:

### 1. Install (one-shot, run by user)

`README.org` documents the procedure:

1. Open `README.org` in Emacs.
2. `C-s installer-script RET` jumps to the source block.
3. `C-c C-c` evaluates it, which calls `(load-file "src/install.el")` then `(ep3c--setup)`.

`ep3c--setup` (`src/install.el`):
- Creates `user-emacs-directory` if missing.
- Sets `custom-file` to `<user-emacs-directory>/custom.el`.
- Calls `ep3c--install` to:
  - Delete and recreate `<user-emacs-directory>/modules/`.
  - Copy `src/init.el` → `<user-emacs-directory>/init.el`.
  - Copy every `src/modules/*.org` → `<user-emacs-directory>/modules/`.
- Defines the `ep3c-modules` defcustom with `:set #'ep3c--set-modules`, which validates module symbols against the available set on every assignment.
- Calls `customize-option 'ep3c-modules` to pop the Customize buffer where the user toggles modules.

`ep3c-modules` is the central switch: a list of symbols (one per module filename without `.org`). Modules not in this list are never loaded.

### 2. Runtime (every Emacs start)

`init.el` (copied to `<user-emacs-directory>/init.el`):
- Configures `package-archives` (gnu, org, melpa). Sets archive priorities only on Emacs <30.
- Calls `package-refresh-contents` and installs `use-package` if missing.
- Installs `quelpa` and `quelpa-use-package` for git-sourced packages.
- Defines/loads `ep3c-modules` custom variable.
- Validates `ep3c-modules` against the files in `<user-emacs-directory>/modules/`.
- `mapcar`s over `ep3c-modules`, calling `org-babel-load-file` on each `<user-emacs-directory>/modules/<name>.org`.
- For each directory in `org-agenda-files`, loads `org-init.el` if present — a per-project Emacs hook.

The `init--with-ensure-frame-ready` macro in `init.el` runs its body either immediately or via `after-make-frame-functions` depending on `(daemonp)` — used to defer GUI-only setup like doom-modeline and the minimal UI.

## Module conventions

- **Headers**: every module begins with `#+TITLE:` and `#+AUTHOR: Diacus Magnuz`. `install.el`'s `ep3c--module-title` extracts this for the Customize display.
- **`:ensure t`** pulls from MELPA/GNU ELPA. **`:quelpa (NAME :fetcher github :repo "OWNER/REPO")** pulls from GitHub via quelpa.
- **`:after PKG`** defers loading until `PKG` is loaded — used heavily so packages like `lsp-haskell` after `lsp-mode`, `treemacs-magit` after `(treemacs magit)`, etc.
- **`:hook (MODE . FN)`** wires up major/minor mode hooks; many modules use `:hook` instead of explicit `add-hook`.
- **OS guards**: `when (member system-type '(ms-dos windows-nt cygwin))` for Windows-only behavior, `unless (member system-type '(ms-dos windows-nt cygwin))` for Unix-only (vterm, multi-vterm, projectile-vterm). Themes also branch on `system-type` (theme.org).
- **Cross-module notes**: `evil.org` references `orgmode.org` explicitly because `evil-org` is configured there, not in `evil.org`. When adding features tied to another module's package, follow the existing convention of co-locating with the language/mode module.
- **Key bindings**: leader is `SPC` in Evil normal state. Existing top-level prefixes — `SPC p` (project), `SPC g` (git/magit), `SPC o` (org/shell), `SPC d` (dap), `SPC c` (compile), `SPC ;` (visual comment), plus global `M-0`/`C-x t` (treemacs), `C-c d` (docker), `C-x /` (engine-mode). See `README.org` for the full table — match the existing prefixes when adding bindings.

## Load-order gotchas (worth knowing before editing)

These are baked into the modules because the underlying packages have ordering bugs:

- **Haskell/flycheck** (`haskell.org`): nests `with-eval-after-load 'lsp-mode` then `with-eval-after-load 'flycheck` because `flycheck-disable-checker` needs an active buffer. Uses `add-to-list 'flycheck-disabled-checkers` instead.
- **Python/elpy** (`python.org`): pyvenv loads before elpy via `:after pyvenv`; elpy enables itself via `(advice-add 'python-mode :before 'elpy-enable)` rather than a hook.
- **Projectile + vterm** (`projectile.org`): the vterm keybindings are deferred inside `with-eval-after-load 'vterm` so projectile functions don't fail on Windows.
- **org-modern** (`orgmode.org`): an `advice-add 'org-modern-agenda :after` adds progress-bar styling in the agenda view (org-modern itself doesn't render progress bars there).
- **lsp-mode** (`lsp.org`): bumps `gc-cons-threshold` to 100 MiB and `read-process-output-max` to 1 MiB at init time for LSP responsiveness.

## Common operations

There are no test, lint, or build commands — this repo has no CI. Day-to-day work is editing `.org` files and verifying by restarting Emacs.

### Validate Emacs Lisp (best-effort, no test runner)

The closest things to "tests" available without running Emacs interactively:

```sh
# Byte-compile a single tangled file (tangle first, or load the .org via emacs -Q)
emacs -Q --batch -l src/init.el -f batch-byte-compile FILE.el

# Or open one module in a fresh Emacs and verify it loads without errors:
emacs -Q --batch -l src/init.el --eval "(progn (require 'org) (org-babel-load-file \"src/modules/python.org\"))"
```

### Tangle a module to inspect generated ELisp

```sh
emacs -Q --batch --eval "(progn (require 'org) (with-temp-buffer (insert-file-contents \"src/modules/haskell.org\") (org-babel-tangle) (princ (buffer-string))))" > /tmp/haskell.el
```

### Install for testing

To smoke-test the installer locally without polluting your real `user-emacs-directory`, point Emacs at a temp directory:

```sh
HOME=/tmp/ep3c-test-home emacs -Q --batch -l src/install.el -f ep3c--setup
```

Then open the resulting `/tmp/ep3c-test-home/init.el` with `(load-file ...)`.

## README.org quirks

`README.org` contains literal emacs-lisp source blocks (e.g. `# installer-script`, `# remove-everything`) intended to be evaluated in-place by the user via `C-c C-c`. **Do not remove or refactor those blocks** — they are part of the user-facing install/remove procedure. Treat them as runnable documentation, not just prose.
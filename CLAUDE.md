# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EP3C (Emacs Pretty Personal Portable Configuration) is a modular Emacs configuration framework written in Org mode with embedded Emacs Lisp. The configuration uses `org-babel-load-file` to tangle and execute code blocks from `.org` module files.

## Architecture

```
src/
├── init.el        # Entry point: package archives, use-package bootstrap, module loading
├── install.el     # Installation routine for copying to user-emacs-directory
└── modules/       # Modular configuration files (Org mode with embedded Elisp)
    ├── lsp.org        # LSP/DAP configuration
    ├── prog-mode.org  # Common programming mode settings
    ├── evil.org      # Vim emulation
    ├── minibuffer.org # Completion (Vertico, Ivy, Counsel)
    └── ...           # Language-specific and feature modules
```

## Key Patterns

### Module Structure
All modules in `src/modules/*.org` follow the same pattern:
- Title/header in Org format
- Descriptive text with links
- `#+begin_src emacs-lisp` blocks containing `use-package` declarations and configuration

### Adding New Modules
1. Create a new `src/modules/<name>.org` file
2. Follow existing module patterns (see `haskell.org` or `lsp.org` for examples)
3. Use `use-package` for all package declarations with `:ensure t`
4. The module will be auto-loaded via `ep3c-modules` customization

### Package Management
- Uses standard Emacs package archives (GNU ELPA, MELPA, Org)
- `quelpa-use-package` for packages from Git repositories
- Package priority configured for Emacs versions < 30

### Keybinding Conventions
- Uses `evil-define-key` with states `'(normal visual motion)` or `'global`
- Leader-style bindings use `SPC` prefix (e.g., `SPC o t` for terminal)
- Language-specific bindings defined in mode hooks

## Platform Support

The configuration handles multiple platforms:
- `gnu/linux` and `berkeley-unix`: Doom Nord theme, vterm
- `darwin`: timu-macos-theme, vterm
- `windows-nt`: nimbus-theme, eshell (no vterm support)
- `android`: Doom Nord theme, vterm

## Common Tasks

### Testing Changes
Since this is an Emacs configuration, testing requires:
1. Restart Emacs, or
2. `M-x eval-buffer` on modified files, or
3. `M-x org-babel-execute-src-block` on individual blocks

### Adding a New Language Module
1. Create `src/modules/<language>.org`
2. Include `use-package` for the major mode
3. Add LSP integration if applicable (follow `haskell.org` pattern)
4. Define keybindings in mode hooks using `evil-define-key`

### Modifying Existing Modules
Edit the `#+begin_src emacs-lisp` blocks directly. Changes take effect after re-evaluation or Emacs restart.

## Important Macros

### `init--with-ensure-frame-ready`
Used for operations requiring graphical frames (works correctly in daemon mode):
```emacs-lisp
(init--with-ensure-frame-ready #'some-function)
```
See `theme.org` and `init.el` for usage examples.

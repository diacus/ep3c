# LSP to Eglot Migration

## Status: COMPLETED

This document describes the migration from `lsp-mode` to `eglot` as the default LSP client.

## Changes Made

### Modules Modified

| Module | Changes |
|--------|---------|
| `lsp.org` | Replaced `lsp-mode` with `eglot` configuration |
| `dap.org` | **NEW** - Standalone DAP configuration (separated from LSP) |
| `haskell.org` | Removed `lsp-haskell`, using `eglot-ensure` |
| `c-cpp.org` | Migrated to `eglot-ensure`, clangd args moved to lsp.org |
| `python.org` | Replaced `lsp` hook with `eglot-ensure` |
| `dotnet.org` | Replaced `lsp-deferred` with `eglot-ensure` |
| `web.org` | Replaced `lsp-deferred` with `eglot-ensure` |
| `minibuffer.org` | Removed `consult-lsp`, added eglot-compatible consult bindings |

### New Module: `dap.org`

DAP (Debug Adapter Protocol) is now a standalone module that works independently of the LSP client. This allows debugging support with either eglot or lsp-mode.

## Migration Details

### lsp-mode → eglot

**Before:**
```emacs-lisp
(use-package lsp-mode
  :ensure t
  :hook ((prog-mode . lsp)))
```

**After:**
```emacs-lisp
(use-package eglot
  :ensure nil  ; Built into Emacs 29+
  :config
  (setq eglot-sync-connect 1)
  (setq eglot-autoshutdown t)
  (setq eglot-send-changes-idle-time 0.1))
```

### Language Hooks

Instead of a global `prog-mode` hook, eglot uses explicit per-language hooks:

```emacs-lisp
(add-hook 'c-mode-hook 'eglot-ensure)
(add-hook 'c++-mode-hook 'eglot-ensure)
(add-hook 'haskell-mode-hook 'eglot-ensure)
(add-hook 'python-mode-hook 'eglot-ensure)
(add-hook 'typescript-mode-hook 'eglot-ensure)
(add-hook 'csharp-mode-hook 'eglot-ensure)
```

### Key Differences

| Feature | lsp-mode | eglot |
|---------|----------|-------|
| Package | External (`lsp-mode`) | Built-in (Emacs 29+) |
| Auto-install servers | Yes | No |
| DAP integration | Built-in | Separate (`dap.org`) |
| Completion UI | `lsp-ivy`, `consult-lsp` | Built-in + `consult-xref` |
| Go-to-definition | `lsp-find-definition` | `xref-find-definitions` (M-.) |
| References | `lsp-find-references` | `xref-find-references` (M-?) |

## Requirements

### Minimum Emacs Version
- Emacs 29.1+ (eglot is built-in)

### Language Servers (must be installed manually)

| Language | Server | Installation |
|----------|--------|--------------|
| Haskell | haskell-language-server | `ghcup install hls` |
| C/C++ | clangd | Package manager |
| Python | pyright or pyls | `pip install pyright` |
| TypeScript | typescript-language-server | `npm install -g typescript-language-server` |
| C# | OmniSharp or csharp-ls | Package manager |

## Testing

1. Ensure language servers are installed
2. Restart Emacs
3. Open a source file in a supported language
4. Verify `M-.` (xref-find-definitions) works
5. Verify `eglot` appears in modeline when LSP is active
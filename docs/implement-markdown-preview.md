# Implement markdown preview for Emacs

I use Emacs as primary editor. I want it to render markdown document
previews in real time. I want a purely Emacs dependent solution.

## Implementation

This feature uses Emacs's built-in `shr-render-buffer` (Simple HTML Renderer)
to render markdown previews directly in Emacs without external browsers or
HTTP servers.

### Components

- **pandoc** - External markdown processor (converts markdown to HTML)
- **shr-render-buffer** - Emacs built-in HTML renderer
- **after-change-functions** - Hook for detecting buffer changes

### How it works

1. User invokes `ep3c-markdown-preview` (or `SPC m p` in evil mode)
2. The current buffer's markdown content is converted to HTML via pandoc
3. HTML is rendered in a preview buffer using `shr-render-buffer`
4. Changes to the source buffer trigger debounced preview updates
5. Focus remains in the source buffer during updates

## Usage scenarios

Let *Document* be the current buffer with markdown mode enabled:

### Enable preview

1. The user invokes `M-x ep3c-markdown-preview RET` or presses `SPC m p`
2. A preview window opens showing the rendered HTML
3. The preview updates automatically as you type

### Kill source buffer with preview enabled

1. Emacs checks if `*markdown-preview*` buffer is the only active
   buffer on its frame
   - if true: Emacs deletes the frame
   - else: Emacs deletes just the `*markdown-preview*` window
2. Emacs kills `*markdown-preview*` buffer
3. Preview mode is disabled in the source buffer

### Kill preview buffer

When user kills `*markdown-preview*` buffer:

1. Preview mode is automatically disabled in the source buffer
2. Hooks are cleaned up

## Customization

- `markdown-preview-buffer-name` - Name of preview buffer (default: `*markdown-preview*`)
- `markdown-preview-debounce-time` - Idle seconds before updating preview (default: `0.3`)

## Prerequisites

Requires pandoc for markdown to HTML conversion:

```bash
# macOS
brew install pandoc

# Debian/Ubuntu
sudo apt install pandoc
```

To use a different processor, configure `markdown-command` before loading.

## Keybinding

```
SPC m p - Toggle markdown preview
```

## References

- [Live preview as you type](https://wikemacs.org/wiki/Markdown#Live_preview_as_you_type)
- [StackOverflow - How can I preview markdown in Emacs in real time?](https://stackoverflow.com/questions/36183071/how-can-i-preview-markdown-in-emacs-in-real-time/36189456?noredirect=1#comment104784050_36189456)
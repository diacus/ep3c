# Implement mardown preview for Emacs
I use Emacs as primary editor. I want it to render markdown document
previews in real time. I want a purely Emacs dependant solution.

## Impatient-mode
Impatient-mode is a library designed to preview HTML documents, but
its documentation claims it can work fine to preview mardown documents
as well.

## Usage scenarios
Implement an interactive preview function `markdown-preview` that
triggers the preview of current buffer if its major mode is markdown,
the function fails otherwise.

Let *Document* the current buffer with markdown mode enabled:

1. The user invokes the preview function with `M-x markdown-preview RET`
2. The preview function enables a mode that captures any change on the
   *Document* buffer to write or update its markdown preview on
   `*markdown-preview*` buffer

When user kills *Document* buffer and the markdown preview is enabled

1. Emacs checks if `*markdown-preview*` buffer is the only active
   buffer on its frame
   - if true: Emacs kills the frame
   - else: emacs kills the `*markdown-preview*` window
2. Emacs kills `*markdown-preview*` buffer

When user kills `*markdown-preview*`buffer, the preview mode turns off
for *Document* buffer

## References
- [Live preview as you type](https://wikemacs.org/wiki/Markdown#Live_preview_as_you_type)
- [StackOverflow - How can I preview markdown in Emacs in real time?](https://stackoverflow.com/questions/36183071/how-can-i-preview-markdown-in-emacs-in-real-time/36189456?noredirect=1#comment104784050_36189456)

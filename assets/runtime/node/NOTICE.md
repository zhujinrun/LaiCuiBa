# Third-party code in this directory

- `linkedom.js` — bundled build of [linkedom](https://github.com/WebReflection/linkedom)
  (MIT, © Andrea Giammarchi), taken verbatim from the reference app package.
  It gives the TVBox js runtime a real DOM so `pdfh` / `pdfa` (the selector
  helpers TVBox sources are written against) work in Node.
- `node.exe` — not in git; copied from the reference package by
  `tool/sync_runtime.sh`.

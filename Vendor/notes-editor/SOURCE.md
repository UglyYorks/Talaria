# Notes editor dependencies

Tiptap and ProseMirror provide the editing model; Tiptap Markdown and Marked provide Markdown parsing and serialization. All code is bundled locally; no CDN or service is used.

Source: https://github.com/ueberdosis/tiptap and https://github.com/markedjs/marked

Exact versions and transitive dependencies are pinned in package-lock.json. To rebuild the checked-in bundle, run `npm ci` then `npm run build` in this directory. Third-party license notices are in LICENSES.txt.

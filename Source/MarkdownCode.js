/* Local code highlighting and native clipboard controls for Markdown replies. */
(function () {
  "use strict";

  const highlights = new Map();
  if (window.hljs) window.hljs.registerAliases("objective-c", { languageName: "objectivec" });

  window.talariaEnhanceCode = function (content) {
    content.querySelectorAll("pre > code").forEach(function (code) {
      const pre = code.parentElement;
      const source = code.textContent;
      const languageClass = [...code.classList].find(name => name.startsWith("language-"));
      const language = languageClass ? languageClass.slice(9).toLowerCase() : "";
      // Avoid guessing unlabelled snippets and keep very large streamed blocks responsive.
      if (window.hljs && language && window.hljs.getLanguage(language) && source.length <= 100000) {
        const key = language + "\n" + source;
        try {
          let html = highlights.get(key);
          if (html === undefined) {
            html = window.hljs.highlight(source, { language, ignoreIllegals: true }).value;
            if (highlights.size >= 32) highlights.clear();
            highlights.set(key, html);
          }
          code.innerHTML = html;
        } catch (_) {
          code.textContent = source;
        }
      }

      const block = document.createElement("div");
      block.className = "tl-code-block";
      pre.replaceWith(block);
      const toolbar = document.createElement("div");
      toolbar.className = "tl-code-toolbar";
      const label = document.createElement("span");
      label.className = "tl-code-language";
      label.textContent = language || "Code";
      const button = document.createElement("button");
      button.type = "button";
      button.className = "tl-code-copy";
      button.textContent = "Copy";
      button.setAttribute("aria-label", "Copy code");
      button.setAttribute("aria-live", "polite");
      button.addEventListener("click", async function () {
        button.disabled = true;
        try {
          await window.webkit.messageHandlers.talariaCopyCode.postMessage(source);
          button.textContent = "Copied!";
          button.setAttribute("aria-label", "Code copied");
        } catch (_) {
          button.textContent = "Retry copy";
          button.setAttribute("aria-label", "Copy failed. Try again");
        } finally {
          button.disabled = false;
          clearTimeout(button.resetTimer);
          button.resetTimer = setTimeout(function () {
            button.textContent = "Copy";
            button.setAttribute("aria-label", "Copy code");
          }, 2000);
        }
      });
      toolbar.append(label, button);
      block.append(toolbar, pre);
    });
  };
})();

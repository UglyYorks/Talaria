/* Local Markdown math support. Formula parsing happens before Markdown escaping. */
(function () {
  "use strict";

  function closingDelimiter(source, start, delimiter) {
    for (let index = start; index < source.length; index++) {
      if (source.startsWith(delimiter, index)) return index;
      if (source[index] === "\\") index++;
    }
    return -1;
  }

  window.talariaMarkdownMath = function (md) {
    function renderMath(source, display) {
      if (!window.katex) return null;
      try {
        const html = window.katex.renderToString(source, {
          displayMode: display, output: "htmlAndMathml", throwOnError: true,
          trust: false, strict: "ignore", maxExpand: 1000, maxSize: 20,
          errorColor: "inherit"
        });
        return '<span class="tl-math ' + (display ? 'tl-math-display' : 'tl-math-inline') + '">' + html + '</span>';
      } catch (_) {
        // Incomplete streamed expressions and unsupported commands stay readable.
        return null;
      }
    }

    md.inline.ruler.before("escape", "talaria_math", function (state, silent) {
      const start = state.pos;
      const source = state.src;
      let open, close, display;
      if (source.startsWith("$$", start)) { open = close = "$$"; display = true; }
      else if (source.startsWith("\\[", start)) { open = "\\["; close = "\\]"; display = true; }
      else if (source.startsWith("\\(", start)) { open = "\\("; close = "\\)"; display = false; }
      else if (source[start] === "$") { open = close = "$"; display = false; }
      else return false;
      if (open === "$" && /\s/.test(source[start + 1] || " ")) return false;
      const end = closingDelimiter(source, start + open.length, close);
      if (end < 0 || end >= state.posMax) return false;
      const expression = source.slice(start + open.length, end);
      if (open === "$" && (/\s/.test(source[end - 1]) || /\d/.test(source[end + 1] || "") || expression.includes("\n"))) return false;
      if (!expression.trim()) return false;
      if (!silent) {
        const token = state.push("talaria_math", "", 0);
        token.content = expression;
        token.markup = open;
        token.meta = { display, close };
      }
      state.pos = end + close.length;
      return true;
    });
    md.renderer.rules.talaria_math = function (tokens, index) {
      const token = tokens[index];
      return renderMath(token.content, token.meta.display) || md.utils.escapeHtml(token.markup + token.content + token.meta.close);
    };

    md.block.ruler.before("fence", "talaria_math_block", function (state, startLine, endLine, silent) {
      const start = state.bMarks[startLine] + state.tShift[startLine];
      if (state.sCount[startLine] - state.blkIndent >= 4) return false;
      const open = state.src.slice(start, start + 2);
      if (open !== "$$" && open !== "\\[") return false;
      const close = open === "$$" ? "$$" : "\\]";
      let lastLine = startLine;
      let end = -1;
      const lines = [];
      for (; lastLine < endLine; lastLine++) {
        const offset = lastLine === startLine ? start + 2 : state.bMarks[lastLine] + state.tShift[lastLine];
        const line = state.src.slice(offset, state.eMarks[lastLine]);
        const closing = closingDelimiter(line, 0, close);
        if (closing >= 0) {
          if (line.slice(closing + 2).trim()) return false;
          end = offset + closing;
          lines.push(line.slice(0, closing));
          break;
        }
        lines.push(line);
      }
      if (end < 0) return false;
      if (silent) return true;
      const token = state.push("talaria_math_block", "", 0);
      token.block = true;
      token.content = lines.join("\n").trim();
      token.map = [startLine, lastLine + 1];
      state.line = lastLine + 1;
      return true;
    }, { alt: ["paragraph", "reference", "blockquote", "list"] });
    md.renderer.rules.talaria_math_block = function (tokens, index) {
      const source = tokens[index].content;
      return (renderMath(source, true) || '<pre><code>' + md.utils.escapeHtml(source) + '</code></pre>') + '\n';
    };

    const code = md.renderer.rules.code_inline;
    md.renderer.rules.code_inline = function (tokens, index, options, env, renderer) {
      const source = tokens[index].content;
      // Older replies use code spans for TeX. Recognize commands or simple
      // equations with powers/subscripts, without changing ordinary code snippets.
      const looksLikeMath = /\\[a-zA-Z]+/.test(source) || (/^[A-Za-z]\s*=/.test(source) && /[\^_]/.test(source));
      return (looksLikeMath && renderMath("\\displaystyle " + source, false)) || code(tokens, index, options, env, renderer);
    };
    const fence = md.renderer.rules.fence;
    md.renderer.rules.fence = function (tokens, index, options, env, renderer) {
      const token = tokens[index];
      const isMath = /^(math|latex|tex)$/.test(token.info.trim());
      return (isMath && renderMath(token.content, true)) || fence(tokens, index, options, env, renderer);
    };
  };
})();

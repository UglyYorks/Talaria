// Search rendered text without changing its formatting, links, or code contents.
(() => {
  let matches = [];
  function clear() {
    document.querySelectorAll('mark[data-talaria-find]').forEach(mark => {
      const parent = mark.parentNode;
      mark.replaceWith(...mark.childNodes);
      parent.normalize();
    });
    matches = [];
  }
  window.talariaFind = (query, colors) => {
    clear();
    if (!query) return 0;
    const root = document.getElementById('content');
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const groups = [];
    let node, group;
    while ((node = walker.nextNode())) {
      const parent = node.parentElement;
      if (parent.closest('button,script,style,[hidden],.katex-mathml') || !parent.getClientRects().length) continue;
      const block = parent.closest('p,li,pre,h1,h2,h3,h4,h5,h6,td,th,blockquote') || root;
      if (!group || group.block !== block) { group = {block, text: '', nodes: []}; groups.push(group); }
      group.nodes.push({node, start: group.text.length});
      group.text += node.data;
    }
    const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const expression = new RegExp(escaped, 'giu');
    const edits = [];
    for (const group of groups) {
      for (const hit of group.text.matchAll(expression)) {
        const index = matches.length;
        matches.push([]);
        const start = hit.index, end = start + hit[0].length;
        for (const entry of group.nodes) {
          const from = Math.max(0, start - entry.start);
          const to = Math.min(entry.node.length, end - entry.start);
          if (from < to) edits.push({node: entry.node, from, to, index});
        }
      }
    }
    // Edit backwards so UTF-16 offsets remain valid within each original node.
    for (const edit of edits.reverse()) {
      const text = edit.node.splitText(edit.from);
      text.splitText(edit.to - edit.from);
      const mark = document.createElement('mark');
      mark.dataset.talariaFind = String(edit.index);
      mark.style.backgroundColor = colors.surface;
      mark.style.color = colors.text;
      text.replaceWith(mark); mark.appendChild(text);
      matches[edit.index].unshift(mark);
    }
    window.talariaSelectFindMatch = (index, reveal) => {
      matches.forEach((parts, i) => parts.forEach(mark => {
        mark.style.backgroundColor = i === index ? colors.activeSurface : colors.surface;
        mark.style.color = i === index ? colors.activeText : colors.text;
      }));
      const parts = matches[index];
      if (!parts?.length) return null;
      if (reveal) {
        const scroller = parts[0].closest('pre,.tl-table-scroll');
        if (scroller) {
          const rect = parts[0].getBoundingClientRect(), bounds = scroller.getBoundingClientRect();
          if (rect.left < bounds.left || rect.right > bounds.right) scroller.scrollLeft += rect.left - bounds.left;
        }
      }
      const rect = parts[0].getBoundingClientRect();
      return {x: rect.x + window.scrollX, y: rect.y + window.scrollY, width: rect.width, height: rect.height};
    };
    return matches.length;
  };
})();

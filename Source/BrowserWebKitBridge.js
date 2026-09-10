// Installed at document start in the application's isolated content world in
// every frame. The native handler receives WKFrameInfo, including opaque frames.
(function (handler, channel, overlayProbe) {
  'use strict';
  if (globalThis.__talariaWebKitBridge) return;
  const identifier = Array.from(crypto.getRandomValues(new Uint32Array(4)), value => value.toString(16)).join('-');
  const children = new Map();
  const announce = () => {
    window.webkit.messageHandlers[handler].postMessage({id:identifier});
    if (parent !== window) parent.postMessage({talaria:channel,id:identifier}, '*');
    // A main-document commit can reset native handles after a child already
    // registered. Ask existing children to register again without inspecting
    // their documents, including cross-origin frames and BFCache restorations.
    for (let index = 0; index < Math.min(frames.length, 128); index++)
      frames[index].postMessage({talaria:channel,request:true}, '*');
  };
  window.addEventListener('message', event => {
    if (event.data?.talaria !== channel) return;
    if (event.data.request === true && event.source === parent && parent !== window) { announce(); return; }
    if (typeof event.data.id !== 'string') return;
    if (children.size < 128 || children.has(event.source)) children.set(event.source, event.data.id);
  });
  window.addEventListener('pageshow', announce);
  window.addEventListener('pagehide', () => window.webkit.messageHandlers[handler].postMessage({id:identifier,remove:true}));
  document.addEventListener('DOMContentLoaded', announce, {once:true});
  announce();

  function deepestHit(x, y) {
    let node = document.elementFromPoint(x, y);
    for (let depth = 0; node?.shadowRoot && depth < 8; depth++) {
      const next = node.shadowRoot.elementFromPoint(x, y);
      if (!next || next === node) break;
      node = next;
    }
    return node;
  }

  async function candidate(config) {
    const node = deepestHit(config.x, config.y);
    const result = await overlayProbe.call(node, {...config,candidate:true});
    if (result.frame) result.frame.id = children.get(node?.contentWindow) || null;
    return result;
  }

  // WebKit's public DOM hit test respects pointer-events. Inspect a bounded set
  // of visible descendants in reverse paint order as a supplement. It never
  // changes site styles to make normally noninteractive content hit-testable.
  async function pointerCandidate(config) {
    const started = performance.now(), stack = [{nodes:[document.documentElement],index:0}];
    const hit = deepestHit(config.x, config.y);
    const hitZ = hit ? Number(getComputedStyle(hit).zIndex) || 0 : 0;
    let visits = 0;
    while (stack.length && visits++ < 256 && performance.now()-started < 3) {
      const cursor = stack.at(-1);
      if (cursor.index < 0) { stack.pop(); continue; }
      const node = cursor.nodes[cursor.index--];
      if (!node) continue;
      const rect = node.getBoundingClientRect();
      if (rect.left <= config.x && rect.right > config.x && rect.top <= config.y && rect.bottom > config.y) {
        const style = getComputedStyle(node);
        if (style.pointerEvents === 'none' && (Number(style.zIndex) || 0) >= hitZ) {
          const result = await overlayProbe.call(node, {...config,candidate:true});
          if (result.obstructed === true) {
            result.cpuMS = (result.cpuMS || 0) + performance.now()-started;
            return result;
          }
        }
      }
      // Fixed descendants can lie outside their parent's bounds, including a
      // zero-size shadow host, so geometrically pruning ancestors is unsafe.
      if (node.children.length) stack.push({nodes:node.children,index:node.children.length-1});
      if (node.shadowRoot?.children.length) stack.push({nodes:node.shadowRoot.children,index:node.shadowRoot.children.length-1});
    }
    return {obstructed:false,cpuMS:performance.now()-started,maxSliceMS:performance.now()-started};
  }

  async function count(query) {
    if (!query) return 0;
    const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'giu');
    let matches = 0, text = '', block = null, visited = 0, slice = performance.now();
    const flush = () => { if (text) matches += Array.from(text.matchAll(pattern)).length; text = ''; };
    const stack = [document.body || document.documentElement];
    while (stack.length) {
      const node = stack.pop();
      if (!node) continue;
      if (node.nodeType === Node.TEXT_NODE) {
        const parent = node.parentElement;
        if (!parent) continue;
        const style = getComputedStyle(parent);
        if (style.visibility !== 'visible' || !parent.getClientRects().length) continue;
        const owner = parent.closest('p,div,li,pre,h1,h2,h3,h4,h5,h6,td,th,blockquote,button') || parent;
        if (owner !== block) { flush(); block = owner; }
        text += node.data;
      } else if (node.nodeType === Node.ELEMENT_NODE || node.nodeType === Node.DOCUMENT_FRAGMENT_NODE) {
        if (node.nodeType === Node.ELEMENT_NODE) {
          if (['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','IFRAME','FRAME'].includes(node.tagName) || node.hidden) continue;
          if (getComputedStyle(node).display === 'none') continue;
          if (['INPUT','TEXTAREA'].includes(node.tagName) && node.type !== 'password' && node.getClientRects().length) {
            flush(); matches += Array.from((node.value || '').matchAll(pattern)).length;
          }
          if (node.shadowRoot) { stack.push(node.shadowRoot); continue; }
        }
        for (let i = node.childNodes.length-1; i >= 0; i--) stack.push(node.childNodes[i]);
      }
      if (++visited % 128 === 0 && performance.now()-slice > 3) {
        await new Promise(resolve => setTimeout(resolve, 0)); slice = performance.now();
      }
    }
    flush(); return matches;
  }
  globalThis.__talariaWebKitBridge = {identifier,candidate,pointerCandidate,count,announce,
    clearSelection() { getSelection()?.removeAllRanges(); }};
})

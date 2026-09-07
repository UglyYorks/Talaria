// Bounded read-only bottom-edge sample, evaluated in the existing isolated world.
(function (banner=null, topEdge=false) {
  const extensionStart=performance.now();
  const extension=!topEdge && globalThis.__talariaDocumentFooter?.canvasSampleRequest?.();
  if(extension){const cost=performance.now()-extensionStart;return {...extension,cpuMS:cost,maxSliceMS:cost};}
  let slice = performance.now(), cpuMS = 0, maxSliceMS = 0;
  const charge = () => { const elapsed=performance.now()-slice;cpuMS+=elapsed;maxSliceMS=Math.max(maxSliceMS,elapsed); };
  const viewState = [innerWidth,innerHeight,scrollX,scrollY];
  // Weak identities keep an unchanged edge cached without observing the whole
  // document or retaining removed elements. This world is discarded on navigation.
  const identity=globalThis.__talariaFooterColorIdentity ||= {nodes:new WeakMap(),next:0};
  const bannerBottom=banner && Number.isFinite(banner.bottom) ? Math.max(1,banner.bottom) : null;
  const sampleBottom=topEdge ? Math.min(8,innerHeight) : bannerBottom!==null ? Math.max(1,innerHeight-bannerBottom) : (globalThis.__talariaDocumentFooter?.sampleBottom?.() ?? innerHeight);
  const signature=[topEdge,viewState,devicePixelRatio,sampleBottom];let cacheable=true;
  const finish = extra => { charge(); return {...extra,topEdge,viewState,sampleBottom,bannerBottom,deviceScale:devicePixelRatio,
    captureKey:!extra.busy && cacheable ? JSON.stringify(signature) : undefined,
    captureReady:!globalThis.__talariaDocumentFooter?.isScrolling(),cpuMS,maxSliceMS}; };
  if (document.visibilityState !== 'visible') return finish({busy:true});
  if(bannerBottom!==null){cacheable=false;return finish(banner.rgb ? {rgb:banner.rgb} : {fallback:true});}
  const styles = new Map(), checked = new Map(), complexNodes = new Set();
  let reads = 0;
  const parent = el => el.assignedSlot || el.parentElement || el.getRootNode().host;
  const style = el => {
    if (++reads > 96) throw 'complex';
    if (performance.now()-slice > 3) throw 'budget';
    if (!styles.has(el)) {
      const css=getComputedStyle(el);styles.set(el,css);
      if(!identity.nodes.has(el))identity.nodes.set(el,++identity.next);
      const values=[identity.nodes.get(el),css.backgroundColor,css.backgroundImage,css.backgroundPosition,css.backgroundSize,
        css.opacity,css.filter,css.backdropFilter,css.mixBlendMode,css.transform,css.width,css.height,
        css.top,css.bottom,css.left,css.right,css.objectFit,css.objectPosition,
        el.currentSrc || el.getAttribute('src') || '',el.complete,el.naturalWidth,el.naturalHeight,el.scrollLeft,el.scrollTop];
      if(values.some(v=>typeof v==='string' && v.length>512))cacheable=false;
      else signature.push(values);
    }
    return styles.get(el);
  };
  function rgba(value) {
    const m = value.match(/^rgba?\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\s*\)$/);
    return m ? [Number(m[1]),Number(m[2]),Number(m[3]),m[4]===undefined?1:Number(m[4])] : null;
  }
  function colorAt(x,y) {
    let el = document.elementFromPoint(x,y), depth = 0;
    while(el?.shadowRoot && depth++ < 8) {
      const next = el.shadowRoot.elementFromPoint(x,y);
      if (!next || next===el) break;
      el=next;
    }
    let rgb=[0,0,0], alpha=0, complex=false;
    for(let p=el;p;p=parent(p)) {
      const css=style(p);
      if (!checked.has(p)) {
        // Their pixels can change without any observable outer style change.
        if(['IFRAME','VIDEO','CANVAS','SVG','OBJECT','EMBED'].includes(p.tagName) ||
            (p.localName.includes('-') && !p.shadowRoot))cacheable=false;
        if (['IFRAME','IMG','VIDEO','CANVAS','SVG','OBJECT','EMBED'].includes(p.tagName) ||
            (p.localName.includes('-') && !p.shadowRoot) || css.opacity!=='1' || css.filter!=='none' ||
            css.backdropFilter!=='none' || css.mixBlendMode!=='normal' || css.backgroundImage!=='none') complexNodes.add(p);
        // Painted pseudo-elements can cover the sampled background.
        for(const pseudo of ['::before','::after']) {
          const decoration=getComputedStyle(p,pseudo);
          if (decoration.content!=='none' && decoration.content!=='normal' && decoration.display!=='none' &&
              (decoration.backgroundImage!=='none' || (rgba(decoration.backgroundColor)?.[3] ?? 1)>0)) {
            complexNodes.add(p);cacheable=false;
          }
        }
        checked.set(p,rgba(css.backgroundColor));
      }
      complex ||= complexNodes.has(p);
      const c=checked.get(p);if(!c){cacheable=false;return null;}
      const weight=(1-alpha)*c[3];
      rgb=rgb.map((v,i)=>v+c[i]*weight);alpha+=weight;
    }
    return !complex && alpha>0.999 ? rgb.map(Math.round) : null;
  }
  try {
    const width=document.documentElement.clientWidth;
    const colors=[];
    for(const x of [0.06,0.28,0.5,0.72,0.94]) {
      // Five points, one bounded synchronous read. CSS is safe during scrolling;
      // only screenshot readback needs a quiet viewport. Never wait on a frame.
      if(viewState.some((v,i)=>v!==[innerWidth,innerHeight,scrollX,scrollY][i])) return finish({busy:true});
      colors.push(colorAt(width*x,Math.max(0,sampleBottom-4)));
    }
    if(colors.some(c=>!c))return finish({fallback:true});
    const winner=colors.find(c=>colors.filter(d=>d.every((v,i)=>Math.abs(v-c[i])<=3)).length>=4);
    return finish(winner ? {rgb:winner} : {fallback:true});
  } catch (reason) { cacheable=false;return finish(reason==='budget' ? {busy:true} : {fallback:true}); }
})

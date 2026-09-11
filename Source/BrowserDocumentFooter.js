/* A real document-scroll extension. No wheel interception, scroll-position
 * ownership, synthetic momentum, or native viewport updates while scrolling. */
(function () {
  'use strict';
  globalThis.__talariaDocumentFooter?.dispose();
  let nativeFill=false, preparedRGB=null, lastFillState=null;
  let enabled=false, range=0, nativeWidth=1, fallbackColor='', disposed=false;
  let node=null, observedBody=null, observedRoot=null, timer=0, lastUpdate=-Infinity;
  let lastScrollActivity=-Infinity, height=0, colorCost=0;
  let colorTargets=new Set(), colorCanvas=null;
  const convertedColors=new Map();
  let canvasSurface=null, canvasSample=null, surfaceSerial=0, surfaceStyleVersion=0;
  const set=(key,value)=>{if(node.style.getPropertyValue(key)!==value)node.style.setProperty(key,value,'important');};
  const imageBackdrop=css=>css.backgroundImage.length<=8192 && css.backgroundImage.includes('url(');
  function surfaceKey(element,rect,bottom,scheme,color) {
    const css=getComputedStyle(element);
    return JSON.stringify([bottom,rect.left+scrollX,rect.top+scrollY,rect.width,rect.height,
      element.width,element.height,scheme,color,surfaceStyleVersion,css.backgroundImage,
      css.backgroundSize,css.backgroundPosition,css.backgroundRepeat,css.opacity,css.filter,css.transform]);
  }
  // Read the document's end before it is visible. Never move the viewport or
  // sample its current bottom: that edge belongs to the separate native footer.
  function documentColor(bottom, root, body, rs, bs, rr, br) {
    const started=performance.now(), watched=new Set([root,body]);
    const cache=new Map([[root,{css:rs,rect:rr}],[body,{css:bs,rect:br}]]);
    let visits=0, bottomCanvas=null, backdropReads=0;
    const exhausted=()=>visits>=128 || performance.now()-started>3;
    const rgba=value=>{
      const match=value.match(/^rgba?\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\s*\)$/);
      if(match)return [Number(match[1]),Number(match[2]),Number(match[3]),match[4]===undefined?1:Number(match[4])];
      if(convertedColors.has(value))return convertedColors.get(value);
      if(!CSS.supports('color',value))return null;
      // Computed colors can retain lab()/oklch()/color() syntax. Let the
      // browser convert one solid color to sRGB, using a tiny CPU-backed
      // canvas. This never captures page pixels and is cached across refreshes.
      try {
        colorCanvas??=new OffscreenCanvas(1,1).getContext('2d',{willReadFrequently:true});
        if(!colorCanvas)return null;
        colorCanvas.clearRect(0,0,1,1);colorCanvas.fillStyle=value;colorCanvas.fillRect(0,0,1,1);
        const pixel=colorCanvas.getImageData(0,0,1,1).data;
        const result=[pixel[0],pixel[1],pixel[2],pixel[3]/255];
        if(convertedColors.size>=64)convertedColors.delete(convertedColors.keys().next().value);
        convertedColors.set(value,result);return result;
      }catch{return null;}
    };
    const over=(front,back)=>front ? front.slice(0,3).map((v,i)=>v*front[3]+back[i]*(1-front[3])) : back;
    // Split computed gradient arguments without splitting rgb()/rgba() values.
    function argumentsOf(value) {
      const parts=[];let depth=0,start=0;
      for(let i=0;i<value.length;i++){
        if(value[i]==='(')depth++;else if(value[i]===')')depth--;
        else if(value[i]===',' && !depth){parts.push(value.slice(start,i).trim());start=i+1;}
      }
      parts.push(value.slice(start).trim());return parts;
    }
    function gradient(value, rect) {
      if(!value.startsWith('linear-gradient(') || value.length>2048 || rect.height<=0)return null;
      const parts=argumentsOf(value.slice(16,-1));let reverse=false;
      if(!/^rgba?\(/.test(parts[0])){
        const direction=parts.shift();
        if(['to top','0deg','360deg'].includes(direction))reverse=true;
        else if(!['to bottom','180deg'].includes(direction))return null;
      }
      if(parts.length<2 || parts.length>16)return null;
      const stops=parts.map(part=>{
        const match=part.match(/^(rgba?\([^)]*\))(?:\s+(-?[\d.]+)(%|px))?$/);
        return match ? {color:rgba(match[1]),at:match[2]===undefined?null:Number(match[2])/(match[3]==='%'?100:rect.height)} : null;
      });
      if(stops.some(stop=>!stop?.color))return null;
      stops[0].at??=0;stops.at(-1).at??=1;
      for(let i=1;i<stops.length;i++)if(stops[i].at!==null){
        let previous=i-1;while(stops[previous].at===null)previous--;
        stops[i].at=Math.max(stops[previous].at,stops[i].at);
        for(let j=previous+1;j<i;j++)stops[j].at=stops[previous].at+(stops[i].at-stops[previous].at)*(j-previous)/(i-previous);
      }
      let t=Math.max(0,Math.min(1,(bottom-1-(rect.top+scrollY))/rect.height));if(reverse)t=1-t;
      if(t<=stops[0].at)return stops[0].color;
      for(let i=1;i<stops.length;i++)if(t<=stops[i].at){
        const fraction=(t-stops[i-1].at)/Math.max(0.000001,stops[i].at-stops[i-1].at);
        return stops[i].color.map((v,c)=>stops[i-1].color[c]+(v-stops[i-1].color[c])*fraction);
      }
      return stops.at(-1).color;
    }
    function paint(css,rect,background) {
      let result=over(rgba(css.backgroundColor),background);
      const fill=gradient(css.backgroundImage,rect);
      if(fill)result=over(fill,result);
      // Complex images/angles retain their container background, never a
      // delayed screenshot of some unrelated part of the page.
      return result;
    }
    // Canvas resolves the browser's actual default page background, including
    // color-scheme. The native theme color is only a failure fallback.
    const canvas=rgba(getComputedStyle(node).color) || rgba(fallbackColor);
    if(!canvas)return {color:fallbackColor,watched,cost:performance.now()-started};
    let base=paint(rs,rr,canvas.slice(0,3));
    const bodyBase=base;
    if((rgba(rs.backgroundColor)?.[3]??0)===0 && rs.backgroundImage==='none')base=paint(bs,br,base);
    const y=bottom-1-scrollY;
    // Canvas/image backdrops often sit behind a transparent content sibling, so
    // ordinary hit testing never sees them. Inspect only a few absolute
    // backdrops on the already-visited bottom path, not the document tree.
    function backdrop(element,rect,css) {
      if(bottomCanvas || rect.width<root.clientWidth*0.9 || rect.bottom+scrollY<bottom-2)return;
      if(element.localName==='canvas' || imageBackdrop(css)){bottomCanvas=element;return;}
      let siblings=0;
      for(let child=element.firstElementChild;child && siblings++<4;child=child.nextElementSibling) {
        if(backdropReads++>=24 || exhausted())return;
        visits++;
        const css=getComputedStyle(child),r=child.getBoundingClientRect();
        if(css.position!=='absolute' || css.visibility!=='visible' || css.opacity==='0' ||
           r.width<root.clientWidth*0.9 || Math.abs(r.bottom+scrollY-bottom)>2)continue;
        if(imageBackdrop(css)){bottomCanvas=child;return;}
        let p=child;
        for(let depth=0;p && depth<4;depth++,p=p.children.length===1?p.firstElementChild:null){
          if(watched.size<32)watched.add(p);
          if(p.localName==='canvas'){bottomCanvas=p;return;}
        }
      }
    }
    function descend(element,x,background,depth) {
      if(depth>24 || exhausted())return background;
      let entry=cache.get(element);
      if(!entry){
        visits++;const rect=element.getBoundingClientRect();
        entry={rect};cache.set(element,entry);
      }
      const rect=entry.rect, parent=element.shadowRoot || element;
      const insideX=rect.width>0 && x>=rect.left && x<rect.right;
      const insideY=rect.height>0 && y>=rect.top && y<rect.bottom;
      const inside=insideX && insideY;
      if(!inside && !parent.lastElementChild)return null;
      entry.css??=getComputedStyle(element);const css=entry.css;
      if(css.display==='none' || css.visibility!=='visible' || css.opacity==='0' || css.contentVisibility==='hidden' || ['fixed','sticky'].includes(css.position))return null;
      if(watched.size<32)watched.add(element);
      if(inside)backdrop(element,rect,css);
      // A 100%-height body, zero-height wrapper or display:contents ancestor
      // can paint descendants beyond its box. Prune only when that box clips
      // the sample; never let its own background paint outside the box.
      const paintClip=/(^|\s)(paint|strict|content)(\s|$)/.test(css.contain);
      // With visible root overflow, CSS propagates body overflow to the
      // viewport. The body's short box is not then an inner scrolling clip.
      const viewportOverflow=element===body && rs.overflowX==='visible' && rs.overflowY==='visible' && !paintClip;
      if(css.display!=='contents' && !viewportOverflow && ((!insideX && (paintClip || css.overflowX!=='visible')) ||
        (!insideY && (paintClip || css.overflowY!=='visible'))))return null;
      const own=inside ? paint(css,rect,background) : element===body ? base : background;
      let result=inside ? own : null;
      for(let child=parent.lastElementChild;child && !exhausted();child=child.previousElementSibling){
        if(child===node)continue;
        const found=descend(child,x,own,depth+1);
        if(found){result=found;break;}
      }
      if(!result)return null;
      const opacity=Number(css.opacity);
      return result.map((v,i)=>v*opacity+background[i]*(1-opacity));
    }
    const samples=[];
    for(const fraction of [0.5,0.25,0.75,0.05,0.95]){
      if(exhausted())break;
      samples.push(descend(body,root.clientWidth*fraction,bodyBase,0) || base);
    }
    // Choose the most common edge background rather than averaging footer
    // text or a narrow inset panel into a color that matches neither surface.
    let winner=samples[0] || base, votes=0;
    for(const candidate of samples){
      const count=samples.filter(sample=>sample.every((v,i)=>Math.abs(v-candidate[i])<=3)).length;
      if(count>votes){winner=candidate;votes=count;}
    }
    if(bottomCanvas) {
      const css=getComputedStyle(bottomCanvas),r=bottomCanvas.getBoundingClientRect();
      if(css.visibility!=='visible' || css.display==='none' || css.opacity==='0' ||
         r.width<root.clientWidth*0.9 || Math.abs(r.bottom+scrollY-bottom)>2)bottomCanvas=null;
      else if(watched.size<32)watched.add(bottomCanvas);
    }
    return {color:`rgb(${winner.map(Math.round).join(',')})`,canvas:bottomCanvas,watched,cost:performance.now()-started};
  }
  function fillState() {
    const end=document.scrollingElement?.scrollHeight;
    const exposed=nativeFill && preparedRGB && Number.isFinite(end) && scrollY+innerHeight+height>end;
    return {exposed:!!exposed,rgb:preparedRGB};
  }
  function reportFill() {
    const state=fillState(), key=JSON.stringify(state);
    if(key===lastFillState)return;
    lastFillState=key;
    globalThis.__talariaWebKitBridge?.reportFooterFill?.(state);
  }
  function remove() { preparedRGB=null; reportFill(); node?.remove(); node=null; height=0;canvasSurface=null;colorObserver.disconnect();colorResizeObserver.disconnect();colorTargets.clear(); }
  function refresh() {
    if(disposed)return;
    lastUpdate=performance.now();
    const root=document.documentElement, body=document.body;
    if(root!==observedRoot || body!==observedBody) {
      resizeObserver.disconnect(); attributesObserver.disconnect(); observedRoot=root; observedBody=body;
      for(const target of [root,body])if(target){resizeObserver.observe(target);attributesObserver.observe(target,{attributes:true,attributeFilter:['style','class','bgcolor','hidden']});}
    }
    if((!enabled && !nativeFill) || !root || !body) {remove();return;}
    const rs=getComputedStyle(root), bs=getComputedStyle(body);
    // Don't introduce an outer scrollbar around a scroll-locked app or modal.
    if([rs.overflowY,bs.overflowY].some(x=>/^(hidden|clip)$/.test(x)) || bs.position==='fixed') {remove();return;}
    const br=body.getBoundingClientRect(), rr=root.getBoundingClientRect();
    // The spacer is outside body and out of flow: none of these measurements
    // include it. Measuring never removes a visible spacer or clamps scrollTop.
    // In quirks mode body.scrollHeight aliases the viewport's scroll range,
    // which includes our sibling spacer. Use flow boxes instead of that alias.
    const bodyOverflow=document.compatMode==='CSS1Compat'
      ? br.top+scrollY+(parseFloat(bs.borderTopWidth)||0)+body.scrollHeight : 0;
    const bottom=Math.max(innerHeight,rr.bottom+scrollY,br.bottom+scrollY+(parseFloat(bs.marginBottom)||0),bodyOverflow);
    // An out-of-flow page may have no measurable document-flow end. Avoid
    // placing our fill over its content or inventing a second scroll container.
    const ownBottom=node?.isConnected ? node.getBoundingClientRect().bottom+scrollY : 0;
    if((document.scrollingElement?.scrollHeight ?? root.scrollHeight)>Math.max(bottom,ownBottom)+1){remove();return;}
    const origin=rs.position!=='static' || rs.transform!=='none' || rs.filter!=='none'
      ? rr.top+scrollY+(parseFloat(rs.borderTopWidth)||0) : 0;
    height=Math.max(0,range*innerWidth/Math.max(1,nativeWidth));
    if(!height){remove();return;}
    if(!node) {
      node=document.createElement('div');
      node.setAttribute('aria-hidden','true'); node.inert=true;
      node.style.cssText='all:initial!important;position:absolute!important;display:block!important;box-sizing:border-box!important;left:0!important;margin:0!important;padding:0!important;border:0!important;min-height:0!important;max-height:none!important;min-width:0!important;max-width:none!important;pointer-events:none!important;contain:strict!important;overflow:hidden!important;visibility:visible!important;opacity:1!important;transform:none!important;';
      set('background-color',fallbackColor);
    }
    node.toggleAttribute('data-talaria-document-footer',!nativeFill);
    // Native WebKit owns the extra scroll area. This zero-size color probe
    // resolves Canvas without painting or changing document scroll geometry.
    set('position',nativeFill ? 'fixed' : 'absolute');
    set('top',nativeFill ? '0' : `${bottom-origin}px`);
    set('height',nativeFill ? '0' : `${height}px`);
    set('width',nativeFill ? '0' : `${root.clientWidth}px`);
    set('color-scheme',rs.colorScheme);set('color','Canvas');
    if(node.parentNode!==root || root.lastElementChild!==node)root.append(node);
    const sample=documentColor(bottom,root,body,rs,bs,rr,br);colorCost=sample.cost;
    const rgb=sample.color.match(/^rgb\(([\d.]+),\s*([\d.]+),\s*([\d.]+)\)$/);
    preparedRGB=rgb ? rgb.slice(1).map(Number) : null;
    if(sample.canvas) {
      const c=sample.canvas,r=c.getBoundingClientRect();
      const key=surfaceKey(c,r,bottom,rs.colorScheme,sample.color);
      if(canvasSurface?.element!==c || canvasSurface.key!==key)
        canvasSurface={element:c,key,token:++surfaceSerial,bottom,color:sample.color,version:surfaceStyleVersion};
      if(canvasSample?.element.deref()!==c || canvasSample.key!==key)canvasSample=null;
    } else {canvasSurface=null;canvasSample=null;}
    set('background-color',sample.color);
    set('background-image',canvasSample?.image || 'none');
    // scrollHeight is integer-rounded; layout and composited edges can be
    // fractional. Cover that subpixel seam with ink overflow only, keeping
    // the spacer box, hit testing and document scroll range unchanged.
    set('box-shadow',nativeFill ? 'none' : `0 -1px 0 0 ${sample.color}`);
    // Border-image paints outside the box without extending scroll overflow.
    // Unlike a solid shadow it also continues each column of a sampled gradient.
    set('border-image',canvasSample ? `${canvasSample.image} 1 / 1px 0 0 / 1px 0 0 stretch` : 'none');
    if(canvasSample)set('box-shadow','none');
    const changed=sample.watched.size!==colorTargets.size || [...sample.watched].some(target=>!colorTargets.has(target));
    if(changed){
      colorObserver.disconnect();
      for(const target of colorTargets)if(!sample.watched.has(target))colorResizeObserver.unobserve(target);
      for(const target of sample.watched)if(target!==root && target!==body){
        colorObserver.observe(target,{attributes:true,attributeFilter:['class','style','hidden','bgcolor','width','height']});
        if(!colorTargets.has(target))colorResizeObserver.observe(target);
      }
      colorTargets=sample.watched;
    }
    reportFill();
  }
  function schedule() {
    if(timer || disposed)return;
    timer=setTimeout(()=>{timer=0;refresh();},Math.max(0,Math.max(200,colorCost*100)-(performance.now()-lastUpdate)));
  }
  const styleChanged=()=>{surfaceStyleVersion++;schedule();};
  const colorObserver=new MutationObserver(styleChanged);
  const colorResizeObserver=new ResizeObserver(schedule);
  const resizeObserver=new ResizeObserver(schedule);
  const attributesObserver=new MutationObserver(styleChanged);
  // Observe structural changes only; ignore all style/attribute churn. The
  // callback does constant work and coalesces busy pages to at most five reads/s.
  const mutationObserver=new MutationObserver(schedule);
  mutationObserver.observe(document,{childList:true,subtree:true});
  window.addEventListener('resize',schedule,{passive:true});
  const appearance=matchMedia('(prefers-color-scheme: dark)');appearance.addEventListener('change',schedule);
  const styleLoaded=event=>{if(event.target.tagName==='LINK')schedule();};
  document.addEventListener('load',styleLoaded,true);
  const styleSettled=event=>{if(colorTargets.has(event.target))schedule();};
  document.addEventListener('transitionend',styleSettled,true);document.addEventListener('animationend',styleSettled,true);
  // Reuse the prepared color; scroll events only check whether blank space is
  // exposed. Notify native code on state changes, without sampling or polling.
  const scrolled=()=>{lastScrollActivity=performance.now();if(nativeFill)reportFill();};
  window.addEventListener('scroll',scrolled,{passive:true});
  globalThis.__talariaDocumentFooter={
    canvasSampleRequest() {
      if(nativeFill || !enabled || !node?.isConnected || !canvasSurface)return null;
      const busy={documentExtension:true,busy:true};
      if(canvasSample || canvasSurface.version!==surfaceStyleVersion || document.visibilityState!=='visible' || performance.now()-lastScrollActivity<150)return busy;
      const c=canvasSurface.element;
      if(!c.isConnected)return busy;
      const r=c.getBoundingClientRect(),edge=canvasSurface.bottom-scrollY;
      const key=surfaceKey(c,r,canvasSurface.bottom,getComputedStyle(document.documentElement).colorScheme,canvasSurface.color);
      if(key!==canvasSurface.key){schedule();return busy;}
      if(edge<3 || edge>innerHeight || Math.abs(r.bottom-edge)>2)return busy;
      // Do not cache a cookie modal's dimmer or a fixed control over the canvas.
      for(const fraction of [0.1,0.5,0.9]) {
        let depth=0;
        for(let p=document.elementFromPoint(document.documentElement.clientWidth*fraction,edge-2);p && depth++<32;p=p.parentElement)
          if(['fixed','sticky'].includes(getComputedStyle(p).position))return busy;
      }
      return {documentExtension:true,token:canvasSurface.token,sampleBottom:edge-1,
        contentWidth:document.documentElement.clientWidth,viewState:[innerWidth,innerHeight,scrollX,scrollY],
        deviceScale:devicePixelRatio,captureReady:true};
    },
    acceptCanvasSample(sample) {
      const request=this.canvasSampleRequest();
      if(!request?.captureReady || sample.token!==request.token ||
         JSON.stringify(sample.viewState)!==JSON.stringify(request.viewState) ||
         !Array.isArray(sample.colors) || sample.colors.length!==32 ||
         sample.colors.some(c=>!Array.isArray(c) || c.length!==3 || c.some(v=>!Number.isFinite(v)||v<0||v>255)))return false;
      const image=`linear-gradient(to right,${sample.colors.map((c,i)=>`rgb(${c.map(Math.round).join(',')}) ${i*100/31}%`).join(',')})`;
      canvasSample={element:new WeakRef(canvasSurface.element),key:canvasSurface.key,image};
      set('background-image',image);set('box-shadow','none');
      set('border-image',`${image} 1 / 1px 0 0 / 1px 0 0 stretch`);
      return true;
    },
    configure(config) {
      nativeFill=!!config.nativeFill;enabled=!!config.enabled;range=Math.max(0,Number(config.height)||0);nativeWidth=Math.max(1,Number(config.width)||1);
      if(typeof config.fallbackColor==='string')fallbackColor=config.fallbackColor;
      if(timer){clearTimeout(timer);timer=0;}refresh();return true;
    },
    refresh,
    preparedColor() { return nativeFill ? preparedRGB : null; },
    fillState,
    sampleBottom() {
      // Never sample our own fill and feed it back as the page's new color.
      return !nativeFill && node?.isConnected ? Math.max(1,Math.min(innerHeight,node.getBoundingClientRect().top)) : innerHeight;
    },
    isScrolling(quietMS=150){return performance.now()-lastScrollActivity<Math.max(150,quietMS);},
    dispose(){disposed=true;clearTimeout(timer);resizeObserver.disconnect();attributesObserver.disconnect();mutationObserver.disconnect();
      appearance.removeEventListener('change',schedule);document.removeEventListener('load',styleLoaded,true);
      document.removeEventListener('transitionend',styleSettled,true);document.removeEventListener('animationend',styleSettled,true);
      window.removeEventListener('resize',schedule);window.removeEventListener('scroll',scrolled);remove();convertedColors.clear();colorCanvas=null;canvasSample=null;}
  };
})

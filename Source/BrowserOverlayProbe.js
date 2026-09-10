/* Read-only, isolated-world inspection. No document-wide queries or observers.
 * Scans yield after 3ms of work; native scheduling also charges
 * the reported CPU time before starting another scan. Browser-level hit tests
 * supplement the sampled DOM pass for closed shadows and pointer-events:none.
 * This expression is also called on a CDP-resolved node with candidate:true.
 */
(async function (config) {
  'use strict';
  let cpuMS = 0, sliceStart = performance.now(), maxSliceMS = 0, samples = 0;
  const started = sliceStart;
  const charge = () => { const elapsed = performance.now() - sliceStart; cpuMS += elapsed; maxSliceMS = Math.max(maxSliceMS, elapsed); };
  const finish = (obstructed, extra = {}) => { charge(); return {obstructed, cpuMS, maxSliceMS, samples, viewState:[innerWidth,innerHeight,scrollX,scrollY], ...extra}; };
  try {
    const win = window, doc = document;
    const initial = [innerWidth, innerHeight, scrollX, scrollY];
    const styles = new WeakMap(), anchors = new WeakMap(), paints = new WeakMap();
    const pinnedViews = new WeakSet(), framePins = new WeakMap(), viewportLayouts = new WeakMap();
    if (config.allowFrame && config.viewportPinned === true) pinnedViews.add(window);
    let incomplete = false;
    const parent = el => el.assignedSlot || el.parentElement || el.getRootNode().host || null;
    const style = el => { if (!styles.has(el)) styles.set(el, el.ownerDocument.defaultView.getComputedStyle(el)); return styles.get(el); };
    const appSurfaces = new WeakMap();
    function viewportApp(el) {
      const view=el.ownerDocument.defaultView;
      // Embedded maps must not change the containing document's chrome.
      if(view!==top)return false;
      const cached=view.__talariaViewportApp?.deref();
      const canvas=el.localName==='canvas' ? el : cached;
      if(!canvas || !canvas.isConnected || canvas.ownerDocument!==doc)return false;
      if(appSurfaces.has(canvas))return appSurfaces.get(canvas);
      appSurfaces.set(canvas,false);
      const root=doc.scrollingElement, body=doc.body;
      if(!root || !body || Math.abs(view.scrollY)>2 || Math.abs(view.scrollX)>2)return false;
      const locked=[style(doc.documentElement),style(body)].some(css=>/^(hidden|clip)$/.test(css.overflowY) || css.position==='fixed');
      if(!locked && root.scrollHeight>view.innerHeight+2)return false;
      const covers=rect=>rect.width>=view.innerWidth*0.7 && rect.height>=view.innerHeight*0.75 &&
        rect.top<=view.innerHeight*0.2 && rect.bottom>=view.innerHeight-2 &&
        rect.left<view.innerWidth*0.5 && rect.right>view.innerWidth*0.5;
      let exposed=canvas.getBoundingClientRect();
      if(!covers(exposed) || !visible(canvas))return false;
      let application=false, count=0;
      for(let p=parent(canvas);p;p=parent(p)) {
        if(++count>32 || performance.now()-sliceStart>3){incomplete=true;return false;}
        const role=(p.getAttribute('role') || '').split(/\s+/);
        // Application semantics (Maps) or a canvas UI host (Flutter/Earth).
        // A decorative canvas, video or fullscreen background is insufficient.
        if((role.includes('application') || p.localName==='flutter-view') && covers(p.getBoundingClientRect()))application=true;
        const css=style(p);
        if(/^(auto|scroll|overlay)$/.test(css.overflowY) && p.scrollHeight>p.clientHeight+2)return false;
        const paintClip=/paint|strict|content/.test(css.contain);
        const clipX=paintClip || /^(hidden|clip|auto|scroll|overlay)$/.test(css.overflowX);
        const clipY=paintClip || /^(hidden|clip|auto|scroll|overlay)$/.test(css.overflowY);
        if(clipX || clipY) {
          // Root overflow clips the viewport, including documents whose fixed
          // body leaves a zero-height html layout box (canvas UI frameworks).
          const rect=p===doc.documentElement ? {left:0,top:0,right:view.innerWidth,bottom:view.innerHeight} : p.getBoundingClientRect();
          const left=clipX ? Math.max(exposed.left,rect.left) : exposed.left;
          const right=clipX ? Math.min(exposed.right,rect.right) : exposed.right;
          const top=clipY ? Math.max(exposed.top,rect.top) : exposed.top;
          const bottom=clipY ? Math.min(exposed.bottom,rect.bottom) : exposed.bottom;
          exposed={left,right,top,bottom,width:right-left,height:bottom-top};
          if(!covers(exposed))return false;
        }
      }
      if(application) {
        appSurfaces.set(canvas,true);
        // Keep the layout classification through panning and transient controls.
        // Revalidate geometry/semantics each pass; never retain a removed canvas.
        view.__talariaViewportApp=new WeakRef(canvas);
      }
      return application;
    }
    const layoutPins = new WeakMap();
    function viewportLayoutContent(el) {
      // Flex/grid app chrome can be stationary without fixed/sticky positioning.
      // Only classify an actual text/control hit, not the full-page background.
      const view=el.ownerDocument.defaultView, root=doc.scrollingElement;
      if(view!==top || !root || !doc.body || Math.abs(view.scrollY)>2 || Math.abs(view.scrollX)>2)return false;
      if(root.scrollHeight>view.innerHeight+2 || root.scrollWidth>view.innerWidth+2)return false;
      if(![style(doc.documentElement),style(doc.body)].some(css=>/^(hidden|clip)$/.test(css.overflowY)))return false;
      let boxElement=el, wrappers=0;
      // Hit testing may return a display:contents span (Gemini's link label).
      // Its nearest box owns the geometry, while the original hit owns text.
      while(boxElement && style(boxElement).display==='contents' && wrappers++<8)boxElement=parent(boxElement);
      if(!boxElement || style(boxElement).display==='contents')return false;
      const rect=boxElement.getBoundingClientRect();
      if(rect.width<6 || rect.height<6 || rect.height>view.innerHeight*0.3 || rect.top<view.innerHeight*0.7)return false;
      let content=false, controlDepth=0;
      for(let p=el;p && controlDepth++<8;p=parent(p)) {
        if(['button','input','select','textarea'].includes(p.localName) ||
           (p.localName==='a' && p.hasAttribute('href')) ||
           /^(button|textbox|combobox|slider|checkbox|link)$/.test(p.getAttribute('role') || '')){content=true;break;}
      }
      if(!content && alpha(style(el).color)>0.02) {
        let count=0;
        for(const child of el.childNodes) {
          if(++count>32)break;
          if(child.nodeType===3 && /\S/.test(child.textContent)){content=true;break;}
        }
      }
      if(!content)return false;
      if(layoutPins.has(el))return layoutPins.get(el);
      let layout=false, count=0;
      for(let p=el;p;p=parent(p)) {
        if(++count>32 || performance.now()-sliceStart>3){incomplete=true;return false;}
        const css=style(p), box=p.getBoundingClientRect();
        // Local scrolling or clipped document content is not app chrome, even
        // when its scrollbar happens to be at the end. Sibling scrollers are OK.
        if((/^(auto|scroll|overlay|hidden|clip)$/.test(css.overflowY) && p.scrollHeight>p.clientHeight+2) ||
           (/^(auto|scroll|overlay|hidden|clip)$/.test(css.overflowX) && p.scrollWidth>p.clientWidth+2))return false;
        if(css.display==='contents')continue;
        if(/^(flex|inline-flex|grid|inline-grid)$/.test(css.display) &&
           box.width>=rect.width && box.height>=view.innerHeight*0.7 &&
           box.top<=view.innerHeight*0.3 && Math.abs(box.bottom-view.innerHeight)<=2)layout=true;
      }
      const result=layout;
      layoutPins.set(el,result);return result;
    }
    function visible(el) {
      if (style(el).visibility !== 'visible') return false;
      let opacity = 1, n = 0;
      for (let p = el; p; p = parent(p)) {
        if (++n > 64) { incomplete = true; return false; }
        const css = style(p); opacity *= Number(css.opacity);
        if (opacity <= 0.02 || css.display === 'none' || css.contentVisibility === 'hidden') return false;
      }
      return true;
    }
    function alpha(color) {
      if (!color || color === 'transparent') return 0;
      const rgba = color.match(/^rgba\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\)$/);
      const slash = color.match(/\/\s*([\d.]+)(%)?\s*\)$/);
      return rgba ? Number(rgba[1]) : slash ? Number(slash[1]) / (slash[2] ? 100 : 1) : 1;
    }
    function painted(el) {
      if (paints.has(el)) return paints.get(el);
      const css = style(el), tag = el.localName;
      let result = alpha(css.backgroundColor) > 0.02 || css.backgroundImage !== 'none' || css.boxShadow !== 'none' ||
        ['button','input','select','textarea','canvas','video','iframe','object','embed','svg'].includes(tag) ||
        (tag === 'img' && el.naturalWidth > 0) ||
        ['Top','Right','Bottom','Left'].some(side => parseFloat(css['border'+side+'Width']) > 0 && alpha(css['border'+side+'Color']) > 0.02);
      if (!result && alpha(css.color) > 0.02) {
        let count = 0;
        for (const child of el.childNodes) {
          if (++count > 32) break;
          if (child.nodeType === 3 && /\S/.test(child.textContent)) { result = true; break; }
        }
      }
      paints.set(el, result); return result;
    }
    function shell(rect, view) { return rect.width >= view.innerWidth * 0.9 && rect.height >= view.innerHeight * 0.85; }
    function containingBlock(css) {
      return css.transform !== 'none' || css.perspective !== 'none' || css.filter !== 'none' ||
        css.backdropFilter !== 'none' || /layout|paint|strict|content/.test(css.contain) ||
        /transform|perspective|filter/.test(css.willChange) || css.contentVisibility === 'auto';
    }
    function viewportFixed(el) {
      let count = 0;
      for (let p = parent(el); p; p = parent(p)) {
        if (++count > 64) { incomplete = true; return false; }
        if (containingBlock(style(p))) {
          for (let outer = p; outer; outer = parent(outer)) {
            if (++count > 64) { incomplete = true; return false; }
            if (style(outer).position === 'fixed') return viewportFixed(outer);
          }
          return false;
        }
      }
      return true;
    }
    function bottomSticky(el, css) {
      if (css.bottom === 'auto') return false;
      let edge = el.ownerDocument.defaultView.innerHeight, count = 0;
      for (let p = parent(el); p; p = parent(p)) {
        if (++count > 64) { incomplete = true; return false; }
        if (/auto|scroll|hidden|overlay/.test(style(p).overflowY)) {
          edge = p.getBoundingClientRect().top + p.clientTop + p.clientHeight; break;
        }
      }
      return Math.abs(el.getBoundingClientRect().bottom - edge + (parseFloat(css.bottom) || 0)) <= 2;
    }
    function fillsViewport(rect, view) {
      return rect.left <= 2 && rect.top <= 2 && rect.right >= view.document.documentElement.clientWidth - 2 && rect.bottom >= view.innerHeight - 2;
    }
    // An inherited frame anchor applies only to the frame's viewport layout,
    // never to a footer at the end of a scrolling document or a local container.
    function viewportLayout(el) {
      if (viewportLayouts.has(el)) return viewportLayouts.get(el);
      const view=el.ownerDocument.defaultView, root=el.ownerDocument.scrollingElement;
      let valid=!!root && root.scrollHeight<=root.clientHeight+2 && root.scrollWidth<=root.clientWidth+2 &&
        Math.abs(view.scrollY)<=2 && Math.abs(view.scrollX)<=2, count=0;
      for(let p=parent(el);valid && p;p=parent(p)) {
        if(++count>64){incomplete=true;valid=false;break;}
        const css=style(p), rect=p.getBoundingClientRect();
        if ((/auto|scroll|hidden|overlay/.test(css.overflowY) && p.scrollHeight>p.clientHeight+2) ||
            (/auto|scroll|hidden|overlay/.test(css.overflowX) && p.scrollWidth>p.clientWidth+2)) valid=false;
        if ((css.position!=='static' || containingBlock(css)) &&
            (!fillsViewport(rect,view) || Math.abs(rect.top)>2 || Math.abs(rect.bottom-view.innerHeight)>2)) valid=false;
      }
      viewportLayouts.set(el,valid);return valid;
    }
    function framePinned(el) {
      if(framePins.has(el))return framePins.get(el);
      let result=false, count=0;
      for(let p=el;p;p=parent(p)) {
        if(++count>64){incomplete=true;break;}
        const css=style(p);
        if((/auto|scroll|hidden|overlay/.test(css.overflowY) && p.scrollHeight>p.clientHeight+2) ||
           (/auto|scroll|hidden|overlay/.test(css.overflowX) && p.scrollWidth>p.clientWidth+2))break;
        // Fullscreen fixed shells are valid frame anchors, but are not by
        // themselves obstructions. The child still needs a bounded painted panel.
        if(css.position==='fixed'){result=viewportFixed(p);break;}
        if(pinnedViews.has(el.ownerDocument.defaultView) && viewportLayout(el)){result=true;break;}
      }
      framePins.set(el,result);return result;
    }
    function anchored(el) {
      if (anchors.has(el)) return anchors.get(el);
      let count = 0, panel = false, result = false;
      const view = el.ownerDocument.defaultView;
      for (let p = el; p; p = parent(p)) {
        if (++count > 64) { incomplete = true; break; }
        const css = style(p), rect = p.getBoundingClientRect();
        const bounded = rect.width >= 6 && rect.height >= 6 && !shell(rect, view);
        if (bounded && css.position === 'absolute' && css.bottom !== 'auto') {
          panel = true;
          if(pinnedViews.has(view) && Math.abs(rect.bottom-view.innerHeight+(parseFloat(css.bottom)||0))<=2 && viewportLayout(p)) {
            result=true;break;
          }
        }
        if (css.position === 'fixed' && (bounded || panel) && viewportFixed(p)) { result = true; break; }
        if (bounded && css.position === 'sticky' && bottomSticky(p, css)) { result = true; break; }
      }
      anchors.set(el, result); return result;
    }
    function frameAt(el, x, y) {
      if (!['iframe','frame'].includes(el.localName)) return null;
      const rect = el.getBoundingClientRect(), view = el.ownerDocument.defaultView;
      if (rect.width < 6 || rect.height < 6) return null;
      // A fixed control in an ordinary embedded document is not viewport-fixed
      // in the containing page. Recurse only into anchored or full-view frames.
      const fills = fillsViewport(rect,view);
      if (!fills && !anchored(el)) return null;
      const sx = el.offsetWidth ? rect.width / el.offsetWidth : 1;
      const sy = el.offsetHeight ? rect.height / el.offsetHeight : 1;
      return {x:(x - rect.left)/sx - el.clientLeft, y:(y - rect.top)/sy - el.clientTop,
        viewportPinned:fills && framePinned(el),scaleY:sy,coverage:Math.min(1,rect.width/view.innerWidth)};
    }
    function bannerColor(el, y) {
      const began=performance.now(), view=el.ownerDocument.defaultView;
      let panel=null, count=0;
      for(let p=el;p && p!==p.ownerDocument.body && p!==p.ownerDocument.documentElement;p=parent(p)) {
        if(++count>32 || performance.now()-began>3)break;
        const css=style(p), rect=p.getBoundingClientRect();
        if(rect.width>=view.innerWidth*0.65 && !shell(rect,view) && anchored(p) &&
            (alpha(css.backgroundColor)>0.02 || css.backgroundImage!=='none' || ['iframe','canvas','video','img'].includes(p.localName)))panel=p;
      }
      if(!panel)return null;
      const rect=panel.getBoundingClientRect();
      const ids=view.__talariaBannerIDs ||= {nodes:new WeakMap(),next:0};
      if(!ids.nodes.has(panel))ids.nodes.set(panel,++ids.next);
      const result={id:ids.nodes.get(panel),coverage:Math.min(1,rect.width/view.innerWidth),
        edgeDelta:Math.min(view.innerHeight-1,Math.max(rect.top+1,rect.bottom-4))-y,capture:true};
      let rgb=[0,0,0], opacity=0, complex=['iframe','canvas','video','img','svg'].includes(panel.localName);
      for(const pseudo of ['::before','::after']){
        const decoration=view.getComputedStyle(panel,pseudo);
        if(decoration.content!=='none' && decoration.content!=='normal' && decoration.display!=='none' &&
          (alpha(decoration.backgroundColor)>0.02 || decoration.backgroundImage!=='none'))complex=true;
      }
      count=0;
      for(let p=panel;p;p=parent(p)) {
        if(++count>32 || performance.now()-began>3)return result;
        const css=style(p), match=css.backgroundColor.match(/^rgba?\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\s*\)$/);
        if(opacity<0.999 && (css.backgroundImage!=='none' || !match))complex=true;
        if(css.filter!=='none' || css.backdropFilter!=='none' || css.mixBlendMode!=='normal')complex=true;
        if(match){
          const a=match[4]===undefined?1:Number(match[4]), weight=(1-opacity)*a;
          rgb=rgb.map((v,i)=>v+Number(match[i+1])*weight);opacity+=weight;
        }
        const groupOpacity=Number(css.opacity);rgb=rgb.map(v=>v*groupOpacity);opacity*=groupOpacity;
      }
      if(!complex && opacity>0.999){result.rgb=rgb.map(Math.round);result.capture=false;}
      return result;
    }
    function scaleBanner(result, scale, coverage) {
      if(result.banner)result.banner={...result.banner,edgeDelta:result.banner.edgeDelta*scale,coverage:result.banner.coverage*coverage};
      return result;
    }
    function inspect(el, x, y, depth = 0) {
      if (!el || el.nodeType !== 1 || !visible(el)) return {obstructed:false};
      if (depth > 6) { incomplete = true; return {obstructed:null}; }
      if (el.shadowRoot) {
        const inner = el.shadowRoot.elementFromPoint(x,y);
        if (inner && inner !== el && inner.getRootNode() === el.shadowRoot) return inspect(inner,x,y,depth+1);
      }
      const frame = frameAt(el,x,y);
      if (frame) {
        let child = null;
        try { child = el.contentDocument; } catch (_) { /* Opaque frame uses CDP. */ }
        // A native owner hit must enter the child through native hit-testing too,
        // so a closed shadow inside an accessible frame is not lost to JS recursion.
        if (child && !config.candidate) {
          if(frame.viewportPinned)pinnedViews.add(child.defaultView);
          return scaleBanner(inspect(child.elementFromPoint(frame.x,frame.y),frame.x,frame.y,depth+1),frame.scaleY,frame.coverage);
        }
        // Bounded anchored frame is itself content the bar would cover.
        if (anchored(el) && !shell(el.getBoundingClientRect(),el.ownerDocument.defaultView)) return {obstructed:true,banner:bannerColor(el,y)};
        return {obstructed:null, frame};
      }
      // A hit on transparent padding still covers the painted fixed panel
      // behind it. Stop at the anchor boundary so an empty transparent overlay
      // cannot borrow the ordinary document's background (or a fullscreen shell).
      let obstructed=false, count=0;
      for(let p=el;p && anchored(p);p=parent(p)) {
        if(++count>32 || performance.now()-sliceStart>3){incomplete=true;break;}
        if(style(p).visibility==='visible' && painted(p)){obstructed=true;break;}
      }
      // A real banner above the application still owns the continuation color.
      if(obstructed)return {obstructed:true,banner:bannerColor(el,y)};
      if(viewportApp(el))return {obstructed:true,reason:'viewport-app'};
      return viewportLayoutContent(el) ? {obstructed:true,reason:'viewport-layout'} : {obstructed:false};
    }
    if (config.candidate) {
      let node = this;
      if (node?.nodeType === 3) node = node.parentElement;
      let x=config.x, y=config.y, scale=1, coverage=1;
      if (!config.allowFrame && node?.ownerDocument.defaultView !== top) {
        const owners=[];
        for(let view=node.ownerDocument.defaultView;view!==top;) {
          const owner=view.frameElement;
          if(!owner) return finish(null,{reason:'frame-owner-unavailable'});
          owners.push(owner); view=owner.ownerDocument.defaultView;
          if(owners.length>6) return finish(null);
        }
        for(const owner of owners.reverse()) {
          // Validate outside-in so cached eligibility sees the inherited anchor.
          const point=frameAt(owner,x,y); if(!point)return finish(false);
          x=point.x; y=point.y;scale*=point.scaleY;coverage*=point.coverage;
          if(point.viewportPinned && owner.contentDocument)pinnedViews.add(owner.contentDocument.defaultView);
        }
      }
      const result = scaleBanner(inspect(node,x,y),scale,coverage);
      return finish(incomplete ? null : result.obstructed, {banner:result.banner,reason:result.reason,...(result.frame ? {frame:result.frame} : {})});
    }
    if (![config.left,config.bottom,config.width,config.height,config.currentWidth,config.currentHeight].every(Number.isFinite) ||
        config.width <= 0 || config.height <= 0 || config.currentWidth <= 0 || config.currentHeight <= 0) return finish(null);
    const sx = innerWidth/config.currentWidth, sy = innerHeight/config.currentHeight;
    const band = {left:Math.max(0,config.left*sx),right:Math.min(innerWidth,(config.left+config.width)*sx),
      top:Math.max(0,innerHeight-(config.bottom+config.height)*sy),bottom:Math.min(innerHeight,innerHeight-config.bottom*sy)};
    if (band.right <= band.left || band.bottom <= band.top) return finish(null);
    const points = [], fallbacks = [];
    function add(x,y) { points.push({x:Math.floor(x),y:Math.floor(y)}); }
    const midX=(band.left+band.right)/2, midY=(band.top+band.bottom)/2;
    // Short banners may overlap only the bottom few pixels of the bar. Always
    // prioritize that edge, alternating the other levels in quick passes.
    add(midX,band.bottom-0.5); add(midX,midY); add(midX,band.top+0.5);
    const rows=Math.min(8,Math.max(2,Math.ceil((band.bottom-band.top)/16)+1));
    const columns=Math.min(Math.floor(253/rows),Math.max(2,Math.ceil((band.right-band.left)/16)+1));
    for(let row=0;row<rows;row++) for(let col=0;col<columns;col++)
      add(band.left+0.5+(band.right-band.left-1)*col/(columns-1),band.top+0.5+(band.bottom-band.top-1)*row/(rows-1));
    let cursor = Number.isInteger(config.cursor) ? config.cursor : 0;
    const scanPoints = config.quick ? [points[0],points[1+cursor%2],points[cursor++%points.length]] : points;
    // Quick scans prioritize common banners and rotate across smaller controls.
    // A negative quick scan is not a full clear proof; native owns that policy.
    // Rotate secondary points to cover hosts ordinary JavaScript cannot pierce.
    // Remembering a previous positive point lets native confirm it immediately.
    const hint = config.hint ? {x:config.hint.x,y:innerHeight-config.hint.bottom} : null;
    if (hint && hint.x >= band.left && hint.x < band.right && hint.y >= band.top && hint.y < band.bottom) {
      fallbacks.push(hint);
      if (config.quick) scanPoints[1]=hint;
    }
    // Closed shadows and pointer-events:none need the same bottom-edge priority;
    // rotating every fallback would postpone shallow banners by many polls.
    if (!fallbacks.some(p=>p.x===points[0].x && p.y===points[0].y)) fallbacks.push(points[0]);
    for(let i=0;i<scanPoints.length;i++) {
      const point=scanPoints[i]; samples++;
      const result=inspect(doc.elementFromPoint(point.x,point.y),point.x,point.y);
      if(result.obstructed) return finish(true,{point,banner:result.banner,reason:result.reason,viewport:{width:innerWidth,height:innerHeight}});
      if(result.frame && !config.quick && fallbacks.length<3) fallbacks.push(point);
      if(performance.now()-sliceStart >= 3) {
        charge();
        // A native navigation snapshot or an occluded window can stop animation
        // frames. Keep the inspection responsive without counting this wait as
        // CPU work, and release both callbacks whichever one resumes us first.
        await new Promise(resolve=>{
          let frame, timer;
          const resume=()=>{cancelAnimationFrame(frame);clearTimeout(timer);resolve();};
          frame=requestAnimationFrame(resume);timer=setTimeout(resume,32);
        });
        sliceStart=performance.now();
        if(performance.now()-started>2000 || innerWidth!==initial[0] || innerHeight!==initial[1] || scrollX!==initial[2] || scrollY!==initial[3]) return finish(null);
      }
    }
    // Quick passes use only the known hit and bottom-center browser hit tests.
    // Broad/opaque banners stay responsive without paying for three CDP probes
    // on every empty-page poll. Full scans retain the rotating fallbacks.
    while(!config.quick && fallbacks.length<3) { fallbacks.push(points[cursor%points.length]); cursor++; }
    return finish(incomplete ? null : false,{fallbacks,cursor:cursor%points.length,viewport:{width:innerWidth,height:innerHeight}});
  } catch (_) { return finish(null); }
})

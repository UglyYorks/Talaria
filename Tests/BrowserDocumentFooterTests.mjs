#!/usr/bin/env node
// Real Chromium, no npm dependencies. Node 22+; override Chrome with CHROME_BIN.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {once} from 'node:events';
import {createServer} from 'node:http';
const chrome=process.env.CHROME_BIN || ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','/usr/bin/chromium','/usr/bin/google-chrome'].find(existsSync);
assert.ok(chrome && globalThis.WebSocket,'Requires Chrome/Chromium and Node 22+');
const source=await readFile(new URL('../Source/BrowserDocumentFooter.js',import.meta.url),'utf8');
const pages=new Map();
const server=createServer((q,r)=>{r.setHeader('Content-Type','text/html');r.end(pages.get(q.url) || '<!doctype html><body>empty')});
server.listen(0,'0.0.0.0');await once(server,'listening');
const port=server.address().port, origin=`http://127.0.0.1:${port}`, cross=`http://localhost:${port}`;
const siblingServer=createServer(server.listeners('request')[0]);
siblingServer.listen(0,'127.0.0.1');await once(siblingServer,'listening');
const sibling=`http://127.0.0.1:${siblingServer.address().port}`;
const profile=await mkdtemp(tmpdir()+'/talaria-overlay-');
const child=spawn(chrome,['--headless=new','--remote-debugging-port=0',`--user-data-dir=${profile}`,'--no-first-run','--disable-background-networking','--disable-component-update','--disable-extensions','about:blank'],{stdio:['ignore','ignore','pipe']});
let ws, sequence=0, count=0;
const pending=new Map();
try {
  const address=await new Promise((resolve,reject)=>{
    let log='';const timer=setTimeout(()=>reject(new Error('Chrome start timed out '+log.slice(-500))),15000);
    child.stderr.on('data',d=>{log+=d;const m=log.match(/DevTools listening on (ws:\/\/[^\s]+)/);if(m){clearTimeout(timer);resolve(m[1]);}});
    child.once('error',reject);child.once('exit',code=>{clearTimeout(timer);reject(new Error('Chrome exited '+code));});
  });
  ws=new WebSocket(address);await once(ws,'open');
  ws.addEventListener('message',event=>{const r=JSON.parse(event.data);const p=pending.get(r.id);if(p){pending.delete(r.id);clearTimeout(p.timer);r.error?p.reject(new Error(JSON.stringify(r.error))):p.resolve(r.result)}});
  function call(method,params={},sessionId) { return new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('CDP timed out '+method))},5000);pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params,sessionId}));}); }
  const {targetId}=await call('Target.createTarget',{url:'about:blank'});
  const {sessionId}=await call('Target.attachToTarget',{targetId,flatten:true});
  const send=(m,p)=>call(m,p,sessionId);
  await send('Page.enable');
  async function evaluate(expression,contextId) {
    const r=await send('Runtime.evaluate',{expression,contextId,returnByValue:true,awaitPromise:true,timeout:50});
    assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result?.value;
  }
  let context, generation=0;
  const config={left:100,bottom:20,width:800,height:48,currentWidth:1000,currentHeight:700,cursor:0};
  async function load(body,setup='',height=700,width=1000,quirks=false) {
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
    const path='/test-'+(++generation);
    pages.set(path,`${quirks?'':'<!doctype html>'}<style>html,body{margin:0}body{min-height:0}.fixed{position:fixed;bottom:0;left:0;right:0;height:90px;background:#eee}</style><body>${body}`);
    await send('Page.navigate',{url:origin+path});
    for(let i=0;i<100;i++){await new Promise(r=>setTimeout(r,10));if(await evaluate(`location.pathname===${JSON.stringify(path)} && document.readyState==='complete'`))break;}
    if(setup)await evaluate(setup);
    const {frameTree}=await send('Page.getFrameTree');
    context=(await send('Page.createIsolatedWorld',{frameId:frameTree.frame.id,worldName:'talaria-overlay'})).executionContextId;
  }

  const wait=ms=>new Promise(r=>setTimeout(r,ms));
  const configure=(enabled=true,height=86,width=1000)=>evaluate(`__talariaDocumentFooter.configure(${JSON.stringify({enabled,height,width,fallbackColor:'rgb(230,20,190)',duration:0.2})})`,context);
  const state=()=>evaluate(`({height:innerHeight,scrollHeight:document.scrollingElement.scrollHeight,scrollTop:scrollY,
    spacer:document.querySelector('[data-talaria-document-footer]')?.getBoundingClientRect().toJSON(),
    body:document.body.getBoundingClientRect().height})`);
  async function fixture(name,html,check,quirks=false){await load(html,'',700,1000,quirks);await evaluate(`(${source})()`,context);await check();console.log('PASS spacer: '+name);count++;}
  await fixture('real scroll range and idempotent mode switches','<style>body{height:2000px}</style>',async()=>{
    const base=await state();await configure();assert.equal((await state()).scrollHeight,base.scrollHeight+86);
    await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');await wait(30);
    const bottom=await state();assert.equal(bottom.scrollTop,1386);assert.equal(bottom.spacer.height,86);
    for(let i=0;i<20;i++)await evaluate('__talariaDocumentFooter.refresh()',context);
    assert.equal((await state()).scrollTop,bottom.scrollTop,'geometry refresh must not clamp the native scroll position');
    for(let i=0;i<20;i++){await configure(false);assert.equal((await state()).scrollHeight,2000);await configure();assert.equal((await state()).scrollHeight,2086);}
    assert.equal((await state()).height,700,'scroll extension never resizes viewport');
    await evaluate('window.prevented=null;addEventListener("wheel",e=>setTimeout(()=>prevented=e.defaultPrevented,0))');
    await send('Input.dispatchMouseEvent',{type:'mouseWheel',x:500,y:600,deltaX:0,deltaY:100});await wait(50);
    assert.equal(await evaluate('prevented'),false,'native wheel input remains uncancelled');
  });
  await fixture('short pages get space beyond the viewport','<p>Short</p>',async()=>{
    const base=await state();await configure();assert.equal((await state()).scrollHeight,base.scrollHeight+86);
  });
  await fixture('flex body keeps its layout','<style>body{display:flex;flex-direction:column;height:2000px}main{flex:1}</style><main>Content</main>',async()=>{
    const base=await state();await configure();assert.equal((await state()).body,base.body);assert.equal((await state()).scrollHeight,2086);
  });
  await fixture('dynamic growth and shrink do not accumulate space','<style>body{height:2000px}</style>',async()=>{
    await configure();await evaluate('document.body.style.height="2500px"');await wait(300);assert.equal((await state()).scrollHeight,2586);
    await evaluate('document.body.style.height="1000px"');await wait(300);assert.equal((await state()).scrollHeight,1086);
    await evaluate('document.body.outerHTML="<body style=height:1500px>Replacement</body>"');await wait(300);assert.equal((await state()).scrollHeight,1586);
  });
  await fixture('unsupported out-of-flow pages retain their original scroll range','<style>body{height:1000px}</style><div style="position:absolute;top:2000px;height:200px">Last item</div>',async()=>{
    const base=await state();await configure();assert.equal((await state()).scrollHeight,base.scrollHeight);assert.equal((await state()).spacer,undefined);
  });
  await fixture('scroll locked pages do not get an outer scrollbar','<style>html,body{height:100%;overflow:hidden}</style>',async()=>{
    await configure();assert.equal((await state()).spacer,undefined);
  });
  await fixture('root scroll locks are observed without scanning descendants','<style>body{height:2000px}</style>',async()=>{
    await configure();await evaluate('document.documentElement.style.overflow="hidden"');await wait(300);assert.equal((await state()).spacer,undefined);
    await evaluate('document.documentElement.style.overflow=""');await wait(300);assert.equal((await state()).spacer.height,86);
  });
  await fixture('idle and scroll input perform no footer geometry work','<style>body{height:2000px}</style><main></main>',async()=>{
    await configure();await wait(300);
    await evaluate('globalThis.reads=0;const original=document.body.getBoundingClientRect.bind(document.body);document.body.getBoundingClientRect=()=>{reads++;return original()}',context);
    await evaluate('for(let i=0;i<100;i++)window.dispatchEvent(new Event("scroll"))');await wait(250);
    assert.equal(await evaluate('reads',context),0,'scroll/idle never recompute the document end');
    await evaluate('const fragment=document.createDocumentFragment();for(let i=0;i<20000;i++)fragment.append(document.createElement("span"));document.querySelector("main").append(fragment)');await wait(300);
    assert.ok(await evaluate('reads<=2',context),'20,000 mutations coalesce into bounded layout reads');
    assert.equal((await state()).scrollHeight,2086);
  });
  await fixture('footer height and zoom use native points','<style>body{height:2000px}</style>',async()=>{
    await configure(true,120,2000);assert.equal((await state()).spacer.height,60);
    await configure(true,46,1000);assert.equal((await state()).spacer.height,46);
  });
  await fixture('page color is sampled above the spacer','<style>html,body{background:rgb(40,50,60)}body{height:2000px}</style>',async()=>{
    await configure();await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');await wait(50);
    const colorSource=await readFile(new URL('../Source/BrowserFooterColor.js',import.meta.url),'utf8');
    const sample=await evaluate(`(${colorSource})()`,context);assert.deepEqual(sample.rgb,[40,50,60]);assert.equal(sample.sampleBottom,614);
  });
  await fixture('quirks-mode table pages get one stable spacer','<style>body{margin:8px}</style><center><table style="height:2000px;width:85%"><tr><td>News</td></tr></table></center>',async()=>{
    assert.equal(await evaluate('document.compatMode'),'BackCompat');
    const base=await state();await configure();
    assert.equal((await state()).scrollHeight,base.scrollHeight+86);
    await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');await wait(50);
    const end=await state();assert.equal(end.spacer.height,86);
    for(let i=0;i<20;i++)await evaluate('__talariaDocumentFooter.refresh()',context);
    assert.equal((await state()).scrollHeight,end.scrollHeight,'body viewport aliases must not accumulate spacer height');
    assert.equal((await state()).scrollTop,end.scrollTop);
    for(let i=0;i<10;i++){await configure(false);assert.equal((await state()).scrollHeight,base.scrollHeight);await configure();}
    assert.equal((await state()).scrollHeight,base.scrollHeight+86);
  },true);
  await fixture('short quirks-mode page remains stable','<p>Short</p>',async()=>{
    await configure();for(let i=0;i<10;i++)await evaluate('__talariaDocumentFooter.refresh()',context);
    assert.equal((await state()).scrollHeight,786);
  },true);
  const extensionColor=()=>evaluate("getComputedStyle(document.querySelector('[data-talaria-document-footer]')).backgroundColor");
  const pondImage=color=>`url("data:image/svg+xml,${encodeURIComponent(`<svg xmlns='http://www.w3.org/2000/svg' width='1000' height='300'><path fill='${color}' d='M0 260 Q250 260 500 80 T1000 180 V300 H0Z'/></svg>`)}")`;
  await fixture('SVG background artwork owns the bottom strip','<style>body{background:rgb(17,17,17)}</style><main style="height:1500px"></main><footer style="height:300px;background-size:100% 100%"></footer>',async()=>{
    await evaluate(`document.querySelector('footer').style.backgroundImage=${JSON.stringify(pondImage('#184c8c'))}`);
    await configure();await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');await wait(350);
    const r=await evaluate('__talariaDocumentFooter.canvasSampleRequest()',context);
    assert.equal(r?.captureReady,true,'a full-width SVG background must request the same rendered fallback as canvas');
    const {data}=await send('Page.captureScreenshot',{format:'png'});
    const colors=await evaluate(`(async()=>{const b=await createImageBitmap(await(await fetch('data:image/png;base64,${data}')).blob(),0,${Math.floor(r.sampleBottom)-2},${r.contentWidth},2);
      const c=new OffscreenCanvas(32,1),x=c.getContext('2d');x.drawImage(b,0,0,32,1);b.close();const p=x.getImageData(0,0,32,1).data;
      return Array.from({length:32},(_,i)=>[...p.slice(i*4,i*4+3)]);})()`);
    assert.ok(colors.every(c=>c.every((v,i)=>Math.abs(v-[24,76,140][i])<=2)),'sample the blue painted edge, not the dark CSS background');
    assert.equal(await evaluate(`__talariaDocumentFooter.acceptCanvasSample(${JSON.stringify({...r,colors})})`,context),true);
    await evaluate('__talariaDocumentFooter.refresh()',context);
    assert.equal((await evaluate('__talariaDocumentFooter.canvasSampleRequest()',context)).busy,true,'unchanged image reuses its strip');
    await evaluate(`document.querySelector('footer').style.backgroundImage=${JSON.stringify(pondImage('#941f33'))}`);await wait(350);
    const changed=await evaluate('__talariaDocumentFooter.canvasSampleRequest()',context);
    assert.equal(changed?.captureReady,true,'image replacement invalidates cached pixels');
    assert.notEqual(changed.token,r.token);
    await evaluate("document.querySelector('footer').style.backgroundImage='none'");await wait(350);
    assert.equal(await evaluate('__talariaDocumentFooter.canvasSampleRequest()',context),null,'removing artwork restores the CSS-only path');
    assert.equal(await evaluate("getComputedStyle(document.querySelector('[data-talaria-document-footer]')).backgroundImage"),'none');
  });
  await fixture('canvas backdrop continues as a cached horizontal strip',`<main style="height:1500px"></main>
    <footer style="position:relative;height:400px;background:rgb(5,43,66)">
      <div style="position:absolute;inset:0"><canvas width="1000" height="400" style="display:block;width:100%;height:100%"></canvas></div>
      <div style="position:relative;height:100%"><div style="height:100%">Transparent content over the canvas</div></div>
    </footer>`,async()=>{
    await evaluate(`{let c=document.querySelector('canvas'),ctx=c.getContext('2d'),g=ctx.createLinearGradient(0,0,c.width,0);
      g.addColorStop(0,'rgb(240,20,30)');g.addColorStop(1,'rgb(20,40,230)');ctx.fillStyle=g;ctx.fillRect(0,0,c.width,c.height);}`);
    await configure();await wait(250);
    const request=()=>evaluate('__talariaDocumentFooter.canvasSampleRequest()',context);
    assert.equal((await request()).busy,true,'offscreen document end must not capture an unrelated viewport edge');
    await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');await wait(30);
    assert.equal((await request()).busy,true,'scrolling never starts a canvas readback');
    await wait(200);
    const r=await request();assert.equal(r.captureReady,true);
    await evaluate("document.body.insertAdjacentHTML('beforeend','<div id=dimmer style=\"position:fixed;inset:0;background:rgba(0,0,0,.5)\"></div>')");
    assert.equal((await request()).busy,true,'a fixed dimmer must not contaminate the cached canvas colors');
    await evaluate("document.querySelector('#dimmer').remove()");await wait(250);
    const {data}=await send('Page.captureScreenshot',{format:'png'});
    const colors=await evaluate(`(async()=>{const b=await createImageBitmap(await(await fetch('data:image/png;base64,${data}')).blob(),0,${Math.floor(r.sampleBottom)-2},${r.contentWidth},2);
      const c=new OffscreenCanvas(32,1),x=c.getContext('2d');x.drawImage(b,0,0,32,1);
      b.close();const p=x.getImageData(0,0,32,1).data;return Array.from({length:32},(_,i)=>[...p.slice(i*4,i*4+3)]);})()`);
    const accept=payload=>evaluate(`__talariaDocumentFooter.acceptCanvasSample(${JSON.stringify(payload)})`,context);
    assert.equal(await accept({...r,viewState:[1000,700,0,0],colors}),false,'stale viewport readback is rejected');
    assert.equal(await accept({...r,colors:colors.slice(1)}),false,'invalid strip is rejected');
    assert.equal(await accept({...r,colors}),true);
    assert.ok(colors[0][0]>220 && colors[31][2]>210,'strip preserves different left and right colors: '+JSON.stringify({r,left:colors[0],right:colors[31]}));
    assert.match(await evaluate("getComputedStyle(document.querySelector('[data-talaria-document-footer]')).backgroundImage"),/^linear-gradient/);
    await evaluate('globalThis.canvasGeometryReads=0;globalThis.originalCanvasRect=Element.prototype.getBoundingClientRect;Element.prototype.getBoundingClientRect=function(){canvasGeometryReads++;return originalCanvasRect.call(this)}',context);
    for(let i=0;i<20;i++)await request();
    assert.equal(await evaluate('canvasGeometryReads',context),0,'cached polling performs no geometry reads');
    await evaluate('Element.prototype.getBoundingClientRect=originalCanvasRect',context);
    const original=await state();
    for(let i=0;i<20;i++){await evaluate('__talariaDocumentFooter.refresh()',context);assert.equal((await request()).busy,true,'cached surface does not request another screenshot');}
    assert.equal((await state()).scrollHeight,original.scrollHeight);
    await configure(false);assert.equal(await request(),null,'native footer takes exclusive ownership');
    assert.equal(await accept({...r,colors}),false,'late readback cannot resurrect a disabled extension');
    await configure();await wait(250);assert.equal((await request()).busy,true,'mode switches reuse the same canvas sample');
    await evaluate("document.querySelector('canvas').width=1200");await wait(350);
    const resized=await request();assert.equal(resized.captureReady,true,'canvas buffer resize invalidates the strip');
    assert.notEqual(resized.token,r.token);
    assert.equal(await accept({...r,colors}),false,'old canvas generation cannot overwrite a resized canvas');
  });
  await fixture('fractional overflowing footer leaves no white seam','<style>html,body{height:100%;background:white}body{transform:translateY(.5px)}</style><main style="height:1800.3px"></main><footer style="height:200.3px;background:black;transform:translateZ(0)"></footer>',async()=>{
    for(const scale of [1,2]) {
      await send('Emulation.setDeviceMetricsOverride',{width:1000,height:700,deviceScaleFactor:scale,mobile:false});
      await configure();await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');await wait(50);
      const initial=await state();
      const {data}=await send('Page.captureScreenshot',{format:'png'});
      const pixels=await evaluate(`(async()=>{const blob=await (await fetch('data:image/png;base64,${data}')).blob();
        const bitmap=await createImageBitmap(blob), canvas=new OffscreenCanvas(1,4),ctx=canvas.getContext('2d');
        const top=document.querySelector('[data-talaria-document-footer]').getBoundingClientRect().top;
        ctx.drawImage(bitmap,500*${scale},Math.round(top*${scale})-2,1,4,0,0,1,4);
        bitmap.close();return [...ctx.getImageData(0,0,1,4).data];})()`);
      assert.ok(pixels.every((value,index)=>value===(index%4===3?255:0)),`no page canvas exposed at scale ${scale}: ${pixels}`);
      for(let i=0;i<10;i++){await configure(false);await configure();}
      await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');
      assert.equal((await state()).scrollHeight,initial.scrollHeight,'seam coverage must not grow the scroll range');
      assert.equal((await state()).spacer.height,86,'paint overlap must not change footer height');
    }
    await send('Emulation.setDeviceMetricsOverride',{width:1000,height:700,deviceScaleFactor:1,mobile:false});
  });
  await fixture('extension is precolored from the offscreen footer before a fast scroll','<main style="height:1800px;background:rgb(240,20,30)"></main><footer style="height:200px;background:rgb(20,40,60)"></footer>',async()=>{
    await configure();assert.equal(await evaluate('scrollY'),0);
    assert.equal(await extensionColor(),'rgb(20, 40, 60)','must use document end while viewport shows a different color');
    const firstFrame=await evaluate("scrollTo(0,document.scrollingElement.scrollHeight);let f=document.querySelector('[data-talaria-document-footer]');({color:getComputedStyle(f).backgroundColor,animations:f.getAnimations().length})");
    assert.equal(firstFrame.color,'rgb(20, 40, 60)');assert.equal(firstFrame.animations,0);
    await evaluate('scrollTo(0,0)');await wait(300);await configure();assert.equal(await extensionColor(),'rgb(20, 40, 60)');
  });
  await fixture('viewport-height body exposes the overflowing document footer','<style>html,body{height:100%;background:white}</style><div><main style="height:1800px"></main><footer style="height:200px;background:rgb(30,30,30)"></footer></div>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(30, 30, 30)');
    assert.equal(await evaluate('scrollY'),0,'offscreen color lookup never moves the viewport');
    await evaluate('scrollTo(0,document.scrollingElement.scrollHeight)');
    assert.equal(await extensionColor(),'rgb(30, 30, 30)','correct before the first bottom frame');
  });
  await fixture('body overflow promoted to the viewport does not clip footer color','<style>html,body{height:100%;background:white}body{overflow:auto}</style><div><main style="height:1800px"></main><footer style="height:200px;background:rgb(30,30,30)"></footer></div>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(30, 30, 30)');
    assert.equal((await state()).scrollHeight,2086);
    await evaluate('document.querySelector("footer").style.background="rgb(40,50,60)"');await wait(350);
    assert.equal(await extensionColor(),'rgb(40, 50, 60)','overflowing footer remains observed');
  });
  await fixture('zero-height wrappers expose their visible overflowing children','<style>body{height:2000px;background:white}</style><main style="height:1800px"></main><div style="height:0"><footer style="height:200px;background:rgb(30,30,30)"></footer></div>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(30, 30, 30)');
  });
  await fixture('display-contents wrappers preserve footer background','<main style="height:1800px"></main><div style="display:contents"><footer style="height:200px;background:rgb(30,30,30)"></footer></div>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(30, 30, 30)');
  });
  for(const clipping of ['overflow:hidden','overflow:clip','overflow:auto','contain:paint']) {
    await fixture('clipped overflow does not color the document end: '+clipping,`<style>body{height:2000px;background:rgb(220,230,240)}</style><div style="height:700px;${clipping}"><main style="height:1800px"></main><footer style="height:200px;background:rgb(30,30,30)"></footer></div>`,async()=>{
      await configure();assert.equal(await extensionColor(),'rgb(220, 230, 240)');
    });
  }
  await fixture('page extension ignores fixed banners','<main style="height:1800px"></main><footer style="height:200px;background:rgb(20,40,60)"></footer><div style="position:fixed;bottom:0;height:200px;width:100%;background:rgb(240,20,30)">Cookies</div>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(20, 40, 60)');
  });
  await fixture('offscreen footer changes refresh without idle polling','<main style="height:1800px"></main><footer style="height:200px;background:rgb(20,40,60)"></footer>',async()=>{
    await configure();await wait(500);
    await evaluate('globalThis.reads=0;const original=document.body.getBoundingClientRect.bind(document.body);document.body.getBoundingClientRect=()=>{reads++;return original()}',context);
    await wait(500);assert.equal(await evaluate('reads',context),0,'observing the footer must not create a resize loop');
    await evaluate('document.querySelector("footer").style.background="rgb(70,80,90)"');await wait(350);
    assert.equal(await extensionColor(),'rgb(70, 80, 90)');
    await evaluate(`document.querySelector('footer').outerHTML='<footer style="height:200px;background:rgb(30,50,70)"></footer>'`);await wait(350);
    assert.equal(await extensionColor(),'rgb(30, 50, 70)');
  });
  await fixture('modern CSS footer colors do not fall back to body color','<style>body{background:rgb(20,20,19)}</style><main style="height:1800px"></main><footer style="height:200px;background:color(srgb 0.1 0.1 0.098)"></footer>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(26, 26, 25)');
  });
  await fixture('perceptual CSS colors convert once and refresh when changed','<main style="height:1800px"></main><footer style="height:200px;background:oklch(0.5 0 0)"></footer>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(99, 99, 99)');
    await evaluate('globalThis.colorReads=0;const original=OffscreenCanvasRenderingContext2D.prototype.getImageData;OffscreenCanvasRenderingContext2D.prototype.getImageData=function(...args){colorReads++;return original.apply(this,args)}',context);
    for(let i=0;i<10;i++)await evaluate('__talariaDocumentFooter.refresh()',context);
    assert.equal(await evaluate('colorReads',context),0,'unchanged CSS color never rereads the conversion canvas');
    await evaluate('document.querySelector("footer").style.background="lab(50 0 0)"');await wait(350);
    assert.equal(await extensionColor(),'rgb(119, 119, 119)');
    assert.equal(await evaluate('colorReads',context),1,'a new color needs just one 1-pixel conversion');
  });
  await fixture('modern translucent footer color composites over its page','<style>body{background:rgb(20,20,20)}</style><main style="height:1800px"></main><footer style="height:200px;background:color(srgb 1 1 1 / 0.5)"></footer>',async()=>{
    await configure();const color=await extensionColor();assert.match(color,/^rgb\(13[78], 13[78], 13[78]\)$/);
  });
  await fixture('vertical gradient endpoint is ready offscreen','<style>body{height:2000px;background:linear-gradient(rgb(240,20,30),rgb(20,40,60) 90%)}</style>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(20, 40, 60)');
  });
  await fixture('transparent body color composites once over the page canvas','<style>body{height:2000px;background:rgba(0,0,0,0.5)}</style>',async()=>{
    await configure();assert.equal(await extensionColor(),'rgb(128, 128, 128)');
  });
  await fixture('default browser canvas respects color scheme','<style>html{color-scheme:dark}body{height:2000px}</style>',async()=>{
    await configure();assert.equal(await extensionColor(),await evaluate("getComputedStyle(document.querySelector('[data-talaria-document-footer]')).color"));
  });
  await fixture('dispose restores the original document','<style>body{height:2000px}</style>',async()=>{
    await configure();await evaluate('__talariaDocumentFooter.dispose()',context);assert.equal((await state()).scrollHeight,2000);assert.equal((await state()).spacer,undefined);
  });
  console.log(`BrowserDocumentFooterTests: ${count} passed`);
} finally {
  for(const p of pending.values())clearTimeout(p.timer);
  ws?.close();child.kill('SIGTERM');
  if(child.exitCode===null)await Promise.race([once(child,'exit'),new Promise(r=>setTimeout(r,2000))]);
  if(child.exitCode===null)child.kill('SIGKILL');
  server.close();siblingServer.close();await rm(profile,{recursive:true,force:true,maxRetries:5});
}

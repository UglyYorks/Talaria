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
const source=await readFile(new URL('../Source/BrowserOverlayProbe.js',import.meta.url),'utf8');
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
  async function load(body,setup='',height=700,width=1000) {
    await send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
    const path='/test-'+(++generation);
    pages.set(path,`<!doctype html><style>html,body{margin:0}body{min-height:2000px}.fixed{position:fixed;bottom:0;left:0;right:0;height:90px;background:#eee}</style><body>${body}`);
    await send('Page.navigate',{url:origin+path});
    for(let i=0;i<100;i++){await new Promise(r=>setTimeout(r,10));if(await evaluate(`location.pathname===${JSON.stringify(path)} && document.readyState==='complete'`))break;}
    if(setup)await evaluate(setup);
    const {frameTree}=await send('Page.getFrameTree');
    context=(await send('Page.createIsolatedWorld',{frameId:frameTree.frame.id,worldName:'talaria-overlay'})).executionContextId;
  }
  async function inspect(input={}) {
    const geometry={...config,...input};
    const result=await evaluate(`(${source})(${JSON.stringify(geometry)})`,context);
    if(result.obstructed!==false)return result;
    const group='overlay-test-'+sequence, attachments=[];
    // Match the native bounded fallback protocol, including OOP-frame sessions.
    async function candidate(point,currentSession=sessionId,depth=0,expectedFrame=null,targetPoint=point) {
      const s=(m,p)=>call(m,p,currentSession);
      const tree=await s('Page.getFrameTree');
      expectedFrame ||= tree.frameTree.frame.id;
      const ownerWorld=(await s('Page.createIsolatedWorld',{frameId:tree.frameTree.frame.id,worldName:'talaria-overlay'})).executionContextId;
      const offset=(await s('Runtime.evaluate',{contextId:ownerWorld,expression:'[scrollX,scrollY]',returnByValue:true})).result.value;
      let hit=await s('DOM.getNodeForLocation',{x:Math.floor(targetPoint.x+offset[0]),y:Math.floor(targetPoint.y+offset[1]),ignorePointerEventsNone:true,includeUserAgentShadowDOM:false});
      if(hit.frameId!==expectedFrame) {
        const parents=new Map(),queue=[tree.frameTree];
        for(let i=0;i<queue.length && i<128;i++)for(const child of queue[i].childFrames || []){parents.set(child.frame.id,queue[i].frame.id);if(queue.length<128)queue.push(child);}
        let child=hit.frameId,steps=0;
        while(parents.has(child) && parents.get(child)!==expectedFrame && ++steps<6)child=parents.get(child);
        if(parents.get(child)!==expectedFrame)return null;
        hit={...await s('DOM.getFrameOwner',{frameId:child}),frameId:expectedFrame};
      }
      const world=(await s('Page.createIsolatedWorld',{frameId:hit.frameId,worldName:'talaria-overlay'})).executionContextId;
      const node=await s('DOM.resolveNode',{backendNodeId:hit.backendNodeId,executionContextId:world,objectGroup:group});
      const r=await s('Runtime.callFunctionOn',{objectId:node.object.objectId,functionDeclaration:`function(config){return (${source}).call(this,config)}`,arguments:[{value:{candidate:true,allowFrame:depth>0,...point}}],returnByValue:true,awaitPromise:true,silent:true});
      if(r.exceptionDetails)return null;
      const v=r.result.value;result.cpuMS+=v.cpuMS;
      if(v.frame && depth<2) {
        const owner=await s('DOM.describeNode',{backendNodeId:hit.backendNodeId,depth:0});
        const targets=await s('Target.getTargets',{filter:[{type:'iframe'},{exclude:true}]});
        if(!targets.targetInfos.some(t=>t.targetId===owner.node.frameId))return candidate(v.frame,currentSession,depth+1,owner.node.frameId,targetPoint);
        const attached=await s('Target.attachToTarget',{targetId:owner.node.frameId,flatten:true});
        attachments.push({parent:currentSession,session:attached.sessionId});
        return candidate(v.frame,attached.sessionId,depth+1);
      }
      return v.obstructed;
    }
    try {
      for(const point of result.fallbacks) {
        let found;try{found=await candidate(point)}catch(error){console.error('Fallback failed:',error.message);found=null}
        if(found!==false) { result.obstructed=found; if(found)result.hint={x:point.x,bottom:result.viewport.height-point.y}; return result; }
      }
      return result;
    }finally{
      await send('Runtime.releaseObjectGroup',{objectGroup:group});
      for(const a of attachments.reverse()) {
        await call('Runtime.releaseObjectGroup',{objectGroup:group},a.session).catch(()=>{});
        await call('Target.detachFromTarget',{sessionId:a.session},a.parent).catch(()=>{});
      }
    }
  }
  async function check(name,body,expected,{setup='',input={},height=700,width=1000,verify}={}) {
    await load(body,setup,height,width);
    const result=await inspect(input);
    assert.equal(result.obstructed,expected,`${name}: ${JSON.stringify(result)}`);
    if(verify)await verify(result);
    console.log('PASS '+name);count++;
  }
  await check('ordinary content','<main>Article</main><footer>ordinary footer</footer>',false);
  await check('ordinary footer at page bottom','<main>Article</main><footer style="position:absolute;top:1940px">Footer</footer>',false,{setup:'scrollTo(0,2000)'});
  await check('scrolled closed shadow banner','<div id=host></div>',true,{setup:`document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<div class=fixed style="position:fixed;bottom:0;height:90px;width:100%;background:#eee">Cookies</div>';scrollTo(0,2000)`});
  await check('scrolled zoomed ordinary page','<main>Article</main>',false,{height:350,width:500,input:{currentWidth:1000,currentHeight:700},setup:'scrollTo(0,2000)'});
  await check('fixed cookie banner','<div class="fixed">Cookies</div>',true);
  const paddedBanner='<section class="fixed" style="height:350px;background:rgb(255,255,255)"><div style="position:relative;height:100%;padding:60px;box-sizing:border-box"><h2>Can we save cookies on your device?</h2><button>Reject all</button></div></section>';
  await check('quick scan sees painted banner through transparent padding',paddedBanner,true,{input:{quick:true},verify:async r=>{
    assert.equal(r.samples,1);assert.deepEqual(r.banner.rgb,[255,255,255]);
    for(const cursor of [1,20,60])assert.equal((await inspect({quick:true,cursor})).obstructed,true,'confirmation must not depend on hitting a button');
    await evaluate('document.querySelector("section").remove()');
    assert.equal((await inspect({quick:true})).obstructed,false,'dismissal clears the obstruction');
  }});
  await check('transparent padding remains detected with footer raised',paddedBanner,true,{height:614,input:{currentHeight:614,quick:true}});
  await check('banner background wins over page gap and white button','<style>html,body{background:white}</style><div class="fixed" style="bottom:12px;background:rgb(20,10,180)"><button style="width:90%;height:70px;background:white">Accept</button></div>',true,{verify:r=>{assert.deepEqual(r.banner.rgb,[20,10,180]);assert.equal(r.banner.capture,false);assert.equal(r.point.y+r.banner.edgeDelta,684);}});
  await check('gradient banner requests its own rendered edge','<div class="fixed" style="bottom:12px;background:linear-gradient(red,blue)">Cookies</div>',true,{verify:r=>{assert.equal(r.banner.capture,true);assert.equal(r.banner.rgb,undefined);}});
  await check('transparent banner composites over page','<style>html,body{background:white}</style><div class="fixed" style="background:rgba(0,0,200,0.5)">Cookies</div>',true,{verify:r=>assert.deepEqual(r.banner.rgb,[128,128,228])});
  await check('small widget does not tint the full footer','<div style="position:fixed;left:450px;bottom:20px;width:100px;height:80px;background:blue">Chat</div>',true,{verify:r=>assert.equal(r.banner,null)});
  await check('fixed banner fully covered','<div class="fixed">Cookies</div><div class="fixed" style="z-index:2;position:absolute;top:600px;background:white">Cover</div>',false);
  await check('hidden banner','<div class="fixed" style="display:none">Cookies</div>',false);
  await check('invisible banner','<div class="fixed" style="visibility:hidden">Cookies</div>',false);
  await check('transparent banner','<div class="fixed" style="opacity:0">Cookies</div>',false);
  await check('transparent ancestor','<div style="opacity:0"><div class="fixed">Cookies</div></div>',false);
  await check('empty transparent fixed box','<div class="fixed" style="background:transparent"></div>',false);
  await check('pointer-events none visual banner','<div class="fixed" style="pointer-events:none">Cookies</div>',true);
  await check('pointer-events none parent with interactive child','<div class="fixed" style="pointer-events:none"><button style="pointer-events:auto">Accept</button></div>',true);
  await check('outside horizontal footprint','<button style="position:fixed;right:0;bottom:20px;width:40px;height:40px">Help</button>',false);
  await check('small control in footprint','<button style="position:fixed;left:510px;bottom:32px;width:24px;height:24px">?</button>',true);
  await check('fixed header','<header style="position:fixed;top:0;height:70px;background:red;width:100%">Header</header>',false);
  await check('clipped fixed banner','<div style="clip-path:inset(0 0 100% 0)"><div class="fixed">Cookies</div></div>',false);
  await check('transformed normal-flow containing block','<div style="transform:translateZ(0);position:absolute;top:600px;height:100px;width:100%"><div class="fixed">Not viewport fixed</div></div>',false);
  await check('fullscreen app shell','<div style="position:fixed;inset:0;background:white">Application</div>',false);
  const flexApp=`<style>html,body{height:100%;min-height:0;overflow:hidden}
    #app{height:100%;display:flex;flex-direction:column}#chat{flex:1;min-height:0;overflow:auto}
    #bottom{height:50px;flex:none;display:flex;align-items:center;justify-content:center}
    #bottom p{margin:0}</style><main id=app><section id=chat><div style="height:1800px">Conversation</div></section>
    <div id=bottom><p>Google Terms and Privacy Policy apply. Gemini can make mistakes.</p></div></main>`;
  await check('viewport flex bottom text',flexApp,true,{input:{quick:true},verify:async r=>{
    assert.equal(r.reason,'viewport-layout');assert.equal(r.samples,1);
    await evaluate('document.querySelector("#chat").scrollTop=600');
    assert.equal((await inspect({quick:true})).obstructed,true,'sibling conversation scroll does not unpin footer');
    await evaluate('document.querySelector("#bottom").remove()');
    assert.equal((await inspect()).obstructed,false,'removed text releases footer');
  }});
  await check('display contents link labels in flex app',flexApp.replace('<p>Google Terms and Privacy Policy apply. Gemini can make mistakes.</p>','<p><a href="#"><span style="display:contents">Google Terms and Privacy Policy apply.</span></a> Gemini can make mistakes.</p>'),true,{input:{quick:true},verify:r=>assert.equal(r.reason,'viewport-layout')});
  await check('icon control in flex app',flexApp.replace('<p>Google Terms and Privacy Policy apply. Gemini can make mistakes.</p>','<button aria-label="Send"><svg width="32" height="32"><rect width="32" height="32" fill="blue"/></svg></button>'),true,{input:{quick:true}});
  await check('flex app stays detected with native footer open',flexApp,true,{height:614,input:{currentHeight:614,quick:true}});
  await check('viewport grid bottom controls',flexApp.replace('display:flex;flex-direction:column','display:grid;grid-template-rows:minmax(0,1fr) 50px').replace('<p>Google Terms and Privacy Policy apply. Gemini can make mistakes.</p>','<button>Send</button>'),true);
  await check('unlocked short flex document',flexApp.replace('overflow:hidden','overflow:visible'),false);
  await check('locked empty flex footer',flexApp.replace('<p>Google Terms and Privacy Policy apply. Gemini can make mistakes.</p>',''),false);
  await check('locked footer background alone',flexApp.replace('<p>Google Terms and Privacy Policy apply. Gemini can make mistakes.</p>','').replace('height:50px;flex:none','background:blue;height:50px;flex:none'),false);
  await check('hidden flex footer',flexApp.replace('<div id=bottom>','<div id=bottom style="visibility:hidden">'),false);
  await check('flex control outside address bar',flexApp.replace('justify-content:center','justify-content:flex-end').replace('<p>Google Terms and Privacy Policy apply. Gemini can make mistakes.</p>','<button>?</button>'),false);
  await check('flex app becomes scrolling document',flexApp,true,{verify:async()=>{
    await evaluate('document.documentElement.style.overflow="visible";document.body.style.overflow="visible";document.querySelector("#app").style.height="2000px";scrollTo(0,2000)');
    assert.equal((await inspect()).obstructed,false);
  }});
  await check('footer inside local scroller',flexApp.replace('<div id=bottom>','<div style="height:50px;overflow:auto;flex:none"><div style="height:300px"></div><div id=bottom>').replace('</main>','</div></main>'),false,{setup:'document.querySelector("#bottom").parentElement.scrollTop=1000'});
  await check('footer inside clipped overflow',flexApp.replace('<div id=bottom>','<div style="height:50px;overflow:hidden;flex:none"><div id=bottom>').replace('</main>','<div style="height:300px"></div></div></main>'),false);
  await check('small embedded flex layout',flexApp.replace('height:100%;display:flex','height:150px;position:absolute;bottom:0;width:100%;display:flex'),false);
  pages.set('/flex-app','<!doctype html>'+flexApp);
  await check('embedded frame flex layout',`<iframe src="${origin}/flex-app" style="position:absolute;inset:0;width:100%;height:100%;border:0"></iframe>`,false);
  const appleApp='<style>html,body{height:100%;min-height:0;overflow:hidden}aside{position:absolute;inset:0 auto 0 150px;width:340px;display:flex;flex-direction:column}aside main{flex:1}aside footer{padding:20px}</style><canvas style="position:absolute;width:100%;height:100%"></canvas>';
  await check('plain map stays overlaid without intersecting controls',appleApp,false);
  await check('narrow full-height search panel bottom copyright',appleApp+'<aside id=search><main>Search</main><footer>Copyright Apple. All rights reserved.</footer></aside>',true,{verify:async r=>{
    assert.equal(r.reason,'viewport-layout');
    await evaluate('document.querySelector("#search").remove()');assert.equal((await inspect()).obstructed,false);
  }});
  await check('narrow search panel remains detected after docking',appleApp+'<aside><main>Search</main><footer>Copyright Apple. All rights reserved.</footer></aside>',true,{height:614,input:{currentHeight:614}});
  const viewportCanvas='<style>html,body{height:100%;min-height:0;overflow:hidden}</style><div id=app role=application style="position:absolute;inset:0"><canvas id=map style="position:absolute;inset:0;width:100%;height:100%"></canvas></div>';
  await check('viewport canvas application',viewportCanvas,true,{input:{quick:true},verify:async result=>{
    assert.equal(result.reason,'viewport-app');assert.equal(result.samples,1);assert.ok(!result.banner);
    await evaluate(`document.querySelector('#app').insertAdjacentHTML('beforeend','<button style="position:absolute;inset:0;width:100%;height:100%">Transient map controls</button>')`);
    assert.equal((await inspect({quick:true})).reason,'viewport-app','cached surface survives transient controls');
    await evaluate(`document.body.insertAdjacentHTML('beforeend','<div id=consent style="position:fixed;bottom:0;width:100%;height:90px;background:rgb(20,10,180)">Cookies</div>')`);
    const banner=await inspect({quick:true});assert.deepEqual(banner.banner.rgb,[20,10,180],'actual banner keeps color ownership above cached app');
    await evaluate('document.querySelector("#consent").remove()');
    await evaluate('document.querySelector("#map").remove()');
    assert.equal((await inspect()).obstructed,false,'removed canvas releases app classification');
  }});
  await check('docked canvas application stays detected',viewportCanvas,true,{height:614,input:{currentHeight:614,quick:true}});
  await check('application semantics removed',viewportCanvas,true,{verify:async()=>{
    await evaluate('document.querySelector("#app").removeAttribute("role")');assert.equal((await inspect()).obstructed,false);
  }});
  await check('hidden application releases classification',viewportCanvas,true,{verify:async()=>{
    await evaluate('document.querySelector("#app").style.display="none"');assert.equal((await inspect()).obstructed,false);
  }});
  await check('Flutter canvas UI through shadow host','<style>html,body{height:100%;min-height:0;overflow:hidden}body{position:fixed;inset:0}</style><flutter-view style="position:absolute;inset:0"></flutter-view>',true,{input:{quick:true},setup:`document.querySelector('flutter-view').attachShadow({mode:'open'}).innerHTML='<div><canvas style="width:100vw;height:100vh"></canvas></div>'`,verify:async result=>assert.equal(result.reason,'viewport-app')});
  await check('closed shadow canvas application','<style>html,body{height:100%;min-height:0;overflow:hidden}</style><div role=application style="position:absolute;inset:0" id=canvas-host></div>',true,{input:{quick:true},setup:`document.querySelector('#canvas-host').attachShadow({mode:'closed'}).innerHTML='<canvas style="width:100vw;height:100vh"></canvas>'`});
  await check('application canvas with pointer events disabled',viewportCanvas.replace('id=map style="','id=map style="pointer-events:none;'),true,{input:{quick:true}});
  await check('application becomes a scrolling document',viewportCanvas,true,{verify:async()=>{
    await evaluate('for(let e of [document.documentElement,document.body]){e.style.overflow="visible";e.style.height="2000px"}');
    assert.equal((await inspect()).obstructed,false);
  }});
  await check('application shrinks into embedded panel',viewportCanvas,true,{verify:async()=>{
    await evaluate('document.querySelector("#app").style.height="150px"');assert.equal((await inspect()).obstructed,false);
  }});
  await check('fixed application with zero-height clipping root',viewportCanvas.replace('<div id=app','<style>html{height:0}body{position:fixed;inset:0;height:100vh}</style><div id=app'),true,{input:{quick:true}});
  await check('decorative fullscreen canvas',viewportCanvas.replace('role=application',''),false);
  await check('video inside application is not a canvas app',viewportCanvas.replaceAll('canvas','video'),false);
  await check('canvas application inside scrolling page',viewportCanvas.replace('height:100%;min-height:0;overflow:hidden','height:2000px;min-height:2000px;overflow:visible'),false);
  await check('small embedded canvas application',viewportCanvas.replace('id=app role=application style="position:absolute;inset:0"','id=app role=application style="position:absolute;bottom:0;width:100%;height:150px"'),false);
  await check('viewport-sized canvas clipped into a small panel',viewportCanvas.replace('<canvas id=map style="position:absolute;inset:0;width:100%;height:100%"></canvas>','<div style="position:absolute;bottom:0;height:150px;width:100%;overflow:hidden"><canvas style="position:absolute;bottom:0;width:100vw;height:100vh"></canvas></div>'),false);
  pages.set('/canvas-app','<!doctype html>'+viewportCanvas);
  await check('embedded frame canvas app does not dock containing page',`<iframe src="${origin}/canvas-app" style="position:absolute;inset:0;width:100%;height:100%;border:0"></iframe>`,false);
  await check('bottom absolute panel in fullscreen overlay','<div style="position:fixed;inset:0"><div style="position:absolute;bottom:0;height:90px;width:100%;background:#eee">Cookies</div></div>',true);
  await check('bottom sticky','<div style="height:610px"></div><div style="position:sticky;bottom:0;height:90px;background:#eee">Sticky</div>',true);
  await check('unstuck sticky away from bottom','<div style="height:100px"></div><div style="position:sticky;bottom:0;height:90px;background:#eee">Sticky</div>',false);
  for(const mode of ['open','closed'])await check(mode+' shadow banner','<div id="host"></div>',true,{setup:`document.querySelector('#host').attachShadow({mode:'${mode}'}).innerHTML='<div style="position:fixed;bottom:0;left:0;width:100%;height:90px;background:#eee">Cookies</div>'`});
  await check('closed shadow ignores pointer events','<div id="host"></div>',true,{setup:`document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<div style="position:fixed;bottom:0;left:0;width:100%;height:90px;background:#eee;pointer-events:none">Cookies</div>'`});
  await check('shadow host cannot see through foreground cover','<div id="host"></div><div style="position:absolute;top:600px;height:100px;width:100%;background:white;z-index:20">Cover</div>',false,{setup:`document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<div style="position:fixed;bottom:0;left:0;width:100%;height:90px;background:#eee">Cookies</div>'`});
  pages.set('/frame','<!doctype html><style>body{margin:0}</style><div style="position:fixed;bottom:0;left:0;right:0;height:90px;background:#eee">Frame banner</div>');
  pages.set('/empty-frame','<!doctype html><style>body{margin:0}</style><p>Ordinary embedded content</p>');
  pages.set('/scrolled-frame',`<!doctype html><style>body{margin:0;height:3000px}</style><div id=host></div><script>host.attachShadow({mode:"closed"}).innerHTML='<div style="position:fixed;bottom:0;height:90px;width:100%;background:#eee">Cookies</div>';scrollTo(0,3000)</script>`);
  await check('scrolled cross-origin frame closed shadow',`<iframe src="${cross}/scrolled-frame" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>`,true,{setup:'scrollTo(0,2000)'});
  await check('same-origin fullscreen frame',`<iframe src="${origin}/frame" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>`,true);
  await check('cross-origin fullscreen frame',`<iframe src="${cross}/frame" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>`,true);
  await check('quick cross-origin fullscreen frame',`<iframe src="${cross}/frame" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>`,true,{input:{quick:true}});
  await check('cross-origin fullscreen frame ordinary content',`<iframe src="${cross}/empty-frame" style="position:fixed;inset:0;width:100%;height:100%;border:0"></iframe>`,false);
  const guardianPanel='<div style="position:absolute;inset:0;display:flex"><div id="banner" style="position:absolute;bottom:0;width:100%;height:260px;background:#052862"><button>Continue</button></div></div>';
  pages.set('/guardian','<!doctype html><style>html,body{margin:0;height:100%}</style>'+guardianPanel);
  const guardianFrame=url=>`<div style="position:fixed;inset:0;overflow:auto"><iframe src="${url}" style="width:100%;height:100%;border:0;display:block"></iframe></div>`;
  await check('Guardian same-origin absolute panel inherits fixed frame',guardianFrame(origin+'/guardian'),true);
  await check('Guardian same-site cross-origin frame retains anchor',guardianFrame(sibling+'/guardian'),true);
  await check('Guardian cross-origin absolute panel inherits fixed frame',guardianFrame(cross+'/guardian'),true,{input:{quick:true},verify:async result=>{
    assert.ok(result.hint,'Cross-origin panel supplies a confirmation point');
    await send('Emulation.setDeviceMetricsOverride',{width:1000,height:610,deviceScaleFactor:1,mobile:false});
    assert.equal((await inspect({currentHeight:610,hint:result.hint,quick:true})).obstructed,true);
  }});
  await check('Guardian same-origin dismissal clears obstruction',guardianFrame(origin+'/guardian'),true,{verify:async()=>{
    await evaluate("document.querySelector('iframe').contentDocument.querySelector('#banner').remove()");
    assert.equal((await inspect()).obstructed,false);
  }});
  await check('fullscreen ordinary frame absolute footer is not pinned',`<iframe src="${origin}/guardian" style="position:absolute;inset:0;width:100%;height:100%;border:0"></iframe>`,false);
  await check('cross-origin ordinary frame absolute footer is not pinned',`<iframe src="${cross}/guardian" style="position:absolute;inset:0;width:100%;height:100%;border:0"></iframe>`,false);
  pages.set('/scrolling-absolute','<!doctype html><style>body{margin:0;height:2000px;position:relative}</style><div style="position:absolute;bottom:0;height:90px;width:100%;background:#eee">Document footer</div><script>scrollTo(0,2000)</script>');
  await check('fixed frame scrolling document absolute footer is not pinned',guardianFrame(cross+'/scrolling-absolute'),false);
  pages.set('/local-absolute','<!doctype html><style>body{margin:0;height:100vh}</style><div style="position:relative;top:calc(100vh - 120px);height:120px;width:100%"><div style="position:absolute;bottom:0;height:90px;width:100%;background:#eee">Local absolute content</div></div>');
  await check('fixed frame local containing block is not viewport pinned',guardianFrame(origin+'/local-absolute'),false);
  await check('transformed ordinary host cannot confer frame anchoring',`<div style="transform:translateZ(0);height:700px">${guardianFrame(cross+'/guardian')}</div>`,false);
  await check('zoomed Guardian frame remains detected',guardianFrame(cross+'/guardian'),true,{height:350,width:500,input:{currentWidth:1000,currentHeight:700}});
  pages.set('/guardian-nested',`<!doctype html><style>html,body{margin:0;height:100%}</style><iframe src="${origin}/guardian" style="display:block;width:100%;height:100%;border:0"></iframe>`);
  await check('nested full-viewport frames preserve verified anchor',guardianFrame(cross+'/guardian-nested'),true);
  pages.set('/guardian-shadow',`<!doctype html><style>html,body{margin:0;height:100%}</style><div id="host"></div><script>host.attachShadow({mode:'closed'}).innerHTML=${JSON.stringify(guardianPanel)}</script>`);
  pages.set('/guardian-shadow-nested',`<!doctype html><style>html,body{margin:0;height:100%}</style><iframe src="${origin}/guardian-shadow" style="display:block;width:100%;height:100%;border:0"></iframe>`);
  await check('nested same-origin closed shadow inherits anchor outside-in',guardianFrame(origin+'/guardian-shadow-nested'),true);
  await check('removing cross-origin frame drops its anchor',guardianFrame(cross+'/guardian'),true,{verify:async()=>{
    await evaluate("document.querySelector('iframe').remove()");
    assert.equal((await inspect()).obstructed,false);
  }});
  await check('bounded cross-origin fixed widget',`<iframe src="${cross}/empty-frame" style="position:fixed;left:200px;bottom:20px;width:100px;height:60px;border:0"></iframe>`,true);
  await check('ordinary embedded frame is not viewport fixed',`<iframe src="${origin}/frame" style="position:absolute;top:520px;width:100%;height:180px;border:0"></iframe>`,false);
  await check('docked viewport remains obstructed','<div class="fixed">Cookies</div>',true,{height:610,input:{currentHeight:610}});
  await check('zoom geometry maps correctly','<div class="fixed">Cookies</div>',true,{height:350,width:500,input:{currentWidth:1000,currentHeight:700}});
  await check('page overrides cannot corrupt isolated inspection','<div class="fixed">Cookies</div>',true,{setup:'window.getComputedStyle=()=>{throw Error("override")};Document.prototype.elementFromPoint=()=>null;'});
  await check('invalid geometry is unknown','<div class="fixed">Cookies</div>',null,{input:{width:0}});
  await check('late insertion and dismissal','<main>Article</main>',false,{verify:async()=>{
    await evaluate(`document.body.insertAdjacentHTML('beforeend','<div class="fixed">Cookies</div>')`);
    assert.equal((await inspect()).obstructed,true);
    await evaluate(`document.querySelector('.fixed').remove()`);
    assert.equal((await inspect()).obstructed,false);
  }});
  await check('closed-shadow hint survives docking','<div id="host"></div>',true,{setup:`document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<div style="position:fixed;bottom:0;left:0;width:100%;height:90px;background:#eee">Cookies</div>'`,verify:async(result)=>{
    assert.ok(result.hint);
    await send('Emulation.setDeviceMetricsOverride',{width:1000,height:610,deviceScaleFactor:1,mobile:false});
    assert.equal((await inspect({currentHeight:610,hint:result.hint})).obstructed,true);
  }});
  await check('quick check catches a late full-width banner','<div class="fixed">Cookies</div>',true,{input:{quick:true}});
  await check('quick check detects shallow bottom overlap immediately','<div class="fixed" style="height:24px">Cookies</div>',true,{input:{quick:true,cursor:30},verify:async(result)=>assert.equal(result.samples,1)});
  await check('quick check detects shallow closed-shadow overlap without sweep delay','<div id="host"></div>',true,{input:{quick:true,cursor:30},setup:`document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<div style="position:fixed;bottom:0;left:0;width:100%;height:24px;background:#eee;pointer-events:none">Cookies</div>'`});
  await check('quick check reaches closed shadow content','<div id="host"></div>',true,{input:{quick:true},setup:`document.querySelector('#host').attachShadow({mode:'closed'}).innerHTML='<div style="position:fixed;bottom:0;left:0;width:100%;height:90px;background:#eee">Cookies</div>'`});
  await check('quick check has a strict sample bound','<p>Normal content</p>',false,{input:{quick:true},verify:async(result)=>{
    assert.ok(result.samples<=3);
    assert.equal(result.fallbacks.length,1,'Empty quick scans need only one browser hit test');
  }});
  await check('scrolling during inspection discards the result','<p>Article</p>'.repeat(20000),null,{setup:'setTimeout(()=>scrollTo(0,100),80)'});
  await check('20,000-node page stays sliced','<main>Content</main>'+'<p>Offscreen content</p>'.repeat(20000),false,{verify:async(result)=>{
    assert.ok(result.samples<=256);
    assert.ok(result.maxSliceMS<25,`Long inspection slice: ${result.maxSliceMS}ms`);
    console.log(`PERFORMANCE ${result.samples} samples, ${result.cpuMS.toFixed(1)}ms work, ${result.maxSliceMS.toFixed(1)}ms longest slice; native cooldown >= ${(result.cpuMS*0.08).toFixed(2)}s`);
    // Aggregate cost varies with Chromium and hardware; native policy tests
    // enforce proportional idle time. Frame blocking and quick-scan work must
    // stay bounded even when the complete scan is expensive.
    const quick=await inspect({quick:true});
    assert.equal(quick.obstructed,false);
    assert.ok(quick.samples<=3 && quick.maxSliceMS<25);
    assert.ok(quick.cpuMS<result.cpuMS/4,`Quick scan costs too much: ${quick.cpuMS}ms vs ${result.cpuMS}ms full`);
    console.log(`PERFORMANCE quick: ${quick.cpuMS.toFixed(1)}ms work, ${quick.maxSliceMS.toFixed(1)}ms longest slice`);
  }});
  const colorSource=await readFile(new URL('../Source/BrowserFooterColor.js',import.meta.url),'utf8');
  async function colorCheck(name,body,expected,setup='',allowBudgetDeferral=false) {
    await load(body,setup);
    let result;
    for(let attempt=0;attempt<4;attempt++) {
      result=await evaluate(`(${colorSource})()`,context);
      if(!result.busy)break;
      await new Promise(r=>setTimeout(r,100));
    }
    if (allowBudgetDeferral && result.busy) {
      // On a busy desktop the large page can exhaust the work budget. Deferring
      // without a screenshot is the intended performance contract, not failure.
      assert.equal(result.rgb,undefined); assert.equal(result.fallback,undefined);
    } else assert.deepEqual(result.rgb || null,expected,`${name}: ${JSON.stringify(result)}`);
    assert.ok(result.cpuMS<25,`Color read took ${result.cpuMS}ms`);
    console.log(`PASS color: ${name} (${result.cpuMS.toFixed(2)}ms)`);count++;
  }
  await load('<style>html,body{background:rgb(20,30,150)}</style><header style="height:80px;background:rgb(180,30,20)">Page header</header>');
  const topRead=()=>evaluate(`(${colorSource})(null,true)`,context);
  assert.deepEqual((await topRead()).rgb,[180,30,20]);
  assert.deepEqual((await evaluate(`(${colorSource})()`,context)).rgb,[20,30,150]);
  await evaluate('scrollTo(0,300)');assert.deepEqual((await topRead()).rgb,[20,30,150],'top tracks visible viewport rather than document start');
  await evaluate(`document.body.insertAdjacentHTML("beforeend",'<header style="position:fixed;top:0;height:60px;width:100%;background:rgb(10,140,70)">Sticky navigation</header>')`);
  assert.deepEqual((await topRead()).rgb,[10,140,70]);
  await evaluate('globalThis.__talariaDocumentFooter={canvasSampleRequest:()=>({documentExtension:true,busy:true}),isScrolling:()=>false}',context);
  assert.deepEqual((await topRead()).rgb,[10,140,70],'bottom-extension cache does not suppress top sampling');
  await evaluate('document.querySelector("header:last-child").style.background="linear-gradient(red,blue)"');
  assert.equal((await topRead()).fallback,true,'complex top edge uses existing screenshot fallback');
  console.log('PASS visible top edge: distinct colors, scrolling, fixed header, extension cache and gradient');count++;
  await load('<style>body{background:rgb(248,247,242)}</style><header style="position:absolute;top:0;width:100%;height:100px;z-index:2"><div style="height:100%"></div></header><section style="height:400px;background:linear-gradient(rgb(70,70,70),rgb(150,150,150))"></section>');
  let layeredTop=await topRead();
  assert.equal(layeredTop.rgb,undefined,'transparent positioned header must not report the ancestor background behind a sibling hero');
  assert.equal(layeredTop.fallback,true);assert.equal(layeredTop.captureReady,true);
  assert.equal(layeredTop.captureKey,undefined,'uninspected sibling content can change without changing the header');
  await evaluate('document.querySelector("section").style.background="rgb(150,20,30)"');
  layeredTop=await topRead();assert.equal(layeredTop.fallback,true);assert.equal(layeredTop.captureKey,undefined);
  await evaluate('document.querySelector("header").style.background="rgb(30,40,50)"');
  assert.deepEqual((await topRead()).rgb,[30,40,50],'opaque header keeps the CSS fast path');count++;
  console.log('PASS visible top edge: transparent header over independent hero layer');
  await colorCheck('white page','<style>html,body{background:white}</style>',[255,255,255]);
  await colorCheck('dark page','<style>html,body{background:rgb(18,20,24)}</style>',[18,20,24]);
  await colorCheck('banner overrides page','<style>html,body{background:black}</style><div class="fixed" style="background:rgb(220,230,240)">Cookies</div>',[220,230,240]);
  await colorCheck('transparent background composites over ancestor','<style>html{background:white}body{background:rgba(0,0,0,0.5)}</style>',[128,128,128]);
  await colorCheck('gradient requests rendered pixels','<style>html,body{background:linear-gradient(red,blue)}</style>',null);
  await load('<style>html,body{background:white}</style><div class="fixed" style="bottom:12px;background:linear-gradient(red,blue)">Cookies</div>');
  const hinted=await evaluate(`(${colorSource})({id:'banner',bottom:16,capture:true})`,context);
  assert.equal(hinted.sampleBottom,684);assert.equal(hinted.fallback,true);assert.equal(hinted.rgb,undefined);
  console.log('PASS color: complex banner samples inside banner instead of page gap');count++;
  await colorCheck('gradient cache setup','<style>html,body{background:linear-gradient(red,blue)}</style>',null);
  const firstKey=(await evaluate(`(${colorSource})()`,context)).captureKey;
  assert.ok(firstKey);
  assert.equal((await evaluate(`(${colorSource})()`,context)).captureKey,firstKey,'Unchanged gradients keep a stable pixel-cache key');
  await evaluate("document.body.style.background='linear-gradient(blue,red)'",context);
  assert.notEqual((await evaluate(`(${colorSource})()`,context)).captureKey,firstKey,'A changed background invalidates cached pixels');count++;
  await colorCheck('opaque iframe requests rendered pixels',`<iframe src="${cross}/color-frame" style="position:fixed;inset:0;width:100%;height:100%"></iframe>`,null);
  await colorCheck('closed shadow requests rendered pixels','<x-footer style="position:fixed;inset:0;background:white"></x-footer>',null,`document.querySelector('x-footer').attachShadow({mode:'closed'}).innerHTML='<div style="height:100%;background:black"></div>'`);
  await colorCheck('large DOM samples or defers within its work budget','<style>html,body{background:rgb(40,50,60)}</style>'+'<p>Content</p>'.repeat(20000),[40,50,60],'',true);
  await load('<style>html,body{background:rgb(40,50,60)}</style>');
  await evaluate('globalThis.__talariaDocumentFooter={isScrolling:()=>true}',context);
  const scrolling=await evaluate(`(${colorSource})()`,context);
  assert.deepEqual(scrolling.rgb,[40,50,60]);assert.equal(scrolling.captureReady,false);count++;
  console.log(`PASS color: scrolling gets immediate CSS color without pixel readback (${scrolling.cpuMS.toFixed(2)}ms)`);
  console.log(`BrowserOverlayTests: ${count} passed`);
} finally {
  for(const p of pending.values())clearTimeout(p.timer);
  ws?.close();child.kill('SIGTERM');
  if(child.exitCode===null)await Promise.race([once(child,'exit'),new Promise(r=>setTimeout(r,2000))]);
  if(child.exitCode===null)child.kill('SIGKILL');
  server.close();siblingServer.close();await rm(profile,{recursive:true,force:true,maxRetries:5});
}

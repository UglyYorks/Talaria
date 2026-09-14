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
const bundle=await readFile(new URL('../Vendor/notes-editor/notes-editor.min.js',import.meta.url),'utf8');
const script=await readFile(new URL('../Source/NotesEditor.js',import.meta.url),'utf8');
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
    const r=await send('Runtime.evaluate',{expression,contextId,returnByValue:true,awaitPromise:true,timeout:10000});
    assert.ok(!r.exceptionDetails,JSON.stringify(r.exceptionDetails));return r.result?.value;
  }
  await send('Page.navigate',{url:origin});
  for(let i=0;i<100;i++){await new Promise(r=>setTimeout(r,10));if(await evaluate(`document.readyState==='complete'`))break;}
  await evaluate(`document.body.innerHTML='<div id="editor"></div>'; window.events=[]; window.webkit={messageHandlers:{notesEditor:{postMessage:message=>events.push(message)}}}`);
  await evaluate(bundle); await evaluate(script);
  let epoch=0;
  const load=async markdown=>evaluate(`TalariaNotes.load(${JSON.stringify(markdown)},${++epoch},true)`);
  const snap=()=>evaluate('TalariaNotes.snapshot()');
  const command=async (name,value='')=>evaluate(`TalariaNotes.command(${JSON.stringify(name)},${JSON.stringify(value)})`);
  const text=async value=>{await evaluate("document.querySelector('.tiptap').focus()");await send('Input.insertText',{text:value});};
  const selectAll=()=>evaluate(`(()=>{const element=document.querySelector('.tiptap');element.focus();const range=document.createRange();range.selectNodeContents(element);const selection=getSelection();selection.removeAllRanges();selection.addRange(range);document.dispatchEvent(new Event('selectionchange'));})()`);
  const fixture='# A heading\n\nA **bold** and *italic* [link](https://example.com).\n\n- First\n- Second\n\n> A quote\n\n```js\nconst n = 1;\n```\n\n| Name | Count |\n| --- | --- |\n| Alpha | 2 |\n\n- [x] Done\n- [ ] Next\n';
  await load(fixture);
  const rendered=await evaluate(`({heading:document.querySelector('h1')?.textContent,bold:document.querySelector('strong')?.textContent,italic:document.querySelector('em')?.textContent,link:document.querySelector('a')?.getAttribute('href'),quote:document.querySelector('blockquote')?.textContent,code:document.querySelector('pre code')?.textContent,table:document.querySelectorAll('table tr').length,tasks:document.querySelectorAll('input[type=checkbox]').length})`);
  assert.deepEqual(rendered,{heading:'A heading',bold:'bold',italic:'italic',link:'https://example.com',quote:'A quote',code:'const n = 1;',table:2,tasks:2});
  assert.equal((await snap()).markdown,fixture,'opening a note preserves exact Markdown until edited');
  await load('Hello'); await selectAll(); await command('bold');
  assert.equal((await snap()).markdown,'**Hello**','native-toolbar command changes document formatting');
  await command('undo');assert.equal((await snap()).markdown,'Hello','undo restores the original source');
  await command('redo');assert.equal((await snap()).markdown,'**Hello**');
  await load('Hello');await selectAll();await command('italic');
  assert.match((await snap()).markdown,/[*_]Hello[*_]/);
  await load('Title');await command('title');assert.match((await snap()).markdown,/^# Title/);
  await load('Item');await command('bullet');assert.match((await snap()).markdown,/^- Item/);
  await load('Item');await command('ordered');assert.match((await snap()).markdown,/^1\. Item/);
  await load('Item');await command('task');assert.match((await snap()).markdown,/^- \[ \] Item/);
  await load('Quote');await command('quote');assert.match((await snap()).markdown,/^> Quote/);
  await load('code');await command('code');assert.match((await snap()).markdown,/^```/);
  await load('Website');await selectAll();await command('link','https://example.com');
  assert.equal((await snap()).markdown,'[Website](https://example.com)');
  await load('');await text('Typed directly');assert.equal((await snap()).markdown,'Typed directly');
  await load('');await command('table');assert.equal(await evaluate("document.querySelectorAll('table tr').length"),3);
  await load(fixture);await evaluate(`(()=>{const e=document.querySelector('.tiptap');e.focus();const range=document.createRange();range.selectNodeContents(e);range.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(range);})()`);await text(' edited');
  const saved=(await snap()).markdown;await load(saved);
  assert.equal(await evaluate("document.querySelector('h1').textContent"),'A heading');
  assert.equal(await evaluate("document.querySelectorAll('table tr').length"),2);
  assert.equal(await evaluate("document.querySelectorAll('input[type=checkbox]').length"),2);
  assert.match(saved,/const n = 1;/);
  const comment='Hello\n\n<!-- keep this comment -->';
  assert.equal((await load(comment)).sourceRequired,true,'comments require source mode, avoiding silent loss');
  assert.equal((await snap()).markdown,comment);
  assert.equal((await load('---\nkey: value\n---\n\nText')).sourceRequired,true);
  assert.equal((await load('[label][ref]\n\n[ref]: https://example.com')).sourceRequired,true);
  await load('No scripts <script>window.pwned=true</script>');
  assert.equal(await evaluate('window.pwned || false'),false,'note HTML cannot execute');
  await load('Protected');await evaluate('TalariaNotes.setEditable(false)');await command('bold');
  assert.equal((await snap()).markdown,'Protected');
  await load('Fresh document');assert.equal((await snap()).epoch,epoch);
  assert.ok(await evaluate(`events.some(event=>event.type==='change' && event.markdown.includes('Typed directly'))`),'typing sends a Markdown snapshot to the native host');
  console.log('NotesEditorTests: formatted editing, input, Markdown round trips, tables, tasks, history and content safety passed');
} finally {
  ws?.close();child.kill();server.close();siblingServer.close();
  await new Promise(resolve=>child.exitCode!==null?resolve():child.once('exit',resolve));
  await rm(profile,{recursive:true,force:true});
}

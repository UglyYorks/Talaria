chrome.runtime.sendMessage({kind: 'visit'}, async reply => {
  const error = chrome.runtime.lastError?.message || reply?.error;
  if (error) { document.documentElement.dataset.extensionError = error; return; }
  const local = await chrome.storage.local.get('token');
  const marker = document.createElement('aside');
  marker.id = 'talaria-extension-proof';
  marker.textContent = `Extension active — visit ${reply.visits}`;
  marker.style.cssText = 'padding:20px;background:rgb(18,100,50);color:white;font:20px sans-serif';
  document.body.prepend(marker);
  document.documentElement.dataset.extensionProof = JSON.stringify({...reply, contentToken: local.token});
});

document.documentElement.dataset.extensionProbe = 'content-script';
chrome.runtime.sendMessage({probe: true}, reply => {
  document.documentElement.dataset.extensionProbe = JSON.stringify({
    reply,
    error: chrome.runtime.lastError?.message,
  });
});

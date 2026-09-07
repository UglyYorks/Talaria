chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (!message.probe) return false;
  chrome.tabs.query({}, tabs => {
    reply({
      sender: sender.tab?.id,
      tabs: (tabs || []).map(tab => ({id: tab.id, url: tab.url})),
      error: chrome.runtime.lastError?.message,
    });
  });
  return true;
});

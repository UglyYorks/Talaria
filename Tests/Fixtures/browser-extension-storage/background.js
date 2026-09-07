let pending = Promise.resolve();
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message.kind !== 'visit') return false;
  pending = pending.then(async () => {
    const previous = await chrome.storage.local.get({visits: 0, token: null});
    const token = previous.token || crypto.randomUUID();
    const sync = await chrome.storage.sync.get({marker: null});
    const state = {visits: previous.visits + 1, token};
    await chrome.storage.local.set(state);
    await chrome.storage.sync.set({marker: token});
    reply({...state, previousVisits: previous.visits, previousSync: sync.marker});
  }).catch(error => reply({error: String(error)}));
  return true;
});

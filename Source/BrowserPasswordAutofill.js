// Runs only in Talaria's isolated content world. Never reads a page password.
(() => {
  'use strict';
  let target = null, targetToken = null, pending = null;
  const post = message => webkit.messageHandlers.talariaPasswordAutofill.postMessage(message);
  const tokens = input => (input.autocomplete || '').toLowerCase().split(/\s+/);
  const visible = input => input instanceof HTMLInputElement && input.isConnected &&
    !input.disabled && !input.readOnly && input.getClientRects().length > 0 &&
    getComputedStyle(input).visibility === 'visible' && getComputedStyle(input).display !== 'none';
  const password = input => visible(input) && input.type === 'password' && !tokens(input).includes('new-password');
  const text = input => visible(input) && ['text', 'email', 'tel'].includes(input.type) &&
    !tokens(input).some(value => ['one-time-code', 'new-password', 'current-password'].includes(value));
  const username = input => text(input) && (tokens(input).includes('username') || input.type === 'email' ||
    /^(user(name)?|email|login|identifier|account)$/i.test(input.name || input.id));
  function secure(form) {
    if (location.protocol !== 'https:' || !isSecureContext) return false;
    const action = new URL(form?.action || location.href, location.href);
    return action.protocol === 'https:' && action.origin === location.origin;
  }
  function fields(input) {
    if (!visible(input) || !secure(input.form)) return null;
    // Never cross form or shadow-root boundaries to find a companion field.
    const candidates = Array.from(input.form ? input.form.elements : input.getRootNode().querySelectorAll('input'))
      .filter(node => node instanceof HTMLInputElement && node.form === input.form);
    const passwords = candidates.filter(password);
    if (passwords.length > 1) return null;
    const pass = password(input) ? input : passwords[0];
    if (!password(input) && !username(input)) return null;
    let user = username(input) ? input : candidates.find(username);
    if (!user && pass) {
      // Common unannotated login forms: use only the nearest preceding text field.
      user = candidates.slice(0, candidates.indexOf(pass)).reverse().find(text);
    }
    if (!pass && !user) return null;
    return {input, user, pass, form: input.form, action: input.form?.action || location.href,
      url: location.href, type: input.type};
  }
  function valid(snapshot) {
    return snapshot && location.href === snapshot.url && secure(snapshot.form) &&
      (snapshot.form?.action || location.href) === snapshot.action && visible(snapshot.input) &&
      snapshot.input.type === snapshot.type && snapshot.input.form === snapshot.form &&
      (!snapshot.user || (text(snapshot.user) && snapshot.user.form === snapshot.form)) &&
      (!snapshot.pass || (password(snapshot.pass) && snapshot.pass.form === snapshot.form));
  }
  function select(input) {
    target = fields(input) ? input : null;
    pending = null;
    if (!target) { post({token: targetToken, available: false}); targetToken = null; return; }
    targetToken = crypto.randomUUID();
    post({token: targetToken, available: !!target});
  }
  document.addEventListener('focusin', event => select(event.composedPath()[0]), true);
  document.addEventListener('contextmenu', event => {
    if (event.isTrusted) select(event.composedPath()[0]);
  }, true);
  window.addEventListener('pagehide', () => { target = pending = null; post({token: targetToken, available: false}); });
  globalThis.__talariaPasswordAutofill = {
    prepare(token) {
      if (token !== targetToken) return null;
      pending = fields(target);
      if (!valid(pending)) { pending = null; return null; }
      return {username: pending.user?.value || '', hasPassword: !!pending.pass};
    },
    fill(token, user, secret) {
      const snapshot = pending;
      pending = null; // A chosen credential can be delivered only once.
      if (token !== targetToken || !valid(snapshot)) return false;
      if ((snapshot.pass && !secret) || (snapshot.user && !snapshot.pass && !user)) return false;
      const set = (input, value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
        input.dispatchEvent(new Event('input', {bubbles: true}));
        input.dispatchEvent(new Event('change', {bubbles: true}));
      };
      if (snapshot.user && user) set(snapshot.user, user);
      // A site's username event handler may replace/navigate the form.
      if (!valid(snapshot)) return false;
      if (snapshot.pass && secret) set(snapshot.pass, secret);
      return true;
    },
    cancel(token) { if (token === targetToken) pending = null; }
  };
})();

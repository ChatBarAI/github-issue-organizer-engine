const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../app/assets/javascripts/github_issue_organizer_engine/application.js'), 'utf8');
const initialize = source.slice(source.indexOf('  const initializeMilestonesDialog ='), source.indexOf('  const initializeAll ='));

function element() {
  return {
    dataset: {}, listeners: {}, attributes: {}, hidden: false,
    addEventListener(name, callback) { this.listeners[name] = callback; },
    setAttribute(name, value) { this.attributes[name] = value; },
    removeAttribute(name) { delete this.attributes[name]; }
  };
}

function setup(fetch) {
  const button = element(), dialog = element(), content = element(), retry = element(), close = element(), save = element();
  button.dataset.milestonesUrl = '/timelines/42/milestones?return_view=show';
  dialog.querySelector = selector => ({
    '[data-milestones-content]': content, '[data-retry-milestones]': retry, '[data-close-milestones]': close, '[data-save-milestones]': save
  })[selector];
  dialog.showModal = () => { dialog.open = true; };
  dialog.close = () => { dialog.open = false; dialog.listeners.close(); };
  const context = vm.createContext({ button, fetch, document: { querySelector: () => dialog } });
  vm.runInContext(initialize + '\ninitializeMilestonesDialog(button);\ninitializeMilestonesDialog(button);', context);
  return { button, dialog, content, retry, close, save };
}
const settle = () => new Promise(resolve => setImmediate(resolve));

test('opening loads the picker on demand and closing discards unsaved selections', async () => {
  const calls = [];
  const ui = setup(async (url, options) => {
    calls.push({ url, options });
    return { ok: true, text: async () => '<form>Saved selection</form>' };
  });
  assert.equal(calls.length, 0);
  ui.button.listeners.click();
  assert.equal(ui.dialog.open, true);
  assert.equal(ui.content.attributes['aria-busy'], 'true');
  assert.equal(ui.save.disabled, true);
  await settle();
  assert.equal(ui.content.innerHTML, '<form>Saved selection</form>');
  assert.equal(ui.content.attributes['aria-busy'], undefined);
  assert.equal(ui.save.disabled, false);
  assert.equal(calls[0].options.credentials, 'same-origin');
  assert.equal(calls[0].options.cache, 'no-store');
  ui.close.listeners.click();
  assert.equal(ui.dialog.open, false);
  ui.content.innerHTML = '<form>Unsaved selection</form>';
  ui.button.listeners.click();
  await settle();
  assert.equal(calls.length, 2);
  assert.equal(ui.content.innerHTML, '<form>Saved selection</form>');
});

test('load failures stay in the dialog and retry loads available milestones', async () => {
  let attempts = 0;
  const ui = setup(async () => {
    attempts += 1;
    return { ok: attempts > 1, text: async () => '<form>Milestones</form>' };
  });
  ui.button.listeners.click();
  await settle();
  assert.equal(ui.dialog.open, true);
  assert.equal(ui.retry.hidden, false);
  assert.equal(ui.save.disabled, true);
  assert.match(ui.content.textContent, /Could not load/);
  await ui.retry.listeners.click();
  assert.equal(ui.retry.hidden, true);
  assert.equal(ui.content.innerHTML, '<form>Milestones</form>');
});

test('a response from a closed dialog cannot replace a newly opened picker', async () => {
  const pending = [];
  const ui = setup(() => new Promise(resolve => pending.push(resolve)));
  ui.button.listeners.click();
  ui.close.listeners.click();
  ui.button.listeners.click();
  pending[1]({ ok: true, text: async () => 'Latest' });
  await settle();
  pending[0]({ ok: true, text: async () => 'Stale' });
  await settle();
  assert.equal(ui.content.innerHTML, 'Latest');
});

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../app/assets/javascripts/github_issue_organizer_engine/application.js'), 'utf8');
const initialize = source.slice(source.indexOf('  const initializeMilestoneDetails ='), source.indexOf('  const initializeMilestonesDialog ='));

function element() {
  return {
    dataset: {}, listeners: {},
    addEventListener(name, handler) { (this.listeners[name] ||= []).push(handler); },
    dispatch(name, event = {}) { for (const handler of this.listeners[name] || []) handler(event); }
  };
}

test('milestone label opens its own dialog and supports close and backdrop without duplicate handlers', () => {
  const button = element(), dialog = element(), close = element();
  button.dataset.openMilestoneDetails = 'milestone-42';
  dialog.querySelector = selector => selector === '[data-close-milestone-details]' ? close : null;
  let opened = 0;
  dialog.showModal = () => { dialog.open = true; opened++; };
  dialog.close = () => { dialog.open = false; };
  vm.runInNewContext(initialize + '\ninitializeMilestoneDetails(button);\ninitializeMilestoneDetails(button);', {
    button, document: { getElementById(id) { assert.equal(id, 'milestone-42'); return dialog; } }
  });
  assert.equal(opened, 0);
  button.dispatch('click');
  assert.equal(dialog.open, true);
  assert.equal(opened, 1);
  dialog.dispatch('click', { target: close });
  assert.equal(dialog.open, true, 'clicks inside content do not dismiss details');
  close.dispatch('click');
  assert.equal(dialog.open, false);
  button.dispatch('click');
  assert.equal(opened, 2);
  dialog.dispatch('click', { target: dialog });
  assert.equal(dialog.open, false);
});

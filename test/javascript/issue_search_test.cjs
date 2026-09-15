const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../../app/assets/javascripts/github_issue_organizer_engine/application.js'), 'utf8');
const search = source.slice(source.indexOf('  const initializeIssueSearch ='), source.indexOf('  const initializeTimelineDetails ='));

test('search finds duplicate issue numbers and titles, handles no matches, and restores cards on clear', () => {
  const element = () => ({
    listeners: {}, attributes: {}, value: '', hidden: false,
    addEventListener(name, handler) { this.listeners[name] = handler; },
    setAttribute(name, value) { this.attributes[name] = value; },
    focus() { this.focused = true; }
  });
  const clearButton = element(), input = element(), status = element();
  const cards = [
    { dataset: { issueNumber: '123', issueTitle: 'Fix login' } },
    { dataset: { issueNumber: '123', issueTitle: 'Update docs' } },
    { dataset: { issueNumber: '1234', issueTitle: 'Improve login form' } }
  ];
  const elements = {
    '[data-issue-search-clear]': clearButton,
    '[data-issue-search-input]': input, '[data-issue-search-status]': status
  };
  const root = { querySelector: selector => elements[selector], querySelectorAll: () => cards };
  vm.runInNewContext(search + '\ninitializeIssueSearch(root);', { root });
  assert.equal(clearButton.hidden, true);

  const query = value => { input.value = value; input.listeners.input(); };
  for (const value of ['123', ' #123 ']) {
    query(value);
    assert.equal(clearButton.hidden, false);
    assert.deepEqual(cards.map(card => card.hidden), [false, false, true]);
    assert.equal(status.textContent, '2 of 3 scheduled issues shown.');
  }
  query(' LOGIN ');
  assert.deepEqual(cards.map(card => card.hidden), [false, true, false]);
  query('missing');
  assert.ok(cards.every(card => card.hidden));
  assert.equal(status.textContent, 'No scheduled issues match your search.');
  query('');
  assert.ok(cards.every(card => !card.hidden));
  query('docs');
  input.listeners.keydown({ key: 'Escape', preventDefault() {} });
  assert.equal(clearButton.hidden, true);
  assert.equal(input.focused, true);
  assert.equal(input.value, '');
  assert.ok(cards.every(card => !card.hidden));
  query('docs');
  clearButton.listeners.click();
  assert.equal(clearButton.hidden, true);
  assert.equal(input.value, '');
  assert.equal(status.textContent, '');
  assert.ok(cards.every(card => !card.hidden));
});

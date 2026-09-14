const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../../app/assets/javascripts/github_issue_organizer_engine/application.js'), 'utf8');
const editor = source.slice(source.indexOf('  const initializeTimelineIssueEditor ='), source.indexOf('  const initializeUnavailabilityEditor ='));

function element() {
  return {
    dataset: {}, listeners: {}, children: {},
    classList: { add() {}, remove() {}, contains() { return false; }, toggle() {} },
    style: { removeProperty() {} },
    addEventListener(name, callback) { this.listeners[name] = callback; },
    querySelector(selector) { return this.children[selector] || null; },
    querySelectorAll() { return []; },
    // Like the DOM, setting textContent removes all descendant elements.
    set textContent(value) { this.text = value; this.children = {}; },
    get textContent() { return this.text; }
  };
}

for (const response of ['unchanged', 'error']) {
 for (const target of ['gap', 'occupied']) {
  test(`repeated drag and drop sends PATCH and preserves the ${response} banner (${target})`, async () => {
    const root = element(), status = element(), task = element(), track = element();
    for (const name of ['title', 'message', 'icon']) status.children[`[data-move-status-${name}]`] = element();
    status.children['[data-dismiss-move-status]'] = element();
    root.children['[data-timeline-issue-move-status]'] = status;
    root.querySelectorAll = selector => selector === '[data-timeline-issue-drop-track]' ? [track] : selector === '[data-timeline-item-move-url]' ? [task] : [];
    task.dataset = { timelineIssue: '561', timelineItemMoveUrl: '/timelines/35/items/561' };
    track.dataset.developerId = 'alice';
    track.dataset.startDate = '2026-09-14';
    track.dataset.timelineStartDate = '2026-09-11';
    const day = { getBoundingClientRect() { return { left: 0, right: 80, width: 80 }; } };
    const other = element();
    other.dataset = { timelineIssue: '574', itemStartColumn: '1' };
    other.getBoundingClientRect = () => ({ left: 0, right: 80, width: 80 });
    track.querySelectorAll = selector => selector === '.tif-timeline-day-column' ? [day] : target === 'occupied' ? [other] : [];
    const requests = [];
    vm.runInNewContext(editor + '\ninitializeTimelineIssueEditor(root);', {
      root, parseDate: value => new Date(value + 'T00:00:00'), document: { querySelector() { return null; } },
      fetch: async (url, options) => {
        requests.push({ url, options });
        return { ok: response !== 'error', json: async () => response === 'error' ? { error: 'No vacant time.' } : { changed: false, message: 'Already at the earliest time.' } };
      }
    });
    for (let attempt = 0; attempt < 2; attempt++) {
      task.listeners.dragstart({ dataTransfer: { setData() {} } });
      assert.ok(status.querySelector('[data-move-status-title]'), 'dragstart must preserve banner children');
      track.listeners.drop({ preventDefault() {}, clientX: 0 });
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(requests.length, attempt + 1);
      assert.equal(requests[attempt].options.method, 'PATCH');
      assert.equal(JSON.parse(requests[attempt].options.body).timeline_item.developer_id, 'alice');
      assert.equal(JSON.parse(requests[attempt].options.body).timeline_item.starts_at, target === 'gap' ? '2026-09-14T09:00:00+00:00' : null);
      assert.equal(status.dataset.kind, response === 'error' ? 'error' : 'info');
      status.querySelector('[data-dismiss-move-status]').listeners.click();
      assert.equal(status.hidden, true);
    }
  });
}
}

for (const input of ['drop', 'keyboard']) {
  test(`${input} inserts before remaining work even when the issue has historical blocks`, async () => {
    const root = element(), track = element(), moving = element();
    const history = element(), remaining = element(), continuation = element();
    const tasks = [history, remaining, continuation, moving];
    root.querySelectorAll = selector => selector === '[data-timeline-issue-drop-track]' ? [track] : selector === '[data-timeline-item-move-url]' ? tasks : [];
    track.dataset = { developerId: 'alice', startDate: '2026-09-10', timelineStartDate: '2026-09-11' };
    const days = [0, 80, 160, 240].map(left => ({ getBoundingClientRect: () => ({ left, right: left + 80, width: 80 }) }));
    tasks.forEach((task, index) => {
      task.dataset = { timelineIssue: index === 3 ? '2' : '1', timelineItemMoveUrl: `/items/${index === 3 ? '2' : '1'}`, itemStartColumn: String(index * 8 + 1) };
      task.getBoundingClientRect = days[index].getBoundingClientRect;
      task.closest = () => track;
    });
    history.classList.contains = name => name === 'is-historical';
    track.querySelectorAll = selector => selector === '.tif-timeline-day-column' ? days : tasks;
    const requests = [];
    vm.runInNewContext(editor + '\ninitializeTimelineIssueEditor(root);', {
      root, parseDate: value => new Date(value + 'T00:00:00'), document: { querySelector() { return null; } },
      fetch: async (url, options) => {
        requests.push(JSON.parse(options.body).timeline_item);
        return { ok: true, json: async () => ({ changed: false }) };
      }
    });
    if (input === 'drop') {
      moving.listeners.dragstart({ dataTransfer: { setData() {} } });
      track.listeners.drop({ preventDefault() {}, clientX: 80 });
    } else {
      moving.listeners.keydown({ target: { closest() { return null; } }, altKey: true, shiftKey: true, key: 'ArrowLeft', preventDefault() {} });
    }
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(requests.length, 1);
    assert.equal(requests[0].before_item_id, '1');
    assert.equal(requests[0].starts_at, null);

    // Once the urgent issue is first, moving it right must use future queue order.
    moving.dataset.itemStartColumn = '9';
    remaining.dataset.itemStartColumn = '13';
    moving.listeners.keydown({ target: { closest() { return null; } }, altKey: true, shiftKey: true, key: 'ArrowRight', preventDefault() {} });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(requests.length, 2);
    assert.equal(requests[1].before_item_id, null);
  });
}

test('date header opens the gap action with the selected cutoff and supports cancel', () => {
  const root = element(), button = element(), dialog = element(), cancel = element();
  const input = element(), label = element();
  button.dataset.fillGapsDate = '2026-09-14';
  dialog.children['[data-fill-gaps-input]'] = input;
  dialog.children['[data-fill-gaps-label]'] = label;
  dialog.showModal = () => { dialog.open = true; };
  dialog.close = () => { dialog.open = false; };
  root.children['#tif-fill-gaps-dialog'] = dialog;
  root.querySelectorAll = selector => selector === '[data-fill-gaps-date]' ? [button] : selector === '[data-close-fill-gaps]' ? [cancel] : [];
  vm.runInNewContext(editor + '\ninitializeTimelineIssueEditor(root);', { root });
  button.listeners.click();
  assert.equal(dialog.open, true);
  assert.equal(input.value, '2026-09-14');
  assert.equal(label.textContent, '2026-09-14');
  cancel.listeners.click();
  assert.equal(dialog.open, false);
});

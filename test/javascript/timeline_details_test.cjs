const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../../app/assets/javascripts/github_issue_organizer_engine/application.js'), 'utf8');
const details = source.slice(source.indexOf('  const initializeTimelineDetails ='), source.indexOf('  const initializeTimelineIssueEditor ='));

function setup(segments = [['a', 900, 100], ['b', 1200, 100]], reducedMotion = false, includeCards = true) {
  const element = () => {
    const classes = new Set();
    return {
      dataset: {}, listeners: {},
      classList: {
        add: name => classes.add(name), remove: name => classes.delete(name),
        toggle: (name, active) => active ? classes.add(name) : classes.delete(name),
        contains: name => classes.has(name)
      },
      addEventListener(name, handler) { this.listeners[name] = handler; },
      querySelector() { return null; },
      matches() { return false; }, contains() { return false; }
    };
  };
  const root = element(), chart = element();
  const calls = [], timers = new Map();
  let now = 0, nextId = 0;
  const scroll = {
    listeners: {},
    addEventListener(name, handler) { this.listeners[name] = handler; },
    scrollLeft: 0, scrollTop: 0, clientLeft: 1, clientTop: 1, clientWidth: 600,
    clientHeight: 300, scrollHeight: 900,
    getBoundingClientRect: () => ({ left: 50, top: 100 }),
    scrollTo(options) { calls.push(options); this.scrollLeft = options.left; this.scrollTop = options.top; },
    focus(options) { this.focusOptions = options; },
    scrollIntoView(options) { this.pageScrollOptions = options; }
  };
  chart.querySelector = selector => ({ getBoundingClientRect: () => selector === '.tif-timeline-developer' ? { width: 118 } : { height: 40 } });
  const tasks = segments.map(([key, left, width, top = 180, height = 72]) => ({
    ...element(), dataset: { timelineIssue: key },
    scrollIntoView(options) { this.pageScrollOptions = options; },
    getBoundingClientRect: () => ({ left: left - scroll.scrollLeft, right: left + width - scroll.scrollLeft, width,
      top: top - scroll.scrollTop, bottom: top + height - scroll.scrollTop, height })
  }));
  const cards = [...new Set(segments.map(([key]) => key))].map(key => {
    const button = element();
    return { ...element(), dataset: { timelineIssueCard: key }, button, querySelector: () => button };
  });
  root.querySelector = selector => selector === '.tif-timeline-chart' ? chart : scroll;
  const dialog = { open: true, close() { this.open = false; } };
  const milestoneButtons = cards.map(card => ({
    ...element(), dataset: { revealTimelineIssue: card.dataset.timelineIssueCard },
    closest: () => dialog
  }));
  root.querySelectorAll = selector => ({
    '[data-timeline-issue]': tasks,
    '[data-timeline-issue-card]': includeCards ? cards : [],
    '[data-reveal-timeline-issue]': milestoneButtons
  })[selector] || [];
  vm.runInNewContext(details + '\ninitializeTimelineDetails(root);', {
    root, initializeIssueSearch() {}, initializeStickyTimeline() {},
    window: { matchMedia: () => ({ matches: reducedMotion }) },
    setTimeout(callback, delay) { const id = ++nextId; timers.set(id, { callback, at: now + delay }); return id; },
    clearTimeout(id) { timers.delete(id); }
  });
  return {
    root, chart, tasks, cards, scroll, calls, dialog, milestoneButtons,
    advance(ms) {
      now += ms;
      for (const [id, timer] of timers) {
        if (timer.at <= now) { timers.delete(id); timer.callback(); }
      }
    }
  };
}

test('highlights immediately and reveals an offscreen issue after a short dwell', () => {
  const { cards, tasks, calls, advance } = setup();
  cards[0].listeners.mouseenter();
  assert.equal(tasks[0].classList.contains('is-highlighted'), true);
  advance(199);
  assert.equal(calls.length, 0);
  advance(1);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].left, 361);
  assert.equal(calls[0].behavior, 'smooth');
});

test('quick movement across cards reveals only the latest issue', () => {
  const { cards, tasks, calls, advance } = setup();
  cards[0].listeners.mouseenter();
  advance(150);
  cards[0].listeners.mouseleave();
  cards[1].listeners.mouseenter();
  advance(50);
  assert.equal(calls.length, 0);
  assert.equal(tasks[0].classList.contains('is-highlighted'), false);
  assert.equal(tasks[1].classList.contains('is-highlighted'), true);
  advance(150);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].left, 661);
});

test('leaving before the dwell cancels scrolling and highlighting', () => {
  const { cards, chart, calls, advance } = setup();
  cards[0].listeners.mouseenter();
  advance(100);
  cards[0].listeners.mouseleave();
  advance(200);
  assert.equal(calls.length, 0);
  assert.equal(chart.classList.contains('is-highlighting-issue'), false);
});

test('keyboard focus reveals issues and moving focus within a card keeps the pending reveal', () => {
  const { cards, calls, scroll, advance } = setup();
  const link = {};
  cards[0].contains = target => target === link;
  cards[0].listeners.focusin();
  cards[0].listeners.focusout({ relatedTarget: link });
  advance(200);
  assert.equal(calls.length, 1);
  scroll.listeners.scrollend();
  cards[1].listeners.focusin();
  cards[1].listeners.focusout({ relatedTarget: null });
  advance(200);
  assert.equal(calls.length, 1);
});

test('scrolls left to uncover a segment hidden by the sticky developer column', () => {
  const { cards, scroll, calls, advance } = setup([['a', 400, 100]]);
  scroll.scrollLeft = 300;
  cards[0].listeners.mouseenter();
  advance(200);
  assert.equal(calls[0].left, 219);
});

for (const segments of [
  [['a', 250, 100]],
  [['a', 100, 1000]],
  [['a', 900, 100], ['a', 250, 100]]
]) {
  test(`does not scroll when an issue segment is already visible: ${JSON.stringify(segments)}`, () => {
    const { cards, calls, advance } = setup(segments);
    cards[0].listeners.mouseenter();
    advance(200);
    assert.equal(calls.length, 0);
  });
}

test('reveals the nearest segment when an issue has several offscreen segments', () => {
  const { cards, calls, advance } = setup([['a', 1500, 100], ['a', 800, 100]]);
  cards[0].listeners.mouseenter();
  advance(200);
  assert.equal(calls[0].left, 261);
});

test('aligns an oversized offscreen segment with the visible date area', () => {
  const { cards, calls, advance } = setup([['a', 900, 1000]]);
  cards[0].listeners.mouseenter();
  advance(200);
  assert.equal(calls[0].left, 719);
});

test('reveals a developer row below the capped Timeline without moving the page', () => {
  const { cards, calls, scroll, advance } = setup([['a', 250, 100, 700]]);
  cards[0].listeners.mouseenter();
  advance(200);
  assert.equal(calls[0].left, 0);
  assert.equal(calls[0].top, 379);
  assert.equal(calls[0].behavior, 'instant');
  assert.equal(scroll.pageScrollOptions, undefined);
});

test('reveals a row above the viewport without hiding it beneath the sticky dates', () => {
  const { cards, calls, scroll, advance } = setup([['a', 250, 100, 180]]);
  scroll.scrollTop = 150;
  cards[0].listeners.focusin();
  advance(200);
  assert.equal(calls[0].top, 31);
});

test('rapid hovering cancels pending vertical scrolling too', () => {
  const { cards, calls, advance } = setup([['a', 250, 100, 700], ['b', 250, 100, 500]]);
  cards[0].listeners.mouseenter();
  advance(150);
  cards[0].listeners.mouseleave();
  cards[1].listeners.mouseenter();
  advance(200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].top, 179);
});

test('chooses a visible segment over a horizontally nearer segment on an offscreen row', () => {
  const { cards, calls, advance } = setup([['a', 250, 100, 700], ['a', 300, 100, 180]]);
  cards[0].listeners.mouseenter();
  advance(200);
  assert.equal(calls.length, 0);
});

test('Show in Timeline immediately reveals the issue, moves focus and brings the chart into view', () => {
  const { cards, tasks, calls, scroll, advance } = setup();
  cards[0].button.listeners.click();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].behavior, 'instant');
  assert.equal(tasks[0].classList.contains('is-highlighted'), true);
  assert.equal(scroll.focusOptions.preventScroll, true);
  assert.equal(tasks[0].pageScrollOptions.block, 'center');
  assert.equal(tasks[0].pageScrollOptions.inline, 'nearest');
  advance(200);
  assert.equal(calls.length, 1, 'explicit navigation cancels the delayed reveal');
});

test('moving to another card stops an ongoing glide and waits before starting the new one', () => {
  const { cards, calls, scroll, advance } = setup();
  cards[0].listeners.mouseenter();
  advance(200);
  assert.equal(calls[0].behavior, 'smooth');
  // Simulate the browser partway through its smooth animation.
  scroll.scrollLeft = 100;
  cards[0].listeners.mouseleave();
  assert.equal(calls[1].behavior, 'instant');
  assert.equal(calls[1].left, 100);
  cards[1].listeners.mouseenter();
  advance(199);
  assert.equal(calls.length, 2);
  advance(1);
  assert.equal(calls.length, 3);
  assert.equal(calls[2].behavior, 'smooth');
  assert.equal(calls[2].left, 661);
});

test('respects reduced motion by revealing issues instantly', () => {
  const { cards, calls, advance } = setup(undefined, true);
  cards[0].listeners.mouseenter();
  advance(200);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].behavior, 'instant');
});

for (const includeCards of [true, false]) {
  test(`milestone action closes its dialog and reveals the matching issue (${includeCards ? 'viewer' : 'editor'})`, () => {
    const { root, tasks, cards, calls, scroll, dialog, milestoneButtons, advance } = setup(undefined, false, includeCards);
    milestoneButtons[1].listeners.click();
    assert.equal(dialog.open, false);
    assert.equal(root.dataset.highlightedTimelineIssue, 'b');
    assert.equal(tasks[0].classList.contains('is-highlighted'), false);
    assert.equal(tasks[1].classList.contains('is-highlighted'), true);
    if (includeCards) assert.equal(cards[1].classList.contains('is-highlighted'), true);
    assert.equal(scroll.focusOptions.preventScroll, true);
    assert.equal(tasks[1].pageScrollOptions.block, 'center');
    assert.equal(calls[0].left, 661);
    advance(200);
    assert.equal(calls.length, 1, 'navigation leaves no pending hover reveal');
  });
}

test('milestone navigation cancels an older pending card hover', () => {
  const { root, cards, calls, milestoneButtons, advance } = setup();
  cards[0].listeners.mouseenter();
  advance(100);
  milestoneButtons[1].listeners.click();
  advance(200);
  assert.equal(root.dataset.highlightedTimelineIssue, 'b');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].left, 661);
});

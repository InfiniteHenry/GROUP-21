// Small dependency-free smoke checks: run with `node checks.js`.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const elements = new Map();
const document = {
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, { innerHTML: '', textContent: '', addEventListener() {}, classList: { add() {}, remove() {} } });
    return elements.get(id);
  },
  querySelectorAll() { return []; },
  querySelector() { return { hidden: false }; },
  addEventListener() {},
};
const storage = new Map();
const localStorage = { getItem: key => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) };
const window = {};
const context = vm.createContext({ document, window, localStorage, console, Date, Math, Intl, structuredClone, setTimeout, clearTimeout });
vm.runInContext(fs.readFileSync('app.js', 'utf8'), context, { filename: 'app.js' });

assert.equal(vm.runInContext('state.decks.length', context), 0, 'app starts with no pre-made decks');
assert.match(elements.get('appContent').innerHTML, /Make what you learn/, 'welcome landing page opens first');
vm.runInContext(`user = { id: 'test-user' }; cloud = { from: () => ({ upsert: row => { localStorage.setItem(row.user_id, JSON.stringify(row.data)); return Promise.resolve({ error: null }); } }) }; render()`, context);
assert.match(elements.get('appContent').innerHTML, /Good to see you, there/, 'empty dashboard renders after sign-in');
vm.runInContext(`state.decks.push({ id: 'test', name: 'Test deck', emoji: '📘', cards: [
  { id: 'b1', q: 'Question one?', a: 'Answer one', interval: 0, due: 0, seen: 0, right: 0 },
  { id: 'b2', q: 'Question two?', a: 'Answer two', interval: 0, due: 0, seen: 0, right: 0 },
  { id: 'b3', q: 'Question three?', a: 'Answer three', interval: 0, due: 0, seen: 0, right: 0 },
  { id: 'b4', q: 'Question four?', a: 'Answer four', interval: 0, due: 0, seen: 0, right: 0 },
  { id: 'b5', q: 'Question five?', a: 'Answer five', interval: 0, due: 0, seen: 0, right: 0 },
]})`, context);

vm.runInContext(`{
  const testDeck = state.decks.find(deck => deck.id === 'test');
  const testCard = testDeck.cards.find(card => card.id === 'b1');
  study = { deckId: 'test', cards: [{ id: testCard.id, deckId: 'test' }], index: 0,
    revealed: true, reviewed: 0, correct: 0, started: Date.now() };
  rate(true);
}`, context);
assert.equal(vm.runInContext("state.decks.find(d => d.id === 'test').cards.find(c => c.id === 'b1').interval", context), 1, 'correct answer schedules first review in one day');
assert.equal(vm.runInContext("state.decks.find(d => d.id === 'test').cards.find(c => c.id === 'b1').right", context), 1, 'correct answer increments correct count');
assert.equal(vm.runInContext('state.sessions.length', context), 1, 'completed session is recorded');
assert.ok(storage.has('test-user'), 'state is saved to the signed-in account');
vm.runInContext("startStudy('test', true)", context);
assert.equal(vm.runInContext('study.cards.length', context), 5, 'a deck can be reviewed again even when its cards are scheduled for later');

vm.runInContext(`{
  const testDeck = state.decks.find(deck => deck.id === 'test');
  const testCard = testDeck.cards.find(card => card.id === 'b2');
  study = { deckId: 'test', cards: [{ id: testCard.id, deckId: 'test' }], index: 0,
    revealed: true, reviewed: 0, correct: 0, started: Date.now() };
  rate(false);
}`, context);
const missed = vm.runInContext("state.decks.find(d => d.id === 'test').cards.find(c => c.id === 'b2')", context);
assert.equal(missed.interval, 0, 'missed card returns to learning interval');
assert.ok(missed.due > Date.now() && missed.due <= Date.now() + 10 * 60 * 1000 + 100, 'missed card is scheduled in about ten minutes');
assert.equal(vm.runInContext('study.index', context), 0, 'missed card stays on the same card');
assert.equal(vm.runInContext('study.revealed', context), false, 'missed card flips back to the question for another try');
vm.runInContext("state.decks.push({ id: 'empty', name: 'Empty', cards: [] }); startStudy('empty', true)", context);
assert.equal(elements.get('toast').textContent, 'No cards in deck', 'empty deck shows a clear message instead of starting a session');

console.log('Recall smoke checks passed: dashboard, sample decks, review scheduling, session recording, and persistence.');

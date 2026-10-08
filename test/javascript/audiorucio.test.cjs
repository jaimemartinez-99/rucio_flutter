const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const audio = require('../../assets/epubjs/audiorucio.js');
const epub = fs.readFileSync(path.join(__dirname, '../../assets/epubjs/epub.min.js'), 'utf8');

function fixture(chapters) {
  const window = new JSDOM('', { runScripts: 'outside-only' }).window;
  window.eval(epub);
  const CFI = window.ePub.CFI;
  const sections = chapters.map((chapter, index) => {
    const document = new JSDOM(`<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Do not read</title></head><body>${chapter.text || chapter}</body></html>`, { contentType: 'application/xhtml+xml' }).window.document;
    const base = `/6/${(index + 1) * 2}`;
    return {
      index, document, href: `${index}.xhtml`, linear: chapter.linear !== false,
      load: async () => document.documentElement,
      cfiFromRange: range => new CFI(range, base).toString()
    };
  });
  const book = {
    load() {},
    spine: { get: target => sections[typeof target === 'string' ? new CFI(target).spinePos : target] },
    getRange: async cfi => new CFI(cfi).toRange(sections[new CFI(cfi).spinePos].document)
  };
  return { reader: audio.create({ book, toRange: (cfi, doc) => new CFI(cfi).toRange(doc) }), sections, book };
}

test('Narration starts at a real EPUB CFI, preserves inline spaces and provides highlight ranges', async () => {
  const { reader, sections, book } = fixture(['<p>Previous paragraph.</p><p>Hello <em>beautiful</em> <strong>world</strong>.</p>']);
  const doc = sections[0].document;
  const start = doc.createRange();
  start.setStart(doc.querySelectorAll('p')[1].firstChild, 6);
  start.collapse(true);
  const page = await reader.read(sections[0].cfiFromRange(start));
  assert.equal(page.paragraphs.map(p => p.text).join('\n\n'), 'beautiful world.');
  assert.equal(page.nextCfi, null);
  for (const paragraph of page.paragraphs) {
    assert.equal((await book.getRange(paragraph.cfiRange)).toString().trim(), paragraph.text);
    for (const run of paragraph.runs) assert.equal((await book.getRange(run.cfiRange)).toString(), run.text);
  }
});

test('Long multilingual chapters split within the API byte limit without losing or repeating text', async () => {
  const original = 'Árbol, pingüino, 日本語 y 🌙. '.repeat(900);
  const { reader } = fixture([`<p>${original}</p>`]);
  let cfi = null;
  const text = [];
  let count = 0;
  do {
    const page = await reader.read(cfi);
    assert.ok(page);
    const spoken = page.paragraphs.map(p => p.text).join('\n\n');
    assert.ok(Buffer.byteLength(spoken, 'utf8') <= 3500);
    assert.ok(!spoken.includes('\uFFFD'));
    text.push(spoken);
    cfi = page.nextCfi;
    count++;
    assert.ok(count < 100);
  } while (cfi);
  assert.ok(count > 2);
  assert.equal(text.join(' ').replace(/\s+/g, ' ').trim(), original.trim());
});

test('Chapter transitions skip non-linear chapters, empty content, notes and executable text', async () => {
  const { reader } = fixture([
    '<nav>Contents</nav><p>Chapter one.<a epub:type="noteref">[1]</a></p><aside epub:type="footnote">Footnote</aside><p hidden="hidden">Hidden</p><script>Bad</script>',
    { text: '<p>Non-linear note chapter.</p>', linear: false },
    '<p> </p>',
    '<p>Chapter two.</p>'
  ]);
  const first = await reader.read(null);
  assert.equal(first.paragraphs.map(p => p.text).join('\n\n'), 'Chapter one.');
  const second = await reader.read(first.nextCfi);
  assert.equal(second.paragraphs[0].text, 'Chapter two.');
  assert.equal(second.href, '3.xhtml');
  assert.equal(second.nextCfi, null);
});

test('A position at the end of a chapter advances and an invalid CFI fails', async () => {
  const { reader, sections } = fixture(['<p>First.</p>', '<p>Second.</p>']);
  const doc = sections[0].document;
  const node = doc.querySelector('p').firstChild;
  const range = doc.createRange();
  range.setStart(node, node.length);
  range.collapse(true);
  const page = await reader.read(sections[0].cfiFromRange(range));
  assert.equal(page.paragraphs[0].text, 'Second.');
  await assert.rejects(reader.read('epubcfi(/6/100!/4/2/1:0)'));
});

test('Visual pages respect both CFI boundaries, inline markup and cross-chapter spreads', async () => {
  const { sections, book } = fixture(['<p>Before. Hello <em>beautiful</em> world. After.</p>', '<p>Next chapter begins here.</p>']);
  function position(index, selector, offset) {
    const doc = sections[index].document;
    const range = doc.createRange();
    range.setStart(doc.querySelector(selector).firstChild, offset);
    range.collapse(true);
    return { cfi: sections[index].cfiFromRange(range), index, href: sections[index].href };
  }
  const locations = [
    { start: position(0, 'p', 8), end: position(0, 'em', 9), atEnd: false },
    { start: position(0, 'em', 9), end: position(1, 'p', 12), atEnd: false },
    { start: position(1, 'p', 12), end: position(1, 'p', 25), atEnd: true }
  ];
  let current = 0;
  const window = new JSDOM('', { runScripts: 'outside-only' }).window;
  window.eval(epub);
  const reader = audio.createVisual({
    book, toRange: (cfi, doc) => new window.ePub.CFI(cfi).toRange(doc),
    display: async cfi => { current = locations.findIndex(loc => loc.start.cfi === cfi); },
    next: async () => { current++; }, getLocation: async () => locations[current]
  });
  const first = await reader.read(locations[0].start.cfi);
  assert.equal(first.paragraphs.map(p => p.text).join('\n\n'), 'Hello beautiful');
  assert.equal(first.startCfi, locations[0].start.cfi);
  assert.equal(first.endCfi, locations[0].end.cfi);
  const second = await reader.read(first.nextCfi);
  assert.equal(second.paragraphs.map(p => p.text).join('\n\n'), 'world. After.\n\nNext chapter');
  const last = await reader.read(second.nextCfi);
  assert.equal(last.paragraphs[0].text, 'begins here.');
  assert.equal(last.nextCfi, null);
  for (const page of [first, second, last]) {
    for (const p of page.paragraphs) assert.equal((await book.getRange(p.cfiRange)).toString().trim(), p.text);
  }
});

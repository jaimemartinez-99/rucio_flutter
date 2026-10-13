const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const context = require('../../assets/epubjs/claude_context.js');
const epub = fs.readFileSync(path.join(__dirname, '../../assets/epubjs/epub.min.js'), 'utf8');

function fixture(t, chapters, maxCharacters) {
  const window = new JSDOM('', { runScripts: 'outside-only' }).window;
  window.eval(epub);
  const CFI = window.ePub.CFI;
  const loaded = [];
  const windows = [];
  const sections = chapters.map((chapter, index) => {
    const chapterWindow = new JSDOM(`<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Future spoiler</title></head><body>${chapter.text || chapter}</body></html>`, { contentType: 'application/xhtml+xml' }).window;
    windows.push(chapterWindow);
    const document = chapterWindow.document;
    return {
      index, document, href: `${index}.xhtml`, linear: chapter.linear !== false,
      load: async () => { loaded.push(index); if (chapter.fail) throw new Error('Load failed'); return document.documentElement; },
      cfiFromRange: range => new CFI(range, `/6/${(index + 1) * 2}`).toString()
    };
  });
  const book = { load() {}, spine: { get: index => sections[index] } };
  t.after(() => { window.close(); windows.forEach(window => window.close()); });
  return { reader: context.create({ book, CFI, maxCharacters }), sections, loaded, CFI };
}

function point(section, selector, offset) {
  const range = section.document.createRange();
  range.setStart(section.document.querySelector(selector).firstChild, offset);
  range.collapse(true);
  return section.cfiFromRange(range);
}

test('Only previous sections and the exact current prefix reach the context', async t => {
  const { reader, sections, loaded } = fixture(t, [
    '<p>Earlier events.</p>',
    '<p>Read this. Secret identity revealed afterwards.</p>',
    '<p>Future chapter twist.</p>'
  ]);
  const result = await reader.read(point(sections[1], 'p', 10));
  assert.deepEqual(result.sections.map(s => s.text), ['Earlier events.', 'Read this.']);
  assert.ok(!loaded.includes(2));
  assert.ok(!JSON.stringify(result).includes('Secret identity'));
});

test('Range selections end at the selected text with inline markup and Unicode intact', async t => {
  const { reader, sections } = fixture(t, ['<p>Árbol 🌙 <em>selected</em> spoiler.</p>']);
  const doc = sections[0].document;
  const range = doc.createRange();
  range.setStart(doc.querySelector('p').firstChild, 0);
  range.setEnd(doc.querySelector('em').firstChild, 8);
  const result = await reader.read(sections[0].cfiFromRange(range));
  assert.equal(result.sections[0].text, 'Árbol 🌙 selected');
  assert.ok(!result.cutoffCfi.includes(','));
});

test('Element boundaries and the start of the book never include later text', async t => {
  const { reader, sections } = fixture(t, ['<p>Already read.</p><p>Not read.</p>']);
  assert.equal((await reader.read('epubcfi(/6/2!/4/4)')).sections[0].text, 'Already read.');
  assert.deepEqual((await reader.read(point(sections[0], 'p', 0))).sections, []);
});

test('Unread notes, navigation, hidden content and non-linear sections are excluded', async t => {
  const { reader, sections, loaded } = fixture(t, [
    '<nav>Future chapter names</nav><p>Earlier text.<a epub:type="noteref">1</a></p><aside epub:type="footnote">Later identity</aside><p style="display:none">Hidden spoiler</p><script>Bad</script>',
    { text: '<p>Endnotes with future revelations</p>', linear: false },
    '<p>Current text.</p>'
  ]);
  const result = await reader.read(point(sections[2], 'p', 13));
  assert.deepEqual(result.sections.map(s => s.text), ['Earlier text.', 'Current text.']);
  assert.ok(!loaded.includes(1));
});

test('Going backwards produces a smaller context instead of reusing later text', async t => {
  const { reader, sections } = fixture(t, ['<p>First.</p>', '<p>Second.</p>']);
  await reader.read(point(sections[1], 'p', 7));
  const earlier = await reader.read(point(sections[0], 'p', 6));
  assert.deepEqual(earlier.sections.map(s => s.text), ['First.']);
});

test('A page start in chapter XVII reports chapter 17 rather than the beginning of the book', async t => {
  const { reader, sections } = fixture(t, ['<p>Earlier narrative.</p>', '<h2>CAPÍTULO XVII</h2><p>Current chapter.</p><h2>CAPÍTULO XVIII</h2><p>Future.</p>']);
  const result = await reader.read(point(sections[1], 'h2', 0));
  assert.equal(result.chapterNumber, 17);
  assert.equal(result.spineIndex, 1);
  assert.deepEqual(result.sections.map(s => s.text), ['Earlier narrative.']);
});

test('Chapter metadata ignores navigation, hidden headings and later subchapters', async t => {
  const { reader, sections } = fixture(t, ['<h2>Chapter 17</h2><nav><p>Chapter 30</p></nav><p hidden="hidden">Chapter 31</p><aside epub:type="footnote"><p>Chapter 32</p></aside><p id="current">Current.</p><h2>Chapter 18</h2>']);
  const result = await reader.read(point(sections[0], '#current', 0));
  assert.equal(result.chapterNumber, 17);
});

test('Invalid CFIs, failed chapters and oversized prefixes fail without partial context', async t => {
  const { reader, sections } = fixture(t, ['<p>Long text.</p>'], 3);
  for (const cfi of [null, 'not-a-cfi', 'epubcfi(/6/100!/4/2/1:0)', 'epubcfi(/6/2!/4/100/1:0)', 'epubcfi(/6/2!/4/2/1:999)']) {
    await assert.rejects(reader.read(cfi));
  }
  await assert.rejects(reader.read(point(sections[0], 'p', 10)), /demasiado grande/);
  const failed = fixture(t, [{ text: '<p>Missing text.</p>', fail: true }, '<p>Now.</p>']);
  await assert.rejects(failed.reader.read(point(failed.sections[1], 'p', 4)), /Load failed/);
});

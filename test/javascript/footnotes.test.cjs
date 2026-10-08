const { test } = require('node:test');
const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');
const footnotes = require('../../assets/epubjs/footnotes.js');

function document(markup) {
  return new JSDOM(markup).window.document;
}

function reference(markup, source = '/OEBPS/Text/chapter.xhtml') {
  return footnotes.resolveReference(document(markup).querySelector('a'), source);
}

test('EPUB 3 references resolve relative paths and escaped anchors', () => {
  const ref = reference('<a epub:type="noteref" href="../Notes/end.xhtml#n%201" id="ref1">[1]</a>');
  assert.deepEqual(ref, {
    path: '/OEBPS/Notes/end.xhtml',
    id: 'n 1',
    sourcePath: '/OEBPS/Text/chapter.xhtml',
    sourceId: 'ref1',
    label: '[1]'
  });
  assert.ok(reference('<a role="doc-noteref" href="appendix.xhtml#odd-id">a</a>'));
});

test('Legacy EPUB 2 note files, note ids and superscript markers work', () => {
  assert.ok(reference('<a href="../Text/notas.xhtml#nt3" id="rf3">[3]</a>'));
  assert.ok(reference('<a href="appendix.html#fn-17">17</a>'));
  assert.ok(reference('<sup><a href="appendix.html#custom">*</a></sup>'));
  assert.ok(reference('<a href="nota1.html#nota1"><sup>1</sup></a>'));
  assert.ok(reference('<a href="nota1.html" id="nota1llam">1</a>'));
  assert.equal(reference('<a href="notas.xhtml">Notas</a>'), null);
  assert.equal(reference('<a href="chapter2.xhtml">2</a>'), null);
});

test('Normal chapter, external, page-list and backlink links keep normal navigation', () => {
  for (const markup of [
    '<a href="chapter2.xhtml#heading">Chapter 2</a>',
    '<a href="https://example.com/notes#fn1">[1]</a>',
    '<a href="//example.com/notes#fn1">[1]</a>',
    '<a href="chapter.xhtml#Page_1">1</a>',
    '<nav><a href="notas.xhtml#nt1">Notes</a></nav>',
    '<p class="nota"><a href="chapter.xhtml#nt1">1</a></p>',
    '<a epub:type="backlink" href="chapter.xhtml#fn1">1</a>',
    '<a role="doc-backlink" href="chapter.xhtml#fn1">1</a>'
  ]) {
    assert.equal(reference(markup), null, markup);
  }
});

test('Semantic notes retain paragraphs and inline text but exclude adjacent notes and backlinks', () => {
  const doc = document('<aside epub:type="footnote" id="fn1"><p>1. A <em>word</em>.</p><p>Second line.<br>More.</p><a role="doc-backlink" href="chapter.xhtml#ref1">Return</a></aside><aside id="fn2">Wrong note.</aside>');
  const ref = reference('<a href="#fn1" id="ref1">[1]</a>');
  assert.equal(footnotes.extractText(doc, ref), '1. A word.\n\nSecond line.\nMore.');
});

test('Spanish legacy note containers and Stoner inline target anchors are extracted', () => {
  const ref = reference('<a href="notas.xhtml#nt3" id="rf3">[3]</a>');
  const doc = document('<div class="nota"><p id="nt3">3. Explanation <a href="chapter.xhtml#rf3">[3]</a></p><p>Continuation.</p></div><div class="nota"><p id="nt4">Other note.</p></div>');
  assert.equal(footnotes.extractText(doc, ref), '3. Explanation\n\nContinuation.');
  const stonerRef = reference('<a href="nota1.html" id="nota1llam">1</a>', '/OEBPS/cap14.html');
  const stoner = document('<p class="nota"><a id="nota1" href="cap14.html#nota1llam">1.</a> An <i>explanation</i>.</p>');
  assert.equal(footnotes.extractText(stoner, stonerRef), 'An explanation.');
  assert.throws(() => footnotes.extractText(document('<p class="nota">One.</p><p class="nota">Two.</p>'), stonerRef));
});

test('Legacy notes spanning sibling paragraphs stop at the next note', () => {
  const ref = reference('<a href="notes.xhtml#fn1">1</a>');
  const doc = document('<p id="fn1">First.</p><p>Second paragraph.</p><p id="fn2">Next note.</p><p>Next continuation.</p>');
  assert.equal(footnotes.extractText(doc, ref), 'First.\n\nSecond paragraph.');
});

test('Named anchors work and executable content is excluded', () => {
  const ref = reference('<a href="notes.xhtml#fn1">1</a>');
  const doc = document('<p><a name="fn1"></a>Explanation.<script>wrong()</script><style>wrong</style><img alt="Diagram description"></p><p id="fn2">Next.</p>');
  assert.equal(footnotes.extractText(doc, ref), 'Explanation.Diagram description');
  assert.throws(() => footnotes.extractText(document('<body id="fn1">Entire book</body>'), ref));
  assert.throws(() => footnotes.extractText(document('<p>No target</p>'), ref));
});

test('Capturing a note click prevents EPUB navigation and caches the note document', async () => {
  const doc = document('<a href="notas.xhtml#nt1" id="rf1">[1]</a><a href="chapter2.xhtml">Chapter</a>');
  const messages = [];
  let loads = 0;
  let navigations = 0;
  const notes = footnotes.create({
    load: async path => {
      assert.equal(path, '/OEBPS/Text/notas.xhtml');
      loads++;
      return document('<div id="nt1" role="doc-footnote">The note.</div>');
    },
    post: message => messages.push(message)
  });
  notes.attach({ document: doc }, '/OEBPS/Text/chapter.xhtml');
  notes.attach({ document: doc }, '/OEBPS/Text/chapter.xhtml');
  const links = doc.querySelectorAll('a');
  for (const link of links) link.onclick = () => { navigations++; return false; };
  const click = link => link.dispatchEvent(new doc.defaultView.MouseEvent('click', { bubbles: true, cancelable: true }));
  click(links[0]);
  assert.equal(navigations, 0);
  assert.equal(messages[0].loading, true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(messages[1].text, 'The note.');
  click(links[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(loads, 1);
  assert.equal(messages.length, 4);
  assert.notEqual(messages[0].requestId, messages[2].requestId);
  click(links[1]);
  assert.equal(navigations, 1);
  assert.equal(messages.length, 4);
});

test('Same-chapter notes need no archive load; failed loads can be retried', async () => {
  const doc = document('<a href="#fn1">1</a><aside id="fn1" role="doc-footnote">Local note.</aside><a href="notes.xhtml#fn2">2</a>');
  const messages = [];
  let loads = 0;
  const notes = footnotes.create({
    load: async () => { loads++; throw Error('Unavailable'); },
    post: message => messages.push(message)
  });
  notes.attach({ document: doc }, '/Text/chapter.xhtml');
  const links = doc.querySelectorAll('a');
  const click = link => link.dispatchEvent(new doc.defaultView.MouseEvent('click', { bubbles: true, cancelable: true }));
  click(links[0]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(loads, 0);
  assert.equal(messages[1].text, 'Local note.');
  for (let attempt = 0; attempt < 2; attempt++) {
    click(links[1]);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(messages.at(-1).error, 'No se pudo leer la nota del EPUB.');
  }
  assert.equal(loads, 2);
});

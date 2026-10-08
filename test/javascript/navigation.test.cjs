const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const navigation = require('../../assets/epubjs/navigation.js');
const epub = fs.readFileSync(path.join(__dirname, '../../assets/epubjs/epub.min.js'), 'utf8');
const jszip = fs.readFileSync(path.join(__dirname, '../../assets/epubjs/jszip.min.js'), 'utf8');

async function fixture(t, { navPath = 'Text/nav.xhtml', href = '001.xhtml#part-two', ncx = false, padding = 0, chapter = 'Text/001.xhtml' } = {}) {
  const window = new JSDOM('', { runScripts: 'outside-only' }).window;
  window.setImmediate = setImmediate;
  window.clearImmediate = clearImmediate;
  window.URL.createObjectURL = () => 'blob:rucio-navigation-test';
  window.URL.revokeObjectURL = () => {};
  window.eval(jszip);
  window.eval(epub);
  const zip = new window.JSZip();
  zip.file('mimetype', 'application/epub+zip');
  zip.file('META-INF/container.xml', '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
  zip.file('OEBPS/content.opf', `<package xmlns="http://www.idpf.org/2007/opf" version="${ncx ? '2.0' : '3.0'}" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">navigation-test</dc:identifier><dc:title>Navigation test</dc:title><dc:language>es</dc:language></metadata><manifest><item id="nav" href="${navPath}" media-type="${ncx ? 'application/x-dtbncx+xml' : 'application/xhtml+xml'}" ${ncx ? '' : 'properties="nav"'}/><item id="root" href="001.xhtml" media-type="application/xhtml+xml"/><item id="chapter" href="${chapter}" media-type="application/xhtml+xml"/></manifest><spine ${ncx ? 'toc="nav"' : ''}><itemref idref="root"/><itemref idref="chapter"/></spine></package>`);
  zip.file(`OEBPS/${navPath}`, ncx
    ? `<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><navMap><navPoint id="entry"><navLabel><text>Chapter</text></navLabel><content src="${href}"/></navPoint></navMap></ncx>`
    : `<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Index</title></head><body><nav epub:type="toc"><ol><li><a href="${href}">Chapter</a><ol><li><a href="${href}">Nested section</a></li></ol></li></ol></nav></body></html>`);
  zip.file('OEBPS/001.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Other chapter</title></head><body><p>Different file with the same name.</p></body></html>');
  zip.file(`OEBPS/${chapter}`, '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter</title></head><body><h1 id="part-two">Selected section</h1><p>Chapter content.</p></body></html>');
  if (padding) zip.file('padding.bin', new window.Uint8Array(padding));
  const bytes = await zip.generateAsync({ type: 'arraybuffer', compression: 'STORE' });
  const book = window.ePub();
  await book.open(bytes);
  await book.ready;
  await book.opened;
  t.after(() => { book.destroy(); window.close(); });
  const rendition = Object.create(window.ePub.Rendition.prototype);
  rendition.book = book;
  rendition.epubcfi = new window.ePub.CFI();
  rendition.emit = () => {};
  rendition.reportLocation = () => {};
  rendition.manager = { display: async (section, target) => { rendition.selected = { section, target }; } };
  return { book, rendition, bytes };
}

test('Nested EPUB 3 index paths select the correct directory and preserve anchors and children', async t => {
  const { book, rendition } = await fixture(t);
  const original = book.navigation.toc[0].href;
  assert.equal(book.spine.get(original).href, '001.xhtml');
  const toc = navigation.toc(book);
  assert.equal(toc[0].href, 'Text/001.xhtml#part-two');
  assert.equal(toc[0].subitems[0].href, toc[0].href);
  assert.equal(book.navigation.toc[0].href, original);
  await rendition._display(toc[0].href);
  assert.equal(rendition.selected.section.href, 'Text/001.xhtml');
  assert.equal(rendition.selected.target, 'Text/001.xhtml#part-two');
  const section = rendition.selected.section;
  await section.load(book.load.bind(book));
  assert.equal(section.document.getElementById('part-two').textContent, 'Selected section');
});

test('A large archived EPUB can open index entries previously rejected with No Section Found', async t => {
  const { book, rendition, bytes } = await fixture(t, { chapter: 'Text/chapter.xhtml', href: 'chapter.xhtml#part-two', padding: 3 * 1024 * 1024 });
  assert.ok(bytes.byteLength > 3 * 1024 * 1024);
  await assert.rejects(rendition._display(book.navigation.toc[0].href), /No Section Found/);
  await rendition._display(navigation.toc(book)[0].href);
  assert.equal(rendition.selected.section.href, 'Text/chapter.xhtml');
});

test('EPUB 2 NCX entries resolve parent directories from the NCX location', async t => {
  const { book, rendition } = await fixture(t, { navPath: 'Navigation/toc.ncx', href: '../Text/001.xhtml#part-two', ncx: true });
  await assert.rejects(rendition._display(book.navigation.toc[0].href), /No Section Found/);
  await rendition._display(navigation.toc(book)[0].href);
  assert.equal(rendition.selected.target, 'Text/001.xhtml#part-two');
});

test('Root indexes and legacy package-relative paths retain their destinations', async t => {
  for (const navPath of ['nav.xhtml', 'Text/nav.xhtml']) {
    const { book, rendition } = await fixture(t, { navPath, href: 'Text/001.xhtml#part-two' });
    await rendition._display(navigation.toc(book)[0].href);
    assert.equal(rendition.selected.target, 'Text/001.xhtml#part-two');
  }
});

test('Encoded spaces and accents match the archive filename', async t => {
  const { book, rendition } = await fixture(t, { chapter: 'Text/Un capítulo.xhtml', href: 'Un%20cap%C3%ADtulo.xhtml#part-two' });
  const target = navigation.toc(book)[0].href;
  assert.equal(target, 'Text/Un capítulo.xhtml#part-two');
  await rendition._display(target);
  await rendition.selected.section.load(book.load.bind(book));
  assert.equal(rendition.selected.section.document.getElementById('part-two').textContent, 'Selected section');
});

test('Missing files, external URLs, grouping headings and CFIs do not map to a guessed chapter', async t => {
  const { book } = await fixture(t);
  const targets = ['../missing/001.xhtml', 'https://example.com/OEBPS/Text/001.xhtml', '', 'epubcfi(/6/4!/4/2:0)'];
  book.navigation.toc = targets.map(href => ({ href, label: 'Entry', subitems: [] }));
  assert.deepEqual(navigation.toc(book).map(item => item.href), targets);
});

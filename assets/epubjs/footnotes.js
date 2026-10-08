(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.RucioFootnotes = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  var namespace = 'http://www.idpf.org/2007/ops';
  var noteId = /^(?:nt|fn|footnote|endnote|note|nota|cite_note)[-_: .]?\d+(?:$|[-_:])/i;
  var noteFile = /(?:^|\/)(?:notas?|notes?|footnotes?|endnotes?)\d*(?:[._-]|$)/i;
  var singleNoteFile = /(?:^|\/)(?:nota|note|footnote|endnote)[-_.]?\d+\.[^/]+$/i;

  function tokens(element, name) {
    var value = name === 'type'
      ? element.getAttributeNS(namespace, 'type') || element.getAttribute('epub:type')
      : element.getAttribute(name);
    return (value || '').toLowerCase().split(/\s+/);
  }

  function has(element, name, values) {
    return tokens(element, name).some(function (value) { return values.indexOf(value) !== -1; });
  }

  function isNote(element) {
    return has(element, 'type', ['footnote', 'endnote', 'rearnote']) ||
      has(element, 'role', ['doc-footnote', 'doc-endnote']) ||
      has(element, 'class', ['nota', 'note', 'footnote', 'endnote']);
  }

  function resolveReference(link, sourcePath) {
    var href = link.getAttribute('href') || '';
    if (!href || /^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(href)) return null;
    if (has(link, 'type', ['backlink']) || has(link, 'role', ['doc-backlink'])) return null;
    if (link.closest('nav, [role="doc-toc"], [role="doc-pagelist"]')) return null;
    var explicit = has(link, 'type', ['noteref']) || has(link, 'role', ['doc-noteref']) ||
      has(link, 'rel', ['footnote', 'endnote']) ||
      has(link, 'class', ['noteref', 'footnote-ref', 'footnote-reference', 'note-ref']);
    var source, target, id;
    try {
      source = new URL(sourcePath, 'https://rucio.epub/');
      target = new URL(href, source);
      id = decodeURIComponent(target.hash.slice(1));
    } catch (error) { return null; }
    var label = (link.textContent || '').trim();
    var shortMarker = /^(?:\[?\d+[a-z]?\]?|[*†‡]+)$/.test(label);
    if (!id && (source.pathname === target.pathname ||
        !(explicit || (singleNoteFile.test(target.pathname) && shortMarker)))) return null;
    var parent = link.parentElement;
    if (!explicit) {
      while (parent && !/^(?:body|html)$/i.test(parent.localName)) {
        if (isNote(parent)) return null;
        parent = parent.parentElement;
      }
      var superscript = link.closest('sup') || link.querySelector('sup');
      if (!noteFile.test(target.pathname) && !noteId.test(id) && !(superscript && shortMarker)) return null;
    }
    return {
      path: target.pathname,
      id: id,
      sourcePath: source.pathname,
      sourceId: link.getAttribute('id') || '',
      label: label.slice(0, 64)
    };
  }

  function containsNoteStart(element) {
    if (element.nodeType !== 1) return false;
    if (isNote(element) || noteId.test(element.getAttribute('id') || '')) return true;
    return Array.prototype.some.call(element.querySelectorAll('[id], a[name]'), function (child) {
      return noteId.test(child.getAttribute('id') || child.getAttribute('name') || '');
    });
  }

  function extractText(doc, reference) {
    var target = reference.id ? doc.getElementById(reference.id) : null;
    if (!reference.id) {
      var notes = Array.prototype.filter.call(doc.querySelectorAll('*'), isNote);
      var outerNotes = notes.filter(function (note) {
        return !notes.some(function (other) { return other !== note && other.contains(note); });
      });
      if (outerNotes.length > 1) throw new Error('Ambiguous footnote document');
      target = outerNotes[0] || doc.querySelector('body');
    }
    if (!target) {
      target = Array.prototype.find.call(doc.querySelectorAll('a[name]'), function (anchor) {
        return anchor.getAttribute('name') === reference.id;
      });
    }
    if (!target || (reference.id && /^(?:body|html)$/i.test(target.localName))) throw new Error('Missing footnote target');
    var container = target;
    var current = target;
    while (current && !/^(?:body|html)$/i.test(current.localName)) {
      if (isNote(current)) { container = current; break; }
      current = current.parentElement;
    }
    if (container === target && !/^(?:p|div|aside|section|li|blockquote)$/i.test(target.localName)) {
      current = target.parentElement;
      while (current && !/^(?:body|html)$/i.test(current.localName)) {
        if (/^(?:p|div|aside|section|li|blockquote)$/i.test(current.localName)) { container = current; break; }
        current = current.parentElement;
      }
    }
    var clone = container.cloneNode(true);
    if (!isNote(container) && noteFile.test(reference.path)) {
      var wrapper = doc.createElement('div');
      wrapper.appendChild(clone);
      var sibling = container.nextSibling;
      while (sibling) {
        if (containsNoteStart(sibling) || (sibling.nodeType === 1 && /^h[1-6]$/i.test(sibling.localName))) break;
        wrapper.appendChild(sibling.cloneNode(true));
        sibling = sibling.nextSibling;
      }
      clone = wrapper;
    }
    Array.prototype.forEach.call(clone.querySelectorAll('script, style, iframe, object, embed, nav'), function (element) {
      element.remove();
    });
    Array.prototype.forEach.call(clone.querySelectorAll('a[href]'), function (anchor) {
      var back = has(anchor, 'type', ['backlink']) || has(anchor, 'role', ['doc-backlink']);
      try {
        var href = new URL(anchor.getAttribute('href'), new URL(reference.path, 'https://rucio.epub/'));
        back = back || (reference.sourceId && href.pathname === reference.sourcePath &&
          decodeURIComponent(href.hash.slice(1)) === reference.sourceId);
      } catch (error) {}
      if (back || /^[\s↩↵←↑]+$/.test(anchor.textContent || '')) anchor.remove();
    });
    function text(node) {
      if (node.nodeType === 3) return node.nodeValue.replace(/\s+/g, ' ');
      if (node.nodeType !== 1) return '';
      var tag = (node.localName || '').toLowerCase();
      if (tag === 'br') return '\n';
      if (tag === 'img') return node.getAttribute('alt') || '';
      var result = Array.prototype.map.call(node.childNodes, text).join('');
      if (tag === 'li') result = '• ' + result;
      return result + (/^(?:p|div|aside|section|blockquote|li|h[1-6])$/.test(tag) ? '\n\n' : '');
    }
    var result = text(clone).replace(/[ \t\u00a0]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
    if (!result) throw new Error('Empty footnote');
    return result;
  }

  function create(options) {
    var documents = new Map();
    var sequence = 0;
    function load(path) {
      if (!documents.has(path)) {
        if (documents.size >= 8) documents.delete(documents.keys().next().value);
        var pending = Promise.resolve().then(function () { return options.load(path); }).catch(function (error) {
          documents.delete(path);
          throw error;
        });
        documents.set(path, pending);
      }
      return documents.get(path);
    }
    function attach(contents, sourcePath) {
      var doc = contents.document;
      if (doc._rucioFootnotes) return;
      doc._rucioFootnotes = true;
      doc.addEventListener('click', function (event) {
        if (event.button > 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
        var element = event.target.nodeType === 1 ? event.target : event.target.parentElement;
        var link = element && element.closest('a[href]');
        if (!link) return;
        var reference = resolveReference(link, sourcePath);
        if (!reference) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        var requestId = String(++sequence);
        options.post({ requestId: requestId, label: reference.label, loading: true });
        var pending = reference.path === reference.sourcePath ? Promise.resolve(doc) : load(reference.path);
        pending.then(function (noteDoc) {
          options.post({ requestId: requestId, label: reference.label, text: extractText(noteDoc, reference) });
        }).catch(function () {
          options.post({ requestId: requestId, label: reference.label, error: 'No se pudo leer la nota del EPUB.' });
        });
      }, true);
    }
    return { attach: attach };
  }

  return { create: create, resolveReference: resolveReference, extractText: extractText };
});

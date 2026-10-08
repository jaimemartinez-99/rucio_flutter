(function(root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.RucioAudio = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  function textNodes(doc) {
    var body = doc.body || doc.querySelector('body') || doc.documentElement;
    var walker = doc.createTreeWalker(body, 4);
    var nodes = [], node;
    while ((node = walker.nextNode())) {
      if (!node.textContent.trim() && /^(html|head|body|div|section|article|ul|ol)$/.test(node.parentElement.localName.toLowerCase())) continue;
      var parent = node.parentElement;
      var skip = false;
      while (parent) {
        var tag = parent.localName.toLowerCase();
        var type = parent.getAttribute('epub:type') || parent.getAttributeNS('http://www.idpf.org/2007/ops', 'type') || '';
        var role = parent.getAttribute('role') || '';
        if (/^(head|script|style|nav|noscript|svg|rt|rp)$/.test(tag) ||
            parent.hasAttribute('hidden') || parent.getAttribute('aria-hidden') === 'true' ||
            /(^|\s)(footnote|endnote|noteref|pagebreak)(\s|$)/.test(type) ||
            /^(doc-footnote|doc-endnote|doc-noteref|doc-pagebreak)$/.test(role)) {
          skip = true;
          break;
        }
        parent = parent.parentElement;
      }
      if (!skip) nodes.push(node);
    }
    return nodes;
  }

  function rangeAt(doc, node, start, end) {
    var range = doc.createRange();
    range.setStart(node, start);
    range.setEnd(node, end);
    return range;
  }

  function blockFor(node) {
    var parent = node.parentElement;
    while (parent && !/^(p|div|li|h[1-6]|blockquote|pre|td|body)$/.test(parent.localName.toLowerCase())) {
      parent = parent.parentElement;
    }
    return parent;
  }

  function extract(section, doc, startRange, maxBytes, limitRange) {
    var nodes = textNodes(doc);
    var paragraphs = [];
    var bytes = 0;
    var lastRange = null;
    var firstRange = null;
    var lastBlock = null;
    var exhausted = true;
    var encoder = new TextEncoder();
    for (var index = 0; index < nodes.length; index++) {
      var node = nodes[index];
      var start = startRange && startRange.startContainer === node ? startRange.startOffset : 0;
      var endRange = rangeAt(doc, node, node.length, node.length);
      if (startRange && endRange.compareBoundaryPoints(0, startRange) <= 0) continue;
      if (limitRange && rangeAt(doc, node, 0, 0).compareBoundaryPoints(0, limitRange) >= 0) break;
      var end = limitRange && limitRange.startContainer === node ? limitRange.startOffset : node.length;
      var remaining = node.textContent.slice(start, end);
      var allowed = maxBytes - bytes - 4;
      var length = 0, count = 0;
      for (var char of remaining) {
        var size = encoder.encode(char).length;
        if (count + size > allowed) break;
        count += size;
        length += char.length;
      }
      if (length < remaining.length) {
        var candidate = remaining.slice(0, length);
        var boundary = Math.max(candidate.lastIndexOf('. '), candidate.lastIndexOf('? '), candidate.lastIndexOf('! '));
        if (boundary > length * 0.5) length = boundary + 1;
        else {
          var space = candidate.lastIndexOf(' ');
          if (space > length * 0.5) length = space + 1;
        }
        exhausted = false;
      }
      if (length <= 0) break;
      var range = rangeAt(doc, node, start, start + length);
      var raw = range.toString();
      var block = blockFor(node);
      var paragraph = paragraphs[paragraphs.length - 1];
      if (!paragraph || block !== lastBlock) {
        paragraph = { text: '', cfiRange: '', runs: [], range: range.cloneRange() };
        paragraphs.push(paragraph);
        bytes += 2;
      }
      paragraph.text += raw;
      paragraph.runs.push({ text: raw, cfiRange: section.cfiFromRange(range) });
      paragraph.range.setEnd(range.endContainer, range.endOffset);
      bytes += encoder.encode(raw).length;
      lastBlock = block;
      if (!firstRange) firstRange = range.cloneRange();
      lastRange = range.cloneRange();
      if (!exhausted) break;
    }
    if (!firstRange) return null;
    firstRange.collapse(true);
    lastRange.collapse(false);
    return {
      startCfi: section.cfiFromRange(firstRange),
      endCfi: section.cfiFromRange(lastRange),
      nextCfi: exhausted ? null : section.cfiFromRange(lastRange),
      href: section.href,
      paragraphs: paragraphs.map(function(paragraph) {
        return { text: paragraph.text.trim(), cfiRange: section.cfiFromRange(paragraph.range), runs: paragraph.runs };
      }).filter(function(paragraph) { return paragraph.text.length > 0; })
    };
  }

  function create(options) {
    var book = options.book;
    function nextSection(section) {
      var next = book.spine.get(section.index + 1);
      while (next && (next.linear === false || next.linear === 'no')) next = book.spine.get(next.index + 1);
      return next;
    }
    async function firstCfi(section) {
      while (section) {
        var contents = await section.load(book.load.bind(book));
        var doc = section.document || contents.ownerDocument || contents;
        var nodes = textNodes(doc);
        if (nodes.length) return section.cfiFromRange(rangeAt(doc, nodes[0], 0, 0));
        section = nextSection(section);
      }
      return null;
    }
    async function read(cfi) {
      var section = book.spine.get(cfi || 0);
      if (!section) throw new Error('No se encontró la posición del libro.');
      var startRange = null;
      while (section) {
        var contents = await section.load(book.load.bind(book));
        var doc = section.document || contents.ownerDocument || contents;
        if (cfi) startRange = options.toRange ? options.toRange(cfi, doc) : await book.getRange(cfi);
        var page = extract(section, doc, startRange, 3500);
        if (page && page.paragraphs.length) {
          if (!page.nextCfi) page.nextCfi = await firstCfi(nextSection(section));
          return page;
        }
        section = nextSection(section);
        startRange = null;
        cfi = null;
      }
      return null;
    }
    return { read: read };
  }
  function createVisual(options) {
    var queue = Promise.resolve();
    var pages = new Map();
    async function read(cfi) {
      if (pages.has(cfi)) return pages.get(cfi);
      await options.display(cfi);
      var visited = new Set();
      while (true) {
        var location = await options.getLocation();
        if (!location || !location.start || !location.end) return null;
        if (visited.has(location.start.cfi)) throw new Error('La paginación no avanza.');
        visited.add(location.start.cfi);
        var paragraphs = [];
        for (var index = location.start.index; index <= location.end.index; index++) {
          var section = options.book.spine.get(index);
          if (!section || section.linear === false || section.linear === 'no') continue;
          var contents = await section.load(options.book.load.bind(options.book));
          var doc = section.document || contents.ownerDocument || contents;
          var start = index === location.start.index ? options.toRange(location.start.cfi, doc) : null;
          var end = index === location.end.index ? options.toRange(location.end.cfi, doc) : null;
          var extracted = extract(section, doc, start, Infinity, end);
          if (extracted) paragraphs.push.apply(paragraphs, extracted.paragraphs);
        }
        var nextCfi = null;
        if (!location.atEnd) {
          await options.next();
          var next = await options.getLocation();
          if (next && next.start && next.start.cfi !== location.start.cfi) nextCfi = next.start.cfi;
        }
        if (paragraphs.length) {
          var page = {
            startCfi: location.start.cfi, endCfi: location.end.cfi,
            nextCfi: nextCfi, href: location.start.href, paragraphs: paragraphs
          };
          pages.set(cfi, page);
          pages.set(page.startCfi, page);
          return page;
        }
        if (!nextCfi) return null;
      }
    }
    return {
      read: function(cfi) {
        var result = queue.then(function() { return read(cfi); });
        queue = result.catch(function() {});
        return result;
      }
    };
  }
  return { create: create, createVisual: createVisual, extract: extract };
});

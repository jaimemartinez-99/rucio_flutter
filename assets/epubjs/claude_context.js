(function(root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.RucioClaudeContext = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  function readableNodes(doc) {
    var body = doc.body || doc.querySelector('body');
    if (!body) throw new Error('No se encontró el texto del capítulo.');
    var walker = doc.createTreeWalker(body, 4);
    var nodes = [], node;
    while ((node = walker.nextNode())) {
      var parent = node.parentElement;
      var skip = false;
      while (parent) {
        var tag = parent.localName.toLowerCase();
        var type = parent.getAttribute('epub:type') || parent.getAttributeNS('http://www.idpf.org/2007/ops', 'type') || '';
        var role = parent.getAttribute('role') || '';
        var style = parent.getAttribute('style') || '';
        if (/^(head|script|style|nav|noscript|svg|rt|rp)$/.test(tag) ||
            parent.hasAttribute('hidden') || parent.getAttribute('aria-hidden') === 'true' ||
            /(^|\s)(footnote|endnote|noteref|pagebreak)(\s|$)/.test(type) ||
            /^(doc-footnote|doc-endnote|doc-noteref|doc-pagebreak)$/.test(role) ||
            /(?:display\s*:\s*none|visibility\s*:\s*hidden)/i.test(style)) {
          skip = true;
          break;
        }
        parent = parent.parentElement;
      }
      if (!skip) nodes.push(node);
    }
    return nodes;
  }

  function blockFor(node) {
    var parent = node.parentElement;
    while (parent && !/^(p|div|li|h[1-6]|blockquote|pre|td|body)$/.test(parent.localName.toLowerCase())) parent = parent.parentElement;
    return parent;
  }

  function prefixText(doc, cutoff) {
    var paragraphs = [], lastBlock = null;
    for (var node of readableNodes(doc)) {
      var range = doc.createRange();
      range.setStart(node, 0);
      range.collapse(true);
      if (cutoff && range.compareBoundaryPoints(0, cutoff) >= 0) break;
      var end = cutoff && cutoff.startContainer === node ? cutoff.startOffset : node.length;
      var text = node.textContent.slice(0, end);
      var block = blockFor(node);
      if (block !== lastBlock || !paragraphs.length) paragraphs.push('');
      paragraphs[paragraphs.length - 1] += text;
      lastBlock = block;
    }
    return paragraphs.map(function(text) { return text.replace(/\s+/g, ' ').trim(); }).filter(Boolean).join('\n\n');
  }

  function chapterAt(doc, cutoff) {
    var chapter = null;
    var nodes = readableNodes(doc);
    for (var element of doc.querySelectorAll('h1,h2,h3,h4,p')) {
      var match = element.textContent.trim().match(/^(?:cap[ií]tulo|chapter|chapitre)\s+(\d+|[IVXLCDM]+)\b/i);
      if (!match) continue;
      if (!nodes.some(function(node) { return element.contains(node); })) continue;
      var range = doc.createRange();
      range.selectNodeContents(element);
      range.collapse(true);
      if (range.compareBoundaryPoints(0, cutoff) > 0) continue;
      var value = match[1].toUpperCase();
      if (/^\d+$/.test(value)) chapter = Number(value);
      else {
        var digits = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 };
        chapter = 0;
        for (var index = 0; index < value.length; index++) {
          var digit = digits[value[index]];
          chapter += index + 1 < value.length && digit < digits[value[index + 1]] ? -digit : digit;
        }
      }
    }
    return chapter;
  }

  function create(options) {
    var queue = Promise.resolve();
    async function read(cfi) {
      if (typeof cfi !== 'string' || !/^epubcfi\(.+\)$/.test(cfi)) throw new Error('No se pudo determinar el límite de lectura.');
      var book = options.book;
      var parsed = new options.CFI(cfi);
      parsed.collapse(false);
      var target = book.spine.get(parsed.spinePos);
      if (!target || !Number.isInteger(target.index) || target.index < 0) throw new Error('La posición de lectura no pertenece al libro.');
      var contents = await target.load(book.load.bind(book));
      var doc = target.document || contents.ownerDocument || contents;
      var cutoff = parsed.toRange(doc);
      if (!cutoff) throw new Error('No se pudo resolver la posición de lectura.');
      cutoff = cutoff.cloneRange();
      cutoff.collapse(false);
      var body = doc.body || doc.querySelector('body');
      if (!body || !body.contains(cutoff.startContainer)) throw new Error('El límite de lectura no está dentro del texto.');
      var cutoffCfi = target.cfiFromRange(cutoff);
      var canonical = new options.CFI(cutoffCfi);
      if (new options.CFI().compare(parsed, canonical) !== 0) {
        var element = doc.documentElement;
        var valid = parsed.path.steps.every(function(step) {
          if (!element || step.type !== 'element') return false;
          element = element.children[step.index];
          return !!element && (!step.id || element.id === step.id);
        });
        var sameBase = parsed.base.steps.length === canonical.base.steps.length && parsed.base.steps.every(function(step, index) {
          return step.type === canonical.base.steps[index].type && step.index === canonical.base.steps[index].index;
        });
        if (!valid || !sameBase || element !== cutoff.startContainer || (parsed.path.terminal.offset || 0) !== cutoff.startOffset) throw new Error('La posición de lectura no se pudo verificar.');
      }
      var sections = [], characters = 0;
      for (var index = 0; index <= target.index; index++) {
        var section = book.spine.get(index);
        if (!section) throw new Error('Falta un capítulo anterior en el libro.');
        if (section.linear === false || section.linear === 'no') {
          if (index === target.index) throw new Error('Esta sección no forma parte del orden de lectura.');
          continue;
        }
        var sectionDoc = doc;
        if (index !== target.index) {
          var loaded = await section.load(book.load.bind(book));
          sectionDoc = section.document || loaded.ownerDocument || loaded;
        }
        var text = prefixText(sectionDoc, index === target.index ? cutoff : null);
        characters += text.length;
        if (characters > (options.maxCharacters || 2000000)) throw new Error('El texto leído es demasiado grande para adjuntarlo completo. No se ha enviado la consulta.');
        if (text) sections.push({ href: section.href, text: text, isCurrent: index === target.index });
      }
      var percentage = book.locations && book.locations.percentageFromCfi(cutoffCfi);
      return {
        cutoffCfi: cutoffCfi, sections: sections, spineIndex: target.index,
        chapterNumber: chapterAt(doc, cutoff),
        percentage: typeof percentage === 'number' && Number.isFinite(percentage) && percentage >= 0 && percentage <= 1 ? Math.round(percentage * 10000) / 100 : null
      };
    }
    return {
      read: function(cfi) {
        var result = queue.then(function() { return read(cfi); });
        queue = result.catch(function() {});
        return result;
      }
    };
  }
  return { create: create };
});

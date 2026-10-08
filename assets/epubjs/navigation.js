(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.RucioNavigation = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  function key(url) {
    return url.origin + decodeURI(url.pathname);
  }

  function toc(book) {
    var base = 'https://rucio.epub/';
    var packaging = book.packaging || {};
    var navPath = packaging.navPath || packaging.ncxPath;
    var navUrl = navPath ? new URL(book.resolve(navPath), base) : null;
    var sections = new Map();
    book.spine.each(function (section) {
      sections.set(key(new URL(book.resolve(section.href), base)), section);
    });

    function target(href) {
      if (!href || href.indexOf('epubcfi(') === 0) return href;
      var section;
      try {
        if (navUrl) section = sections.get(key(new URL(href, navUrl)));
      } catch (error) {}
      if (!section) section = book.spine.get(href);
      if (!section) return href;
      var fragment = href.indexOf('#');
      return section.href + (fragment === -1 ? '' : href.slice(fragment));
    }

    function item(entry) {
      return Object.assign({}, entry, {
        href: target(entry.href),
        subitems: (entry.subitems || []).map(item)
      });
    }

    return (book.navigation.toc || []).map(item);
  }

  return { toc: toc };
});

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rucio_flutter/models/epub_metadata.dart';
import 'package:rucio_flutter/services/epub_metadata_service.dart';

List<int> epub({
  String metadata = '',
  String manifest = '',
  Map<String, String> files = const {},
}) {
  final archive = Archive();
  final sources = {
    'META-INF/container.xml':
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/package.opf"/></rootfiles></container>',
    'OPS/package.opf':
        '''<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf" version="3.0">
      <metadata>$metadata</metadata><manifest>$manifest</manifest></package>''',
    ...files,
  };
  for (final entry in sources.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ZipEncoder().encode(archive);
}

void main() {
  test(
    'Reads namespaced metadata, Calibre pages and a plain text synopsis',
    () {
      final bytes = epub(
        metadata: '''
      <dc:title>Una historia</dc:title>
      <dc:creator>Autora Uno</dc:creator><dc:creator>Autor Dos</dc:creator>
      <dc:contributor opf:role="trl">Traductora</dc:contributor>
      <dc:publisher>Editorial</dc:publisher><dc:language>es</dc:language>
      <dc:date opf:event="modification">2025-01-01</dc:date>
      <dc:date>1845-01-01T00:00:00Z</dc:date>
      <dc:identifier opf:scheme="ISBN">9781234567890</dc:identifier>
      <dc:subject>Novela</dc:subject>
      <dc:description>&lt;p&gt;Una &lt;b&gt;historia&lt;/b&gt;.&lt;/p&gt;&lt;p&gt;Otra línea.&lt;/p&gt;</dc:description>
      <meta name="calibre:user_metadata:#pages" content='{ "label": "pages", "#value#": 554 }'/>
      <meta name="calibre:series" content="Colección"/>
    ''',
      );
      final data = EpubMetadataService.parse(bytes);
      expect(data.title, 'Una historia');
      expect(data.authors, ['Autora Uno', 'Autor Dos']);
      expect(data.contributors, ['Traductora (traducción)']);
      expect(data.publisher, 'Editorial');
      expect(data.languages, ['es']);
      expect(data.publicationDate, '1845-01-01');
      expect(data.identifiers, ['9781234567890']);
      expect(data.subjects, ['Novela']);
      expect(data.description, 'Una historia.\nOtra línea.');
      expect(data.pageCount, 554);
      expect(data.pageCountSource, EpubPageCountSource.metadata);
      expect(data.series, 'Colección');
      expect(data.fileSize, bytes.length);
    },
  );

  test('Counts distinct EPUB 3 page references and resolves relative paths', () {
    final data = EpubMetadataService.parse(
      epub(
        metadata:
            '<dc:title>EPUB 3</dc:title><dc:contributor id="translator">Nombre</dc:contributor><meta property="role" refines="#translator">trl</meta>',
        manifest:
            '<item id="nav" href="../Nav%20Dir/nav.xhtml" properties="scripted nav"/>',
        files: {
          'Nav Dir/nav.xhtml':
              '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
        <nav epub:type="toc"><a href="chapter.xhtml">Capítulo</a></nav>
        <nav epub:type="page-list"><a href="chapter.xhtml#p200">200</a><a href="chapter.xhtml#p201">201</a><a href="chapter.xhtml#p201">201</a></nav>
        </body></html>''',
        },
      ),
    );
    expect(data.pageCount, 2);
    expect(data.pageCountSource, EpubPageCountSource.pageList);
    expect(data.contributors, ['Nombre (traducción)']);
  });

  test('Reads EPUB 2 NCX pages without counting chapter navigation', () {
    final data = EpubMetadataService.parse(
      epub(
        manifest:
            '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        files: {
          'OPS/toc.ncx': '''<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
        <navMap><navPoint><content src="chapter.xhtml"/></navPoint></navMap>
        <pageList><pageTarget><content src="chapter.xhtml#pi"/></pageTarget><pageTarget><content src="chapter.xhtml#p1"/></pageTarget></pageList>
        </ncx>''',
        },
      ),
    );
    expect(data.pageCount, 2);
    expect(data.pageCountSource, EpubPageCountSource.pageList);
  });

  test('Prefers an explicit page count over a partial page list', () {
    final data = EpubMetadataService.parse(
      epub(
        metadata: '<meta property="schema:numberOfPages">300</meta>',
        manifest: '<item id="nav" href="nav.xhtml" properties="nav"/>',
        files: {
          'OPS/nav.xhtml':
              '<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="page-list"><a href="p1">1</a></nav>',
        },
      ),
    );
    expect(data.pageCount, 300);
    expect(data.pageCountSource, EpubPageCountSource.metadata);
  });

  test('Missing or damaged optional pagination preserves other metadata', () {
    for (final nav in ['<broken', '<nav/>']) {
      final data = EpubMetadataService.parse(
        epub(
          metadata:
              '''<dc:title>Libro sin páginas</dc:title><meta name="calibre:pages" content="-1"/><meta name="calibre:user_metadata:#pages" content="invalid json"/>''',
          manifest: '<item id="nav" href="nav.xhtml" properties="nav"/>',
          files: {'OPS/nav.xhtml': nav},
        ),
      );
      expect(data.title, 'Libro sin páginas');
      expect(data.pageCount, isNull);
      expect(data.pageCountSource, isNull);
    }
  });

  test('Rejects an EPUB without its package instead of inventing metadata', () {
    final archive = Archive();
    final bytes = utf8.encode('<container/>');
    archive.addFile(ArchiveFile('META-INF/container.xml', bytes.length, bytes));
    expect(
      () => EpubMetadataService.parse(ZipEncoder().encode(archive)),
      throwsFormatException,
    );
  });
}

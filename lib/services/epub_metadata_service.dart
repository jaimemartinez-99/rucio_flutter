import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import '../models/book.dart';
import '../models/epub_metadata.dart';
import 'cache_service.dart';

class EpubMetadataService {
  EpubMetadataService({required this.client, CacheService? cache})
    : _cache = cache ?? CacheService();

  final SupabaseClient client;
  final CacheService _cache;

  Future<EpubMetadata> load(Book book) async {
    final user = client.auth.currentUser;
    if (user == null || user.id != book.userId) {
      throw StateError('Inicia sesión de nuevo para consultar este libro.');
    }
    var path = await _cache.getCachedEpubPath(book.id);
    if (path == null) {
      final filePath = book.filePath;
      if (filePath == null) {
        throw StateError('El archivo EPUB ya no está disponible.');
      }
      final url = await client.storage
          .from('libros')
          .createSignedUrl(filePath, 3600);
      path = await _cache.downloadAndCache(book.id, url);
    }
    final epubPath = path;
    return Isolate.run(() => parse(File(epubPath).readAsBytesSync()));
  }

  static EpubMetadata parse(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    XmlDocument readXml(String path) {
      final file = archive.findFile(path);
      if (file == null || !file.isFile) {
        throw const FormatException('Faltan los metadatos del EPUB.');
      }
      return XmlDocument.parse(utf8.decode(file.content));
    }

    final container = readXml('META-INF/container.xml');
    final rootfile = container.descendants
        .whereType<XmlElement>()
        .where((element) => element.localName == 'rootfile')
        .firstOrNull;
    final packagePath = rootfile?.getAttribute('full-path');
    if (packagePath == null) {
      throw const FormatException(
        'El EPUB no indica dónde están sus metadatos.',
      );
    }
    final package = readXml(packagePath);
    final metadata = package.rootElement.childElements
        .where((element) => element.localName == 'metadata')
        .firstOrNull;
    if (metadata == null) {
      throw const FormatException('Este EPUB no contiene metadatos.');
    }
    final elements = metadata.childElements.toList();
    List<String> values(String name) => elements
        .where((element) => element.localName == name)
        .map((element) => _plainText(element.innerText))
        .where((text) => text.isNotEmpty)
        .toSet()
        .toList();
    String? metaValue(String key) => elements
        .where(
          (element) =>
              element.localName == 'meta' &&
              (element.getAttribute('name') == key ||
                  element.getAttribute('property') == key) &&
              element.getAttribute('refines') == null,
        )
        .map((element) => element.getAttribute('content') ?? element.innerText)
        .where((value) => value.trim().isNotEmpty)
        .firstOrNull
        ?.trim();

    int? pageCount;
    for (final key in ['schema:numberOfPages', 'page-count', 'calibre:pages']) {
      pageCount = _positiveInt(metaValue(key));
      if (pageCount != null) break;
    }
    if (pageCount == null) {
      for (final element in elements.where(
        (element) =>
            element
                .getAttribute('name')
                ?.startsWith('calibre:user_metadata:') ??
            false,
      )) {
        try {
          final custom = jsonDecode(element.getAttribute('content') ?? '');
          if (custom is Map &&
              [
                'pages',
                'paginas',
                'páginas',
              ].contains(custom['label']?.toString().toLowerCase())) {
            pageCount = _positiveInt(custom['#value#']?.toString());
            if (pageCount != null) break;
          }
        } on FormatException {
          continue;
        }
      }
    }
    var pageSource = pageCount == null ? null : EpubPageCountSource.metadata;
    if (pageCount == null) {
      final manifest = package.descendants.whereType<XmlElement>().where(
        (element) => element.localName == 'item',
      );
      final candidates = manifest.where(
        (element) =>
            (element.getAttribute('properties') ?? '')
                .split(RegExp(r'\s+'))
                .contains('nav') ||
            element.getAttribute('media-type') == 'application/x-dtbncx+xml',
      );
      for (final item in candidates) {
        final href = item.getAttribute('href');
        if (href == null) continue;
        try {
          final path = Uri.parse(packagePath).resolve(href).path;
          final navigation = readXml(Uri.decodeComponent(path));
          final targets = <String>{};
          for (final element
              in navigation.descendants.whereType<XmlElement>()) {
            if (element.localName == 'nav' &&
                (_attribute(element, 'type') ?? '')
                    .split(RegExp(r'\s+'))
                    .contains('page-list')) {
              for (final link
                  in element.descendants.whereType<XmlElement>().where(
                    (e) => e.localName == 'a',
                  )) {
                final target = link.getAttribute('href');
                if (target != null && target.isNotEmpty) targets.add(target);
              }
            } else if (element.localName == 'pageList') {
              for (final target
                  in element.descendants.whereType<XmlElement>().where(
                    (e) => e.localName == 'content',
                  )) {
                final src = target.getAttribute('src');
                if (src != null && src.isNotEmpty) targets.add(src);
              }
            }
          }
          if (targets.isNotEmpty) {
            pageCount = targets.length;
            pageSource = EpubPageCountSource.pageList;
            break;
          }
        } on FormatException {
          continue;
        } on XmlException {
          continue;
        }
      }
    }
    final contributors = elements
        .where((element) => element.localName == 'contributor')
        .map((element) {
          final id = element.getAttribute('id');
          final role =
              _attribute(element, 'role') ??
              (id == null
                  ? null
                  : elements
                        .where(
                          (meta) =>
                              meta.getAttribute('refines') == '#$id' &&
                              meta.getAttribute('property') == 'role',
                        )
                        .firstOrNull
                        ?.innerText
                        .trim());
          final name = _plainText(element.innerText);
          return role == 'trl' ? '$name (traducción)' : name;
        })
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    final date = elements
        .where(
          (element) =>
              element.localName == 'date' &&
              _attribute(element, 'event') != 'modification',
        )
        .map((element) => element.innerText.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    return EpubMetadata(
      title: values('title').firstOrNull,
      authors: values('creator'),
      contributors: contributors,
      publisher: values('publisher').firstOrNull,
      languages: values('language'),
      publicationDate: date?.split('T').first,
      identifiers: values('identifier'),
      subjects: values('subject'),
      description: values('description').firstOrNull,
      pageCount: pageCount,
      pageCountSource: pageSource,
      series: metaValue('calibre:series') ?? metaValue('belongs-to-collection'),
      fileSize: bytes.length,
    );
  }

  static int? _positiveInt(String? value) {
    final number = num.tryParse(value?.trim() ?? '');
    return number != null &&
            number.isFinite &&
            number > 0 &&
            number == number.roundToDouble()
        ? number.toInt()
        : null;
  }

  static String? _attribute(XmlElement element, String name) => element
      .attributes
      .where((attribute) => attribute.name.local == name)
      .firstOrNull
      ?.value;

  static String _plainText(String value) {
    var text = value
        .replaceAll(
          RegExp(r'<br\s*/?>|</(?:p|div|li)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ');
    try {
      text = XmlDocument.parse('<text>$text</text>').rootElement.innerText;
    } on XmlException {
      return text.trim();
    }
    return text.trim();
  }
}

final epubMetadataServiceProvider = Provider<EpubMetadataService>((ref) {
  return EpubMetadataService(client: Supabase.instance.client);
});

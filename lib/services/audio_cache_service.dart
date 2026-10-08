import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/audio_page.dart';

class AudioCacheService {
  AudioCacheService({this.directory, this.maxBytes = 500 * 1024 * 1024});

  final Directory? directory;
  final int maxBytes;

  String key(String userId, String bookId, String text, AudioVoice voice) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode([
                'audiorucio-v1',
                userId,
                bookId,
                voice.apiName,
                'MP3',
                text,
              ]),
            ),
          )
          .toString();

  Future<Directory> _root() async {
    final root =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/audiorucio',
        );
    await root.create(recursive: true);
    return root;
  }

  Future<File?> find(String key) async {
    final file = File('${(await _root()).path}/$key.mp3');
    if (!await file.exists()) return null;
    if (await file.length() == 0) {
      await file.delete();
      return null;
    }
    await file.setLastModified(DateTime.now());
    return file;
  }

  Future<File> store(
    String key,
    Uint8List bytes, {
    String? protectedPath,
  }) async {
    final root = await _root();
    final file = File('${root.path}/$key.mp3');
    final temporary = File('${file.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    await trim(protectedPaths: {file.path, ?protectedPath});
    return file;
  }

  Future<List<File>> _files() async => (await (await _root()).list().toList())
      .whereType<File>()
      .where((file) => file.path.endsWith('.mp3'))
      .toList();

  Future<int> sizeBytes() async {
    var total = 0;
    for (final file in await _files()) {
      total += await file.length();
    }
    return total;
  }

  Future<void> trim({Set<String> protectedPaths = const {}}) async {
    final entries = <({File file, FileStat stat})>[];
    var total = 0;
    for (final file in await _files()) {
      final stat = await file.stat();
      entries.add((file: file, stat: stat));
      total += stat.size;
    }
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      if (protectedPaths.contains(entry.file.path)) continue;
      await entry.file.delete();
      total -= entry.stat.size;
    }
  }

  Future<void> clear() async {
    for (final file in await _files()) {
      await file.delete();
    }
  }
}

final audioCacheServiceProvider = Provider<AudioCacheService>((ref) {
  return AudioCacheService();
});

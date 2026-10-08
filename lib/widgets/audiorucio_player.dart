import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_page.dart';
import '../providers/audiorucio_provider.dart';
import 'audio_usage_dialog.dart';

class AudioRucioPlayer extends ConsumerWidget {
  const AudioRucioPlayer({
    super.key,
    required this.session,
    required this.onExit,
  });

  final AudioSession session;
  final VoidCallback onExit;

  String _time(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 999999);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _connect(
    BuildContext context,
    AudioRucioController audio,
  ) async {
    final input = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conectar Google Cloud'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Usa una clave de tu proyecto con Cloud Text-to-Speech y facturación activados.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: input,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Clave de API'),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context, value.trim());
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'La clave se mantiene solo durante esta sesión. El audio se guarda en este PC.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('Conectar'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
    if (key != null && context.mounted) {
      audio.configure(key);
      await audio.togglePlayback();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioRucioProvider(session));
    final title = session.book?.title ?? 'Tu libro';
    final author = session.book?.author ?? '';
    final page = audio.page;
    final canControl = !audio.isBusy && page != null;
    return Material(
      color: const Color(0xFF0F0E17),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF35271F), Color(0xFF171420), Color(0xFF0F0E17)],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Volver al libro',
                      onPressed: () {
                        unawaited(audio.close());
                        onExit();
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.graphic_eq, color: Color(0xFFF2A65A)),
                    const SizedBox(width: 10),
                    Text(
                      'Audiorucio',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Consumo mensual',
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const AudioUsageDialog(),
                      ),
                      icon: const Icon(Icons.payments_outlined),
                    ),
                    IconButton(
                      tooltip: 'Conectar Google Cloud',
                      onPressed: audio.isBusy
                          ? null
                          : () => _connect(context, audio),
                      icon: Icon(
                        audio.isConfigured
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_outlined,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones de audio',
                      enabled: !audio.isBusy,
                      onSelected: (_) => unawaited(audio.clearCache()),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'clear',
                          child: ListTile(
                            leading: const Icon(
                              Icons.cleaning_services_outlined,
                            ),
                            title: const Text('Vaciar caché de audio'),
                            subtitle: Text(
                              '${(audio.cacheBytes / 1024 / 1024).toStringAsFixed(1)} MB de 500 MB · Este PC',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cover = _BookDisplay(
                      title: title,
                      author: author,
                      coverUrl: session.book?.coverUrl,
                    );
                    final text = _ReadingDisplay(
                      page: page,
                      finished: audio.finished,
                    );
                    if (constraints.maxWidth >= 760) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(40, 12, 40, 24),
                        child: Row(
                          children: [
                            Expanded(flex: 4, child: cover),
                            const SizedBox(width: 44),
                            Expanded(flex: 6, child: text),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          SizedBox(height: 150, child: cover),
                          const SizedBox(height: 16),
                          Expanded(child: text),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (audio.error != null)
                _StatusBanner(
                  text: audio.error!,
                  color: const Color(0xFFF87171),
                )
              else if (!audio.isConfigured && !audio.isBusy)
                _StatusBanner(
                  text:
                      'Conecta Google Cloud para escuchar con Standard-H o Autonoe.',
                  action: TextButton(
                    onPressed: () => _connect(context, audio),
                    child: const Text('Conectar'),
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1827),
                  border: Border(top: BorderSide(color: Color(0xFF352F42))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(_time(audio.position)),
                        Expanded(
                          child: Slider(
                            label: _time(audio.position),
                            value: audio.position.inMilliseconds
                                .toDouble()
                                .clamp(
                                  0,
                                  audio.duration.inMilliseconds.toDouble(),
                                ),
                            max: audio.duration.inMilliseconds > 0
                                ? audio.duration.inMilliseconds.toDouble()
                                : 1,
                            onChanged:
                                canControl && audio.duration > Duration.zero
                                ? (value) => unawaited(
                                    audio.seek(
                                      Duration(milliseconds: value.round()),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        Text(_time(audio.duration)),
                      ],
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 28,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 245,
                          child: DropdownButtonFormField<AudioVoice>(
                            key: ValueKey(audio.voice),
                            initialValue: audio.voice,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Voz',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: AudioVoice.values
                                .map(
                                  (voice) => DropdownMenuItem(
                                    value: voice,
                                    child: Text(
                                      voice.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: audio.isBusy
                                ? null
                                : (voice) {
                                    if (voice != null) {
                                      unawaited(audio.changeVoice(voice));
                                    }
                                  },
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Atrasar 5 segundos',
                              iconSize: 30,
                              onPressed: canControl
                                  ? () => unawaited(
                                      audio.skip(const Duration(seconds: -5)),
                                    )
                                  : null,
                              icon: const Icon(Icons.replay_5_rounded),
                            ),
                            const SizedBox(width: 14),
                            SizedBox(
                              width: 58,
                              height: 58,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: const CircleBorder(),
                                ),
                                onPressed: audio.isBusy
                                    ? null
                                    : () => unawaited(audio.togglePlayback()),
                                child: audio.isBusy
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        audio.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        size: 36,
                                        semanticLabel: audio.isPlaying
                                            ? 'Pausar'
                                            : 'Reproducir',
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            IconButton(
                              tooltip: 'Adelantar 15 segundos',
                              onPressed: canControl
                                  ? () => unawaited(
                                      audio.skip(const Duration(seconds: 15)),
                                    )
                                  : null,
                              icon: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fast_forward_rounded),
                                  Text('15 s', style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 190,
                          child: Row(
                            children: [
                              Icon(
                                audio.volume == 0
                                    ? Icons.volume_off_outlined
                                    : Icons.volume_up_outlined,
                                size: 22,
                              ),
                              Expanded(
                                child: Slider(
                                  value: audio.volume,
                                  label: '${(audio.volume * 100).round()}%',
                                  onChanged: (value) =>
                                      unawaited(audio.setVolume(value)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      audio.isBusy
                          ? 'Preparando la lectura…'
                          : audio.finished
                          ? 'Has llegado al final del libro'
                          : audio.fromCache
                          ? 'Audio en este PC · Disponible sin conexión'
                          : 'Google Cloud · Caché local de hasta 500 MB',
                      style: const TextStyle(
                        color: Color(0xFFA8A1B5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.text,
    this.action,
    this.color = const Color(0xFFE8E4F0),
  });
  final String text;
  final Widget? action;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: TextStyle(color: color)),
        ),
        ?action,
      ],
    ),
  );
}

class _BookDisplay extends StatefulWidget {
  const _BookDisplay({
    required this.title,
    required this.author,
    this.coverUrl,
  });
  final String title;
  final String author;
  final String? coverUrl;

  @override
  State<_BookDisplay> createState() => _BookDisplayState();
}

class _BookDisplayState extends State<_BookDisplay> {
  Uint8List? _coverBytes;

  String get title => widget.title;
  String get author => widget.author;

  @override
  void initState() {
    super.initState();
    _decodeCover();
  }

  @override
  void didUpdateWidget(_BookDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) _decodeCover();
  }

  void _decodeCover() {
    _coverBytes = null;
    if (widget.coverUrl != null) {
      try {
        _coverBytes = base64Decode(widget.coverUrl!.split(',').last);
      } on FormatException {
        _coverBytes = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _coverBytes;
    final placeholder = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF594332), Color(0xFF252336)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 220,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_stories_outlined,
                  size: 64,
                  color: Color(0xFFF2A65A),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 220) {
          return Row(
            children: [
              SizedBox(
                width: 95,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: bytes == null
                      ? const Center(
                          child: Icon(Icons.auto_stories_outlined, size: 64),
                        )
                      : Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: _title(context)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 0.72,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x80000000),
                          blurRadius: 32,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: bytes == null
                        ? placeholder
                        : Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => placeholder,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            _title(context),
          ],
        );
      },
    );
  }

  Widget _title(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'ESCUCHANDO AHORA',
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 2,
          color: Color(0xFFF2A65A),
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      if (author.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          author,
          style: const TextStyle(color: Color(0xFFA8A1B5), fontSize: 16),
        ),
      ],
    ],
  );
}

class _ReadingDisplay extends StatelessWidget {
  const _ReadingDisplay({required this.page, required this.finished});
  final AudioPage? page;
  final bool finished;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
    decoration: BoxDecoration(
      color: const Color(0xB31A1827),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF352F42)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.subject_rounded,
              color: Color(0xFFF2A65A),
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              finished ? 'Lectura completada' : 'Texto de la lectura',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            const Icon(
              Icons.headphones_rounded,
              color: Color(0xFF7C748E),
              size: 20,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: page == null
              ? const Center(child: Text('Preparando el texto del libro…'))
              : SingleChildScrollView(
                  key: ValueKey(page!.startCfi),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: page!.paragraphs
                          .map(
                            (paragraph) => Padding(
                              key: ValueKey(paragraph.cfiRange),
                              padding: const EdgeInsets.only(bottom: 22),
                              child: Text(
                                paragraph.text,
                                style: const TextStyle(
                                  fontSize: 23,
                                  height: 1.65,
                                  color: Color(0xFFE8E4F0),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

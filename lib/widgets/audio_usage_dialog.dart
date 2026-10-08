import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_page.dart';
import '../services/audio_usage_service.dart';

String _number(int value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => '.',
);

String _money(double value) =>
    '${value.toStringAsFixed(value > 0 && value < 0.0001 ? 6 : 4)} USD';

class AudioUsageDialog extends ConsumerStatefulWidget {
  const AudioUsageDialog({super.key});

  @override
  ConsumerState<AudioUsageDialog> createState() => _AudioUsageDialogState();
}

class _AudioUsageDialogState extends ConsumerState<AudioUsageDialog> {
  late String _month;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final usage = ref.read(audioUsageServiceProvider);
    _month = usage.currentMonth;
    unawaited(usage.initialize());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _monthLabel(String month) {
    const names = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    final parts = month.split('-');
    return '${names[int.parse(parts[1]) - 1]} ${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(audioUsageServiceProvider);
    final months = {...usage.months, _month}.toList()
      ..sort((a, b) => b.compareTo(a));
    final total = AudioVoice.values.fold<double>(
      0,
      (sum, voice) => sum + usage.totals(_month, voice).estimatedUsd(voice),
    );
    final unconfirmed = AudioVoice.values.fold<int>(
      0,
      (sum, voice) => sum + usage.totals(_month, voice).unconfirmedCharacters,
    );
    final since = usage.trackedSince;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1827),
      title: const Text('Consumo mensual'),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _month,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Mes'),
                    items: [
                      for (final month in months)
                        DropdownMenuItem(
                          value: month,
                          child: Text(
                            _monthLabel(month),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (month) {
                      if (month != null) setState(() => _month = month);
                    },
                  ),
                  const SizedBox(height: 20),
                  const Text('Coste estimado tras el tramo gratuito'),
                  const SizedBox(height: 4),
                  Text(
                    usage.isLoaded
                        ? _money(total)
                        : usage.error == null
                        ? 'Cargando…'
                        : 'No disponible',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFFF2A65A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (since != null)
                    Text(
                      'Registro desde ${since.day.toString().padLeft(2, '0')}/'
                      '${since.month.toString().padLeft(2, '0')}/${since.year} '
                      '· Este dispositivo · Mes según la hora local',
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Supone el tramo gratuito disponible. No incluye el uso '
                    'anterior al registro ni el de otros dispositivos o aplicaciones.',
                  ),
                  const SizedBox(height: 16),
                  if (usage.error != null) ...[
                    Text(
                      usage.error!,
                      style: const TextStyle(color: Color(0xFFF87171)),
                    ),
                    TextButton(
                      onPressed: () => unawaited(usage.initialize()),
                      child: const Text('Reintentar'),
                    ),
                  ],
                  if (unconfirmed > 0) ...[
                    Text(
                      '${_number(unconfirmed)} caracteres sin confirmar. '
                      'Incluye solicitudes en curso o sin respuesta por cortes, '
                      'cancelaciones o errores. Google podría haberlas facturado; '
                      'no están sumadas al coste estimado.',
                      style: const TextStyle(color: Color(0xFFF2A65A)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (usage.isLoaded)
                    for (final voice in AudioVoice.values) ...[
                      _VoiceUsage(
                        voice: voice,
                        totals: usage.totals(_month, voice),
                      ),
                      const SizedBox(height: 12),
                    ],
                  const Text(
                    'Solo cuenta el audio generado por Audiorucio en este PC, '
                    'sumando todas las claves utilizadas. Escuchar la caché no suma. '
                    'Vaciarla no borra este registro.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'La estimación supone que el tramo gratuito está disponible '
                    'para este consumo. El uso previo, otros dispositivos o '
                    'aplicaciones pueden consumirlo. No incluye impuestos, '
                    'conversión de moneda ni descuentos. No es la factura de Google.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tarifas de referencia: Google Cloud, 08/10/2026. '
                    'Puedes comprobar el importe registrado por Google en '
                    'Facturación → Informes, filtrando por proyecto y servicio '
                    'Cloud Text-to-Speech.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _VoiceUsage extends StatelessWidget {
  const _VoiceUsage({required this.voice, required this.totals});

  final AudioVoice voice;
  final AudioUsageTotals totals;

  @override
  Widget build(BuildContext context) {
    final remaining = (voice.freeCharacters - totals.characters).clamp(
      0,
      voice.freeCharacters,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252336),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(voice.label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('${_number(totals.characters)} caracteres generados'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (totals.characters / voice.freeCharacters).clamp(0, 1),
            color: const Color(0xFFF2A65A),
          ),
          const SizedBox(height: 8),
          Text(
            'Tramo gratuito de referencia: ${_number(voice.freeCharacters)} '
            'caracteres/mes · Quedarían ${_number(remaining)}',
          ),
          const SizedBox(height: 8),
          Text('Coste estimado: ${_money(totals.estimatedUsd(voice))}'),
          Text(
            'Valor sin tramo gratuito: ${_money(totals.listPriceUsd(voice))}',
          ),
          Text('Después del tramo: ${voice.usdPerMillion.toInt()} USD/millón'),
        ],
      ),
    );
  }
}

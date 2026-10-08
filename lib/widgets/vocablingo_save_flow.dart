import 'package:flutter/material.dart';

import '../services/vocablingo_service.dart';

Future<void> saveToVocablingo(
  BuildContext context, {
  required VocablingoService service,
  required String selection,
  String? email,
}) async {
  try {
    if (!service.isAuthenticated) {
      final signedIn = await showDialog<bool>(
        context: context,
        builder: (_) => _VocablingoSignInDialog(service: service, email: email),
      );
      if (signedIn != true) return;
    }
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Guardando en Vocablingo...')),
    );
    final result = await service.saveSelection(selection);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    final definition = result['definition'] as String?;
    if (result['type'] == 'word' &&
        definition != null &&
        definition.trim().isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text('Definición de ${result['text']}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Palabra guardada en Vocablingo · Definición RAE'),
                const SizedBox(height: 16),
                SelectableText(definition),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }
    final type = result['type'] == 'word'
        ? 'Palabra y definición guardadas'
        : 'Frase guardada';
    messenger.showSnackBar(SnackBar(content: Text('$type: ${result['text']}')));
  } catch (error) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo guardar en Vocablingo: $error')),
    );
  }
}

class _VocablingoSignInDialog extends StatefulWidget {
  const _VocablingoSignInDialog({required this.service, this.email});

  final VocablingoService service;
  final String? email;

  @override
  State<_VocablingoSignInDialog> createState() =>
      _VocablingoSignInDialogState();
}

class _VocablingoSignInDialogState extends State<_VocablingoSignInDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.email ?? '');
  }

  Future<void> _signIn() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await widget.service.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'No se pudo iniciar sesión: $error';
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Iniciar sesión en Vocablingo'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Usa tu cuenta de Vocablingo para guardar la selección.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isLoading,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Introduce tu correo electrónico.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_isLoading,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Introduce tu contraseña.'
                      : null,
                  onFieldSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _signIn,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Iniciar sesión'),
        ),
      ],
    );
  }
}

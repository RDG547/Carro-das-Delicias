import 'dart:async';

import 'package:flutter/material.dart';

import '../services/play_update_service.dart';

class MandatoryUpdateGate extends StatefulWidget {
  const MandatoryUpdateGate({super.key, required this.child, this.service});
  final Widget child;
  final PlayUpdateService? service;

  @override
  State<MandatoryUpdateGate> createState() => _MandatoryUpdateGateState();
}

class _MandatoryUpdateGateState extends State<MandatoryUpdateGate> {
  late final _service = widget.service ?? PlayUpdateService();
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    unawaited(_service.start());
  }

  void _changed() {
    if (!mounted) return;
    if (_service.updateRequired && !_blocked) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() => _blocked = _service.updateRequired);
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: _blocked,
        child: ExcludeSemantics(
          excluding: _blocked,
          child: AbsorbPointer(absorbing: _blocked, child: widget.child),
        ),
      ),
      if (_blocked) ...[
        const ModalBarrier(dismissible: false, color: Colors.black54),
        SafeArea(
          child: Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Nova versão disponível',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Atualize o Carro das Delícias pela Play Store para continuar.',
                      textAlign: TextAlign.center,
                    ),
                    if (_service.message != null) ...[
                      const SizedBox(height: 12),
                      Text(_service.message!, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _service.updating ? null : _service.update,
                        child: Text(
                          _service.updating
                              ? 'Atualizando…'
                              : 'Atualizar agora',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _service.updating ? null : _service.openStore,
                      child: const Text(
                        'Abrir Play Store',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

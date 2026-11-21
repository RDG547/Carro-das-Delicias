import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/admin_report_service.dart';

class AdminReportDialog extends StatefulWidget {
  const AdminReportDialog({super.key});
  @override
  State<AdminReportDialog> createState() => _AdminReportDialogState();
}

class _AdminReportDialogState extends State<AdminReportDialog> {
  AdminReportScope _scope = AdminReportScope.allProducts;
  AdminReportData? _report;
  String? _error;
  bool _loading = true;
  bool _exporting = false;
  int _page = 0;
  int _requestId = 0;
  StreamSubscription<AuthState>? _auth;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedOut && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
    });
    try {
      final report = await AdminReportService.load(_scope);
      if (mounted && request == _requestId) {
        setState(() {
          _report = report;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _requestId) {
        setState(() {
          _error =
              'Não foi possível carregar o relatório. Confira a conexão e tente novamente.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _export(AdminReportFormat format) async {
    final report = _report;
    if (report == null ||
        _exporting ||
        Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _exporting = true);
    try {
      if (format == AdminReportFormat.text) {
        await Clipboard.setData(ClipboardData(text: report.toText()));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Relatório completo copiado.')),
          );
        }
      } else {
        final file = await AdminReportService.createFile(report, format);
        if (!mounted) return;
        await SharePlus.instance.share(
          ShareParams(
            files: [file],
            subject: 'Carro das Delícias — ${report.title}',
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível exportar. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final count = report?.entries.length ?? 0;
    final pages = (count / AdminReportData.pageSize).ceil().clamp(1, 100000);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
              color: Colors.black,
              child: Row(
                children: [
                  const Icon(Icons.assessment_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Relatórios',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _exporting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<AdminReportScope>(
                initialValue: _scope,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conteúdo',
                  border: OutlineInputBorder(),
                ),
                items: AdminReportScope.values
                    .map(
                      (scope) => DropdownMenuItem(
                        value: scope,
                        child: Text(scope.label),
                      ),
                    )
                    .toList(),
                onChanged: _exporting
                    ? null
                    : (scope) {
                        if (scope != null) {
                          setState(() => _scope = scope);
                          unawaited(_load());
                        }
                      },
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '$count registros • ${report?.generatedLabel ?? ''}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: count == 0
                    ? const Padding(
                        padding: EdgeInsets.all(30),
                        child: Text(
                          'Nenhum registro encontrado.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: report!.entries
                            .skip(_page * AdminReportData.pageSize)
                            .take(AdminReportData.pageSize)
                            .length,
                        separatorBuilder: (_, _) => const Divider(height: 24),
                        itemBuilder: (_, index) {
                          final entry =
                              report.entries[_page * AdminReportData.pageSize +
                                  index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                entry.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...entry.lines.map(
                                (line) => SelectableText(
                                  line,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Página anterior',
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Página ${_page + 1} de $pages'),
                  IconButton(
                    tooltip: 'Próxima página',
                    onPressed: _page + 1 < pages
                        ? () => setState(() => _page++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (_exporting) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _exporting
                          ? null
                          : () => _export(AdminReportFormat.text),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar texto'),
                    ),
                    FilledButton.icon(
                      onPressed: _exporting
                          ? null
                          : () => _export(AdminReportFormat.pdf),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                    FilledButton.icon(
                      onPressed: _exporting
                          ? null
                          : () => _export(AdminReportFormat.docx),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('DOCX'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

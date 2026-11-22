import 'package:flutter/material.dart';
import '../services/admin_report_service.dart';

class ReportExportActions extends StatelessWidget {
  const ReportExportActions({
    super.key,
    required this.onExport,
    this.enabled = true,
  });
  final ValueChanged<AdminReportFormat> onExport;
  final bool enabled;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, format) in AdminReportFormat.values.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: enabled ? () => onExport(format) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                minimumSize: const Size(0, 76),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(switch (format) {
                    AdminReportFormat.text => Icons.copy,
                    AdminReportFormat.pdf => Icons.picture_as_pdf,
                    AdminReportFormat.docx => Icons.description_outlined,
                  }, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    switch (format) {
                      AdminReportFormat.text => 'Copiar texto',
                      AdminReportFormat.pdf => 'PDF',
                      AdminReportFormat.docx => 'DOCX',
                    },
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

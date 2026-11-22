import 'package:flutter/material.dart';

class DeliveryDateActions extends StatelessWidget {
  const DeliveryDateActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
  });
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Expanded(
        child: TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icons/menu/cancel_button.png',
                width: 18,
                height: 18,
              ),
              const SizedBox(width: 6),
              const Flexible(
                child: Text('Cancelar', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: ElevatedButton(
          onPressed: onConfirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check, size: 18),
              SizedBox(width: 6),
              Flexible(child: Text('Confirmar', textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    ],
  );
}

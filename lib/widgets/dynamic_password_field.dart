import 'package:flutter/material.dart';

/// Campo de senha dinâmico que evita problemas de GlobalKey duplicada
class DynamicPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final String? Function(String?)? validator;
  final String uniqueId;

  const DynamicPasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.hintText,
    required this.uniqueId,
    this.validator,
  });

  @override
  State<DynamicPasswordField> createState() => _DynamicPasswordFieldState();
}

class _DynamicPasswordFieldState extends State<DynamicPasswordField> {
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('password_field_${widget.uniqueId}'),
      controller: widget.controller,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          key: ValueKey('password_visibility_${widget.uniqueId}'),
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
      ),
      validator: widget.validator,
    );
  }
}

import 'package:flutter/material.dart';

/// Gerenciador de estados de carregamento para widgets específicos
class LoadingManager extends ChangeNotifier {
  final Map<String, bool> _loadingStates = {};

  /// Verifica se um componente específico está carregando
  bool isLoading(String key) {
    return _loadingStates[key] ?? false;
  }

  /// Define o estado de carregamento para um componente específico
  void setLoading(String key, bool isLoading) {
    if (_loadingStates[key] != isLoading) {
      _loadingStates[key] = isLoading;
      notifyListeners();
    }
  }

  /// Remove o estado de carregamento de um componente
  void removeLoading(String key) {
    if (_loadingStates.containsKey(key)) {
      _loadingStates.remove(key);
      notifyListeners();
    }
  }

  /// Limpa todos os estados de carregamento
  void clearAll() {
    if (_loadingStates.isNotEmpty) {
      _loadingStates.clear();
      notifyListeners();
    }
  }

  /// Verifica se existe algum carregamento ativo
  bool get hasAnyLoading {
    return _loadingStates.values.any((loading) => loading);
  }

  /// Retorna todas as keys que estão carregando
  List<String> get loadingKeys {
    return _loadingStates.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }
}

/// Widget builder que escuta mudanças de carregamento específicas
class LoadingBuilder extends StatelessWidget {
  final LoadingManager loadingManager;
  final String loadingKey;
  final Widget Function(BuildContext context, bool isLoading) builder;

  const LoadingBuilder({
    super.key,
    required this.loadingManager,
    required this.loadingKey,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: loadingManager,
      builder: (context, child) {
        return builder(context, loadingManager.isLoading(loadingKey));
      },
    );
  }
}

/// Widget que mostra um indicador de carregamento sobreposto
class LoadingOverlay extends StatelessWidget {
  final LoadingManager loadingManager;
  final String loadingKey;
  final Widget child;
  final String? loadingText;
  final Color? overlayColor;

  const LoadingOverlay({
    super.key,
    required this.loadingManager,
    required this.loadingKey,
    required this.child,
    this.loadingText,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingBuilder(
      loadingManager: loadingManager,
      loadingKey: loadingKey,
      builder: (context, isLoading) {
        return Stack(
          children: [
            child,
            if (isLoading)
              Container(
                color: overlayColor ?? Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      if (loadingText != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          loadingText!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Botão que mostra seu próprio estado de carregamento
class DynamicLoadingButton extends StatelessWidget {
  final LoadingManager loadingManager;
  final String loadingKey;
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;

  const DynamicLoadingButton({
    super.key,
    required this.loadingManager,
    required this.loadingKey,
    required this.text,
    this.onPressed,
    this.icon,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingBuilder(
      loadingManager: loadingManager,
      loadingKey: loadingKey,
      builder: (context, isLoading) {
        return SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: backgroundColor ?? Colors.black,
              foregroundColor: textColor ?? Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

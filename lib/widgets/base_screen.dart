import 'package:flutter/material.dart';

/// Widget base para todas as telas do app
/// Inclui estilização padrão, animação de entrada e transição suave
class BaseScreen extends StatelessWidget {
  final String? title;
  final Widget child;
  final bool showAppBar;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool centerTitle;
  final bool useSafeArea;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  const BaseScreen({
    super.key,
    required this.child,
    this.title,
    this.showAppBar = true,
    this.showBackButton = true,
    this.onBackPressed,
    this.actions,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.centerTitle = true,
    this.useSafeArea = true,
    this.backgroundColor,
    this.padding,
  });

  /// Função utilitária para navegação com transição suave
  static Future<dynamic> push(BuildContext context, Widget page) {
    return Navigator.of(context).push(_createRoute(page));
  }

  /// Função utilitária para substituir tela com transição suave
  static Future<dynamic> pushReplacement(BuildContext context, Widget page) {
    return Navigator.of(context).pushReplacement(_createRoute(page));
  }

  /// Cria uma rota com animação de fade
  static PageRouteBuilder _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: Padding(
        key: ValueKey('${child.runtimeType}_${child.hashCode}_$hashCode'),
        padding:
            padding ??
            const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: child,
      ),
    );

    return Scaffold(
      backgroundColor: backgroundColor ?? Colors.white,
      appBar: showAppBar && title != null
          ? PreferredSize(
              preferredSize: const Size.fromHeight(
                48,
              ), // Diminuída de kToolbarHeight (56) para 48
              child: Container(
                decoration: const BoxDecoration(color: Colors.black),
                child: SafeArea(
                  child: Container(
                    height: 48, // Altura reduzida
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Stack(
                      children: [
                        // Lado esquerdo - Sino de notificações ou Botão de voltar
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Botão de voltar (se necessário)
                              if (showBackButton &&
                                  (Navigator.of(context).canPop() ||
                                      onBackPressed != null))
                                IconButton(
                                  icon: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                  ),
                                  onPressed:
                                      onBackPressed ??
                                      () => Navigator.of(context).pop(),
                                ),
                            ],
                          ),
                        ),

                        // Título perfeitamente centralizado
                        Center(
                          child: Text(
                            title!,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                          ),
                        ),

                        // Actions do lado direito
                        if (actions != null && actions!.isNotEmpty)
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions!,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: useSafeArea ? SafeArea(child: content) : content,
    );
  }
}

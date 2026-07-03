import 'package:flutter/material.dart';

/// Localização customizada para o FloatingActionButton
/// Posiciona o botão acima da navbar de forma responsiva
class CustomFabLocation extends FloatingActionButtonLocation {
  const CustomFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    // Calcula o padding inferior do dispositivo (notch, barra de navegação, etc)
    final bottomPadding = scaffoldGeometry.minInsets.bottom;

    // Altura da navbar compacta + margem visual acima dela + padding do dispositivo.
    final bottomOffset = 60.0 + 50.0 + bottomPadding;

    // Posiciona no canto direito
    final double fabX =
        scaffoldGeometry.scaffoldSize.width -
        scaffoldGeometry.floatingActionButtonSize.width -
        16.0;

    // Posiciona acima da navbar considerando o padding do dispositivo
    final double fabY =
        scaffoldGeometry.scaffoldSize.height -
        scaffoldGeometry.floatingActionButtonSize.height -
        bottomOffset;

    return Offset(fabX, fabY);
  }
}

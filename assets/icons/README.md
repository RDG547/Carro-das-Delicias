# Ícones do App

Esta pasta é para armazenar ícones personalizados usados no app.

## Como adicionar seu ícone PNG:

1. **Adicione o ícone nesta pasta** (`assets/icons/`)
   - Exemplo: `kombi_icon.png`

2. **Para usar o ícone no código Flutter:**
   ```dart
   Image.asset('assets/icons/seu_icone.png', width: 24, height: 24)
   ```

3. **Para usar como marcador no mapa Mapbox:**
   - O ícone precisa ser carregado no estilo do mapa
   - Exemplo no código:
   ```dart
   // Carregar a imagem
   final ByteData bytes = await rootBundle.load('assets/icons/seu_icone.png');
   final Uint8List list = bytes.buffer.asUint8List();
   await mapboxMap?.style.addImage('custom-marker', list);

   // Usar no marcador
   PointAnnotationOptions(
     geometry: point,
     iconImage: 'custom-marker',
     iconSize: 1.0,
   )
   ```

## Recomendações de tamanho:

- **Ícones pequenos** (botões, UI): 24x24, 48x48, 72x72 px
- **Marcadores de mapa**: 64x64, 128x128 px
- **Logos**: 512x512 px ou maior

## Formato:
- PNG com fundo transparente é recomendado
- Para melhor qualidade, use imagens @2x e @3x (ex: `icon.png`, `icon@2x.png`, `icon@3x.png`)

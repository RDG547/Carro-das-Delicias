# Imagens do App

Esta pasta é para armazenar imagens gerais usadas no app (fotos, ilustrações, etc.).

## Como usar:

1. **Adicione suas imagens aqui** (`assets/images/`)
   - Exemplo: `logo.png`, `banner.jpg`, `produto.png`

2. **Para usar no código Flutter:**
   ```dart
   Image.asset('assets/images/sua_imagem.png')
   ```

3. **Com configurações adicionais:**
   ```dart
   Image.asset(
     'assets/images/sua_imagem.png',
     width: 200,
     height: 200,
     fit: BoxFit.cover,
   )
   ```

## Organização sugerida:

```
assets/images/
  ├── logos/          # Logos da marca
  ├── products/       # Imagens de produtos
  ├── banners/        # Banners promocionais
  └── backgrounds/    # Imagens de fundo
```

## Formatos suportados:
- PNG (recomendado para transparência)
- JPEG/JPG (recomendado para fotos)
- GIF (animações simples)
- WebP (melhor compressão)

## Dicas de otimização:
- Comprima imagens antes de adicionar ao projeto
- Use tamanhos apropriados (não adicione imagens 4K se só usa em 200px)
- Considere usar imagens @2x e @3x para diferentes densidades de tela

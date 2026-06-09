import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../services/catalog_sync_service.dart';
import '../services/image_service.dart';
import '../utils/flavor_icon_assets.dart';
import '../utils/product_variant_utils.dart';
import 'adaptive_dropdown_menu.dart';
import 'category_icon_widget.dart';
import 'flavor_icon_widget.dart';
import 'product_form_dialog_shell.dart';

// Formatter personalizado para entrada de preço
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Remove tudo que não é dígito
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Converte para centavos e depois para reais
    double value = double.parse(digitsOnly) / 100;

    // Formata como moeda brasileira
    String formatted = 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Dialog reutilizável para adicionar produtos
/// Combina o melhor dos formulários da home e do admin
class AddProductDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categorias;
  final VoidCallback onProductAdded;

  const AddProductDialog({
    super.key,
    required this.categorias,
    required this.onProductAdded,
  });

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _precoController = TextEditingController();
  final _precoAnteriorController = TextEditingController();
  final _precoComDescontoController = TextEditingController();
  final _valorDescontoController = TextEditingController();
  String? _selectedCategoryId;
  bool _isDisponivel = true;
  bool _isMaisVendido = false;
  bool _isNovidade = false;
  bool _isComDesconto = false;
  bool _hasMultipleSizes = false; // Nova opção para produtos com tamanhos
  bool _hasMultipleFlavors = false;

  // Listas de opções e imagens pendentes de upload.
  final List<Map<String, dynamic>> _sizes = [];
  final List<Map<String, dynamic>> _flavors = [];
  final List<Map<String, dynamic>> _productImages = [];
  List<String> _presetFlavorIcons = FlavorIconAssets.fallbackIcons;
  bool _isUploadingImages = false;
  int _nextFlavorKey = 0;

  @override
  void initState() {
    super.initState();
    _loadPresetFlavorIcons();
  }

  Future<void> _loadPresetFlavorIcons() async {
    final icons = await FlavorIconAssets.loadIcons();
    if (!mounted) return;
    setState(() {
      _presetFlavorIcons = icons;
    });
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _precoAnteriorController.dispose();
    _precoComDescontoController.dispose();
    _valorDescontoController.dispose();
    for (final size in _sizes) {
      size['nameController']?.dispose();
      size['precoController']?.dispose();
    }
    for (final flavor in _flavors) {
      flavor['nameController']?.dispose();
      flavor['iconController']?.dispose();
    }
    super.dispose();
  }

  void _addSize() {
    setState(() {
      _sizes.add({
        'nome': '',
        'preco': 0.0,
        'nameController': TextEditingController(),
        'precoController': TextEditingController(),
      });
    });
  }

  void _removeSize(int index) {
    setState(() {
      // Limpar controllers
      _sizes[index]['nameController']?.dispose();
      _sizes[index]['precoController']?.dispose();
      _sizes.removeAt(index);
    });
  }

  void _addFlavor() {
    setState(() {
      _flavors.add({
        'key': _nextFlavorKey++,
        'nameController': TextEditingController(),
        'iconController': TextEditingController(),
        'iconImage': null,
        'iconFile': null,
      });
    });
  }

  void _removeFlavor(int index) {
    setState(() {
      final flavorKey = _flavors[index]['key'];
      _flavors[index]['nameController']?.dispose();
      _flavors[index]['iconController']?.dispose();
      _flavors.removeAt(index);
      for (final image in _productImages) {
        if (image['flavorKey'] == flavorKey) {
          image['flavorKey'] = null;
        }
      }
    });
  }

  String? _flavorDisplayIcon(Map<String, dynamic> flavor) {
    final iconImage = flavor['iconImage']?.toString().trim();
    if (iconImage != null && iconImage.isNotEmpty) return iconImage;

    final iconController = flavor['iconController'] as TextEditingController?;
    final emoji = iconController?.text.trim();
    if (emoji != null && emoji.isNotEmpty) return emoji;

    return null;
  }

  Widget _buildFlavorIconPreview(Map<String, dynamic> flavor) {
    final iconFile = flavor['iconFile'] as File?;
    if (iconFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          iconFile,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    final icon = _flavorDisplayIcon(flavor);
    if (icon == null) {
      return Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(Icons.image_outlined, color: Colors.grey[500], size: 22),
      );
    }

    return FlavorIconWidget(icon: icon, size: 44, boxed: true);
  }

  Widget _buildPresetFlavorIconDropdown(
    int index,
    Map<String, dynamic> flavor,
  ) {
    final selectedIcon = flavor['iconImage']?.toString();

    return AdaptiveDropdownMenu<String>(
      items: _presetFlavorIcons,
      selectedItem: selectedIcon,
      itemHeight: 54,
      maxVisibleItems: 5,
      onSelected: (icon) {
        setState(() {
          _flavors[index]['iconImage'] = icon;
          _flavors[index]['iconFile'] = null;
        });
      },
      buttonBuilder: (context, isOpen) {
        final hasPreset = selectedIcon != null && selectedIcon.isNotEmpty;
        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal[200]!),
          ),
          child: Row(
            children: [
              if (hasPreset) ...[
                FlavorIconWidget(icon: selectedIcon, size: 28),
                const SizedBox(width: 8),
              ] else ...[
                Icon(Icons.image_search_outlined, color: Colors.teal[700]),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  hasPreset
                      ? FlavorIconAssets.labelFor(selectedIcon)
                      : 'Selecionar icone',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.teal[800],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                isOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: Colors.teal[700],
              ),
            ],
          ),
        );
      },
      itemBuilder: (context, icon, isSelected) {
        return Container(
          color: isSelected ? Colors.teal[50] : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FlavorIconWidget(icon: icon, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  FlavorIconAssets.labelFor(icon),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[900],
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, color: Colors.teal[700], size: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFlavorIcon(int index) async {
    final image = await ImageService.pickImageFromGallery();
    if (image == null || !mounted) return;

    setState(() {
      _flavors[index]['iconFile'] = image;
      _flavors[index]['iconImage'] = null;
    });
  }

  void _removeFlavorIcon(int index) {
    setState(() {
      _flavors[index]['iconFile'] = null;
      _flavors[index]['iconImage'] = null;
    });
  }

  Future<void> _uploadPendingFlavorIcons() async {
    if (!_hasMultipleFlavors || _flavors.isEmpty) return;

    for (var i = 0; i < _flavors.length; i++) {
      final iconFile = _flavors[i]['iconFile'] as File?;
      if (iconFile == null) continue;

      final fileName =
          'flavor_icon_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      final imageUrl = await ImageService.uploadImage(
        imageFile: iconFile,
        bucketName: 'produtos',
        fileName: fileName,
      );

      if (imageUrl != null) {
        _flavors[i]['iconImage'] = imageUrl;
        _flavors[i]['iconFile'] = null;
      }
    }
  }

  Future<void> _ensureInsertedFlavorPersistence(
    String nomeProduto,
    List<Map<String, dynamic>> expectedSabores, {
    Map<String, dynamic>? savedProduct,
  }) async {
    final client = Supabase.instance.client;
    Map<String, dynamic>? product = savedProduct;

    if (ProductVariantUtils.flavorOptionsMatch(
      product?['sabores'],
      expectedSabores,
    )) {
      return;
    }

    product ??= await client
        .from('produtos')
        .select('id, sabores')
        .eq('nome', nomeProduto)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();

    if (ProductVariantUtils.flavorOptionsMatch(
      product?['sabores'],
      expectedSabores,
    )) {
      return;
    }

    final productId = product?['id'];
    if (productId != null) {
      debugPrint(
        'Insert/RPC nao persistiu sabores; tentando update direto na coluna sabores.',
      );

      try {
        await client
            .from('produtos')
            .update(<String, dynamic>{'sabores': expectedSabores})
            .eq('id', productId);
      } catch (updateError) {
        debugPrint('Update direto de sabores falhou: $updateError');
      }
    }

    final verifiedProduct = await client
        .from('produtos')
        .select('sabores')
        .eq('nome', nomeProduto)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();

    if (!ProductVariantUtils.flavorOptionsMatch(
      verifiedProduct?['sabores'],
      expectedSabores,
    )) {
      throw Exception(
        'Os sabores nao foram salvos. Atualize a funcao insert_produto_admin no Supabase para gravar a coluna sabores.',
      );
    }
  }

  Future<void> _pickProductImages() async {
    final images = await ImageService.pickMultipleImagesFromGallery();
    if (images.isEmpty || !mounted) return;
    setState(() {
      _productImages.addAll(
        images.map((image) => {'file': image, 'flavorKey': null}),
      );
    });
  }

  Future<void> _takeProductPhoto() async {
    final image = await ImageService.pickImageFromCamera();
    if (image == null || !mounted) return;
    setState(() {
      _productImages.add({'file': image, 'flavorKey': null});
    });
  }

  Future<List<String>> _uploadPendingProductImages(
    Map<String, List<String>> flavorImagesByKey,
  ) async {
    if (_productImages.isEmpty) return const [];

    setState(() {
      _isUploadingImages = true;
    });

    final uploadedUrls = <String>[];
    try {
      for (var i = 0; i < _productImages.length; i++) {
        final imageFile = _productImages[i]['file'] as File;
        final fileName =
            'product_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final imageUrl = await ImageService.uploadImage(
          imageFile: imageFile,
          bucketName: 'produtos',
          fileName: fileName,
        );

        if (imageUrl == null) continue;

        uploadedUrls.add(imageUrl);
        final flavorKey = _productImages[i]['flavorKey'];
        if (flavorKey != null) {
          flavorImagesByKey.putIfAbsent(flavorKey.toString(), () => []);
          flavorImagesByKey[flavorKey.toString()]!.add(imageUrl);
        }
      }
      return uploadedUrls;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImages = false;
        });
      }
    }
  }

  Future<void> _addProduct() async {
    // Validações básicas
    if (_nomeController.text.trim().isEmpty || _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha os campos obrigatórios: Nome e Categoria'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validação específica para múltiplos tamanhos
    if (_hasMultipleSizes) {
      if (_sizes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adicione pelo menos um tamanho para o produto'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Validar que todos os tamanhos têm nome e preço
      for (var size in _sizes) {
        if (size['nome'] == null || size['nome'].toString().trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos os tamanhos devem ter um nome'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (size['preco'] == null || size['preco'] <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos os tamanhos devem ter um preço válido'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    } else {
      // Validação de preço baseado no modo desconto (apenas se não tem tamanhos)
      if (_isComDesconto) {
        if (_precoAnteriorController.text.trim().isEmpty ||
            _precoAnteriorController.text.trim() == 'R\$ 0,00' ||
            _precoComDescontoController.text.trim().isEmpty ||
            _precoComDescontoController.text.trim() == 'R\$ 0,00') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Preencha Preço Anterior e Preço com Desconto (maiores que R\$ 0,00)',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } else {
        if (_precoController.text.trim().isEmpty ||
            _precoController.text.trim() == 'R\$ 0,00') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preencha o Preço (maior que R\$ 0,00)'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    if (_hasMultipleFlavors) {
      if (_flavors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adicione pelo menos um sabor para o produto'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      for (final flavor in _flavors) {
        final nameController =
            flavor['nameController'] as TextEditingController;
        if (nameController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos os sabores devem ter um nome'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final nomeProduto = _nomeController.text.trim();

      // Verificar se já existe produto com o mesmo nome
      final existingProducts = await Supabase.instance.client
          .from('produtos')
          .select('id')
          .eq('nome', nomeProduto)
          .limit(1);

      if (existingProducts.isNotEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Já existe um produto com este nome!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Processar preços
      double? preco;
      double? precoAnterior;

      if (_hasMultipleSizes && _sizes.isNotEmpty) {
        // Se tem múltiplos tamanhos, usar o menor preço como referência
        preco = _sizes
            .map((size) => size['preco'] as double)
            .reduce((a, b) => a < b ? a : b);
        precoAnterior = null;
      } else if (_isComDesconto) {
        // Extrair preço com desconto
        final precoComDescontoText = _precoComDescontoController.text.trim();
        final precoComDescontoNumerico = precoComDescontoText
            .replaceAll('R\$ ', '')
            .replaceAll(',', '.');
        preco = double.parse(precoComDescontoNumerico);

        // Extrair preço anterior
        final precoAnteriorText = _precoAnteriorController.text.trim();
        final precoAnteriorNumerico = precoAnteriorText
            .replaceAll('R\$ ', '')
            .replaceAll(',', '.');
        precoAnterior = double.parse(precoAnteriorNumerico);

        // Validar que preço anterior é maior que preço com desconto
        if (precoAnterior <= preco) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'O Preço Anterior deve ser maior que o Preço com Desconto!',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } else {
        // Extrair preço normal
        final precoText = _precoController.text.trim();
        final precoNumerico = precoText
            .replaceAll('R\$ ', '')
            .replaceAll(',', '.');
        preco = double.parse(precoNumerico);
        precoAnterior = null;
      }

      final flavorImagesByKey = <String, List<String>>{};
      final uploadedImageUrls = await _uploadPendingProductImages(
        flavorImagesByKey,
      );
      await _uploadPendingFlavorIcons();
      final imagemUrl = uploadedImageUrls.isNotEmpty
          ? uploadedImageUrls.first
          : null;

      // Preparar tamanhos como JSON se houver
      List<Map<String, dynamic>>? tamanhos;
      if (_hasMultipleSizes && _sizes.isNotEmpty) {
        tamanhos = _sizes.map((size) {
          return {
            'nome': size['nome'].toString().trim(),
            'preco': size['preco'],
          };
        }).toList();
      }

      List<Map<String, dynamic>>? sabores;
      if (_hasMultipleFlavors && _flavors.isNotEmpty) {
        sabores = _flavors.map((flavor) {
          final nameController =
              flavor['nameController'] as TextEditingController;
          final emojiController =
              flavor['iconController'] as TextEditingController;
          final flavorKey = flavor['key'].toString();
          final imagens = flavorImagesByKey[flavorKey] ?? const <String>[];
          final emoji = emojiController.text.trim();
          final iconImage = flavor['iconImage']?.toString().trim();
          final icon = iconImage != null && iconImage.isNotEmpty
              ? iconImage
              : emoji;
          return {
            'nome': nameController.text.trim(),
            'icone': icon.isEmpty ? null : icon,
            'emoji': emoji.isEmpty ? null : emoji,
            'imagem_url': imagens.isNotEmpty ? imagens.first : null,
            'imagens': imagens,
          };
        }).toList();
      }

      final produtoData = <String, dynamic>{
        'nome': nomeProduto,
        'descricao': _descricaoController.text.trim().isEmpty
            ? null
            : _descricaoController.text.trim(),
        'preco': preco, // Menor preço quando tem múltiplos tamanhos
        'preco_anterior': precoAnterior,
        'categoria_id': int.parse(_selectedCategoryId!),
        'imagem_url': imagemUrl,
        'imagens': uploadedImageUrls.isNotEmpty ? uploadedImageUrls : null,
        'ativo': _isDisponivel,
        'mais_vendido': _isMaisVendido,
        'novidade': _isNovidade,
        'promocao':
            precoAnterior != null, // Automaticamente true se tem desconto
        'tamanhos': tamanhos, // Array JSON de tamanhos e preços
      };
      if (sabores != null) {
        produtoData['sabores'] = sabores;
      }

      Map<String, dynamic>? savedProduct;
      try {
        // Tentar insert direto primeiro
        savedProduct = await Supabase.instance.client
            .from('produtos')
            .insert(produtoData)
            .select('id, sabores')
            .maybeSingle();
      } catch (insertError) {
        debugPrint('Insert direto falhou: $insertError');
        // Fallback: tentar via RPC que bypassa RLS
        try {
          final rpcResult = await Supabase.instance.client.rpc(
            'insert_produto_admin',
            params: {'dados': produtoData},
          );
          if (rpcResult is Map) {
            savedProduct = Map<String, dynamic>.from(rpcResult);
          }
        } catch (rpcError) {
          debugPrint('RPC insert também falhou: $rpcError');
          rethrow;
        }
      }

      if (sabores != null) {
        await _ensureInsertedFlavorPersistence(
          nomeProduto,
          sabores,
          savedProduct: savedProduct,
        );
      }

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Produto adicionado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        CatalogSyncService.instance.notifyCatalogChanged();
        widget.onProductAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar produto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.sizeOf(context).width - 16)
        .clamp(304.0, 680.0)
        .toDouble();

    return ProductFormDialogShell(
      width: dialogWidth,
      title: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.green, Colors.teal],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.add_shopping_cart, color: Colors.white, size: 28),
            SizedBox(width: 12),
            Text(
              'Novo Produto',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome do produto
          Container(
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: TextField(
              controller: _nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome do Produto *',
                labelStyle: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(Icons.shopping_bag, color: Colors.green),
                hintText: 'Digite o nome do produto',
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Descrição
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: TextField(
              controller: _descricaoController,
              maxLines: 3,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                prefixIcon: Icon(Icons.description),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Campo de Preço (condicional baseado em desconto e tamanhos)
          // Não mostrar se tem múltiplos tamanhos ativado
          if (!_hasMultipleSizes && !_isComDesconto)
            Container(
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: TextField(
                controller: _precoController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Preço *',
                  labelStyle: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(
                    Icons.payments_outlined,
                    color: Colors.green,
                  ),
                  hintText: 'R\$ 0,00',
                  hintStyle: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.28),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),

          // Campos de Desconto (quando ativado e não tem múltiplos tamanhos)
          if (!_hasMultipleSizes && _isComDesconto) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: TextField(
                controller: _precoAnteriorController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Preço Anterior *',
                  labelStyle: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(Icons.money_off, color: Colors.orange),
                  hintText: 'R\$ 0,00',
                  hintStyle: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.28),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: TextField(
                controller: _precoComDescontoController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Preço com Desconto *',
                  labelStyle: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(
                    Icons.local_offer,
                    color: Colors.green,
                  ),
                  hintText: 'R\$ 0,00',
                  hintStyle: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.28),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Categoria
          Container(
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCategoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoria *',
                labelStyle: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(Icons.category, color: Colors.green),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
              items: widget.categorias.map((categoria) {
                return DropdownMenuItem<String>(
                  value: categoria['id'].toString(),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(
                          child: CategoryIconWidget(
                            icone: categoria['icone'] ?? '📦',
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(categoria['nome']),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategoryId = value;
                });
              },
            ),
          ),
          const SizedBox(height: 16),

          // Upload de Imagens
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Imagens do Produto',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _hasMultipleFlavors
                      ? 'A primeira imagem será a principal. Atribua fotos aos sabores aqui.'
                      : 'A primeira imagem será a principal.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),

                if (_productImages.isNotEmpty) ...[
                  ..._productImages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final imageData = entry.value;
                    final imageFile = imageData['file'] as File;
                    final selectedFlavorKey = imageData['flavorKey'] as int?;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: index == 0 ? Colors.green : Colors.grey[300]!,
                          width: index == 0 ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(7),
                            ),
                            child: SizedBox(
                              height: 120,
                              width: double.infinity,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(
                                    imageFile,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                  if (index == 0)
                                    Positioned(
                                      left: 8,
                                      top: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Text(
                                          'PRINCIPAL',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: IconButton.filled(
                                      onPressed: () {
                                        setState(() {
                                          _productImages.removeAt(index);
                                        });
                                      },
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_hasMultipleFlavors && _flavors.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: DropdownButtonFormField<int>(
                                key: ValueKey(
                                  'pending_image_${index}_${selectedFlavorKey ?? -1}_${_flavors.length}',
                                ),
                                initialValue: selectedFlavorKey ?? -1,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Foto vinculada ao sabor',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem<int>(
                                    value: -1,
                                    child: Text('Sem sabor específico'),
                                  ),
                                  ..._flavors.map((flavor) {
                                    final controller =
                                        flavor['nameController']
                                            as TextEditingController;
                                    final icon = _flavorDisplayIcon(flavor);
                                    final label = controller.text.trim().isEmpty
                                        ? 'Sabor ${_flavors.indexOf(flavor) + 1}'
                                        : controller.text.trim();
                                    return DropdownMenuItem<int>(
                                      value: flavor['key'] as int,
                                      child: Row(
                                        children: [
                                          if (icon != null) ...[
                                            FlavorIconWidget(
                                              icon: icon,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          Expanded(child: Text(label)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    imageData['flavorKey'] =
                                        value == null || value == -1
                                        ? null
                                        : value;
                                  });
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                ],

                if (_isUploadingImages)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final galleryButton = ElevatedButton.icon(
                        onPressed: _pickProductImages,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text(
                          _productImages.isEmpty
                              ? 'Adicionar Imagens'
                              : 'Adicionar Mais',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      );

                      final cameraButton = ElevatedButton.icon(
                        onPressed: _takeProductPhoto,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text(
                          'Tirar Foto',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      );

                      if (constraints.maxWidth < 340) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            galleryButton,
                            const SizedBox(height: 8),
                            cameraButton,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: galleryButton),
                          const SizedBox(width: 8),
                          Expanded(child: cameraButton),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Características (Switches)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[100]!),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _isDisponivel ? Icons.check_circle : Icons.cancel,
                      color: _isDisponivel ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Produto Disponível',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _isDisponivel,
                      activeThumbColor: Colors.green,
                      onChanged: (value) {
                        setState(() {
                          _isDisponivel = value;
                        });
                      },
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Icon(
                      _isMaisVendido ? Icons.star : Icons.star_border,
                      color: _isMaisVendido ? Colors.amber : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Mais Vendido',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _isMaisVendido,
                      activeThumbColor: Colors.amber,
                      onChanged: (value) {
                        setState(() {
                          _isMaisVendido = value;
                        });
                      },
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Icon(
                      _isNovidade ? Icons.fiber_new : Icons.fiber_new_outlined,
                      color: _isNovidade ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Novidade',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch(
                      value: _isNovidade,
                      activeThumbColor: Colors.orange,
                      onChanged: (value) {
                        setState(() {
                          _isNovidade = value;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Switch para Produto com Desconto
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[100]!),
            ),
            child: Row(
              children: [
                Icon(
                  _isComDesconto ? Icons.discount : Icons.discount_outlined,
                  color: _isComDesconto ? Colors.orange : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Produto com Desconto',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ative para definir preço anterior e preço com desconto',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isComDesconto,
                  activeThumbColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _isComDesconto = value;
                    });
                  },
                ),
              ],
            ),
          ),

          // Campo de Desconto (visível quando marcado como promoção)
          if (_isComDesconto) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _valorDescontoController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Valor do Desconto (em R\$)',
                      labelStyle: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                      hintText: _hasMultipleSizes
                          ? 'Ex: R\$ 5,00'
                          : 'Valor a ser deduzido do preço',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(
                        Icons.local_offer,
                        color: Colors.green,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  if (_hasMultipleSizes)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        '💡 Este valor será deduzido automaticamente de TODOS os preços',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Switch para Múltiplos Tamanhos
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple[100]!),
            ),
            child: Row(
              children: [
                Icon(
                  _hasMultipleSizes
                      ? Icons.format_size
                      : Icons.format_size_outlined,
                  color: _hasMultipleSizes ? Colors.purple : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Múltiplos Tamanhos',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ative para adicionar diferentes tamanhos com preços variados',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _hasMultipleSizes,
                  activeThumbColor: Colors.purple,
                  onChanged: (value) {
                    setState(() {
                      _hasMultipleSizes = value;
                      if (value && _sizes.isEmpty) {
                        // Adicionar um tamanho inicial
                        _addSize();
                      } else if (!value) {
                        // Limpar tamanhos se desativar
                        for (var size in _sizes) {
                          size['nameController']?.dispose();
                          size['precoController']?.dispose();
                        }
                        _sizes.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ),

          // Lista de tamanhos (se ativado)
          if (_hasMultipleSizes) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Tamanhos e Preços',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _addSize,
                        icon: Image.asset(
                          'assets/icons/menu/add_button.png',
                          width: 18,
                          height: 18,
                          color: Colors.white,
                        ),
                        label: const Text('Adicionar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_sizes.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Clique em "Adicionar" para criar tamanhos',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _sizes.length,
                      itemBuilder: (context, index) {
                        final size = _sizes[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: size['nameController'],
                                        decoration: InputDecoration(
                                          labelText: 'Tamanho *',
                                          hintText: 'Ex: P, M, G, 300ml',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                          isDense: true,
                                        ),
                                        onChanged: (value) {
                                          size['nome'] = value;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: size['precoController'],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          CurrencyInputFormatter(),
                                        ],
                                        decoration: InputDecoration(
                                          labelText: 'Preço *',
                                          hintText: 'R\$ 0,00',
                                          hintStyle: TextStyle(
                                            color: Colors.grey.withValues(
                                              alpha: 0.28,
                                            ),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                          isDense: true,
                                        ),
                                        onChanged: (value) {
                                          final precoText = value.trim();
                                          final precoNumerico = precoText
                                              .replaceAll('R\$ ', '')
                                              .replaceAll(',', '.');
                                          size['preco'] =
                                              double.tryParse(precoNumerico) ??
                                              0.0;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Image.asset(
                                        'assets/icons/menu/delete_button.png',
                                        width: 20,
                                        height: 20,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _removeSize(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Switch para Sabores
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.teal[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal[100]!),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: _hasMultipleFlavors ? Colors.teal : Colors.grey,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sabores',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Ative para agrupar sabores e fotos específicas',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _hasMultipleFlavors,
                  activeThumbColor: Colors.teal,
                  onChanged: (value) {
                    setState(() {
                      _hasMultipleFlavors = value;
                      if (value && _flavors.isEmpty) {
                        _addFlavor();
                      } else if (!value) {
                        for (final flavor in _flavors) {
                          flavor['nameController']?.dispose();
                          flavor['iconController']?.dispose();
                        }
                        _flavors.clear();
                        for (final image in _productImages) {
                          image['flavorKey'] = null;
                        }
                      }
                    });
                  },
                ),
              ],
            ),
          ),

          if (_hasMultipleFlavors) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sabores',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._flavors.asMap().entries.map((entry) {
                    final index = entry.key;
                    final flavor = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal[100]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildFlavorIconPreview(flavor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Sabor ${index + 1}',
                                  style: TextStyle(
                                    color: Colors.teal[800],
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Image.asset(
                                  'assets/icons/menu/delete_button.png',
                                  width: 20,
                                  height: 20,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeFlavor(index),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: flavor['iconController'],
                            textAlign: TextAlign.center,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Emoji',
                              hintText: '🍓',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: flavor['nameController'],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Sabor *',
                              hintText: 'Ex: Chocolate, Limão',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildPresetFlavorIconDropdown(index, flavor),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _pickFlavorIcon(index),
                              icon: const Icon(Icons.upload, size: 16),
                              label: const Text('Enviar icone'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.teal,
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                side: BorderSide(color: Colors.teal[200]!),
                              ),
                            ),
                          ),
                          if (flavor['iconImage'] != null ||
                              flavor['iconFile'] != null) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _removeFlavorIcon(index),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Remover icone'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: BorderSide(color: Colors.red[200]!),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'As fotos deste sabor são vinculadas na seção Imagens do Produto.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addFlavor,
                      icon: Image.asset(
                        'assets/icons/menu/add_button.png',
                        width: 18,
                        height: 18,
                        color: Colors.white,
                      ),
                      label: const Text('Adicionar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icons/menu/cancel_button.png',
                      width: 18,
                      height: 18,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _addProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icons/menu/add_button.png',
                      width: 18,
                      height: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Adicionar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog reutilizável para adicionar categorias
class AddCategoryDialog extends StatefulWidget {
  final VoidCallback onCategoryAdded;

  const AddCategoryDialog({super.key, required this.onCategoryAdded});

  @override
  State<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<AddCategoryDialog> {
  final _nomeController = TextEditingController();
  final _iconeController = TextEditingController();

  @override
  void dispose() {
    _nomeController.dispose();
    _iconeController.dispose();
    super.dispose();
  }

  Future<void> _addCategory() async {
    if (_nomeController.text.trim().isEmpty ||
        _iconeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha os campos obrigatórios: Nome e Ícone'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final nomeCategoria = _nomeController.text.trim();

      // Verificar se já existe categoria com o mesmo nome
      final existingCategories = await Supabase.instance.client
          .from('categorias')
          .select('id')
          .eq('nome', nomeCategoria)
          .limit(1);

      if (existingCategories.isNotEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Já existe uma categoria com este nome!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Obter o maior valor de ordem atual
      final maxOrdemResult = await Supabase.instance.client
          .from('categorias')
          .select('ordem')
          .order('ordem', ascending: false)
          .limit(1);

      final nextOrdem = maxOrdemResult.isEmpty
          ? 0
          : ((maxOrdemResult.first['ordem'] ?? -1) as int) + 1;

      try {
        // Tentar insert direto primeiro
        await Supabase.instance.client.from('categorias').insert({
          'nome': nomeCategoria,
          'icone': _iconeController.text.trim().isEmpty
              ? '📦'
              : _iconeController.text.trim(),
          'ativo': true,
          'ordem': nextOrdem,
        });
      } catch (insertError) {
        debugPrint('Insert direto falhou: $insertError');
        // Fallback: tentar via RPC que bypassa RLS
        try {
          await Supabase.instance.client.rpc(
            'insert_categoria_admin',
            params: {
              'dados': {
                'nome': nomeCategoria,
                'icone': _iconeController.text.trim().isEmpty
                    ? '📦'
                    : _iconeController.text.trim(),
                'ativo': true,
                'ordem': nextOrdem,
              },
            },
          );
        } catch (rpcError) {
          debugPrint('RPC insert também falhou: $rpcError');
          rethrow;
        }
      }

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Categoria adicionada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onCategoryAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao adicionar categoria: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.blue, Colors.indigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.add, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Nova Categoria',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        child: SingleChildScrollView(
          child: RepaintBoundary(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome da categoria
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: TextField(
                    controller: _nomeController,
                    decoration: InputDecoration(
                      labelText: 'Nome da Categoria *',
                      labelStyle: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Padding(
                        padding: EdgeInsets.all(12),
                        child: Image.asset(
                          'assets/icons/menu/add_category.png',
                          width: 24,
                          height: 24,
                        ),
                      ),
                      hintText: 'Digite o nome da categoria',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                      helperText: 'Obrigatório',
                      helperStyle: TextStyle(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Ícone
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: TextField(
                    controller: _iconeController,
                    decoration: const InputDecoration(
                      labelText: 'Ícone *',
                      labelStyle: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Icon(
                        Icons.emoji_emotions,
                        color: Colors.blue,
                      ),
                      hintText: '🍰 ou asset:assets/icons/icone.svg',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                      helperText: 'Emoji ou caminho do asset',
                      helperStyle: TextStyle(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icons/menu/cancel_button.png',
                        width: 18,
                        height: 18,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Cancelar',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _addCategory,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icons/menu/add_button.png',
                        width: 18,
                        height: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Adicionar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

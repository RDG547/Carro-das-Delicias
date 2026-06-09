import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/catalog_sync_service.dart';
import '../services/image_service.dart';
import '../utils/flavor_icon_assets.dart';
import '../utils/product_variant_utils.dart';
import 'adaptive_dropdown_menu.dart';
import 'form_dialogs.dart'; // Para usar CurrencyInputFormatter
import 'category_icon_widget.dart';
import 'flavor_icon_widget.dart';
import 'product_form_dialog_shell.dart';

class EditProductDialog extends StatefulWidget {
  final Map<String, dynamic> produto;
  final List<Map<String, dynamic>> categorias;
  final VoidCallback onProductUpdated;

  const EditProductDialog({
    super.key,
    required this.produto,
    required this.categorias,
    required this.onProductUpdated,
  });

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  late TextEditingController _nomeController;
  late TextEditingController _descricaoController;
  late TextEditingController _precoController;
  late TextEditingController _valorDescontoController;

  String? _selectedCategoryId;
  bool _isDisponivel = true;
  bool _isMaisVendido = false;
  bool _isNovidade = false;
  bool _isPromocao = false;
  bool _hasMultipleSizes = false;
  bool _hasMultipleFlavors = false;

  // Lista de tamanhos
  final List<Map<String, dynamic>> _sizes = [];
  final List<Map<String, dynamic>> _flavors = [];
  String? _currentImageUrl;

  // Lista de imagens do produto (suporte a múltiplas imagens)
  List<String> _productImages = [];
  final Map<String, int> _imageFlavorAssignments = {};
  List<String> _presetFlavorIcons = FlavorIconAssets.fallbackIcons;
  bool _isUploadingImages = false;
  int _nextFlavorKey = 0;

  String _formatCurrencyText(dynamic value) {
    final numericValue = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (numericValue == null || numericValue <= 0) {
      return '';
    }
    return 'R\$ ${numericValue.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  void initState() {
    super.initState();
    _loadPresetFlavorIcons();

    // DEBUG: Imprimir estrutura completa do produto
    debugPrint('🔍 PRODUTO COMPLETO: ${widget.produto}');
    debugPrint('🔍 Keys do produto: ${widget.produto.keys.toList()}');

    // Inicializar controladores com dados do produto
    _nomeController = TextEditingController(text: widget.produto['nome'] ?? '');
    _descricaoController = TextEditingController(
      text: widget.produto['descricao'] ?? '',
    );

    _selectedCategoryId = widget.produto['categoria_id']?.toString();
    _isDisponivel = widget.produto['ativo'] ?? true;
    _isMaisVendido = widget.produto['mais_vendido'] ?? false;
    _isNovidade = widget.produto['novidade'] ?? false;
    _isPromocao = widget.produto['promocao'] ?? false;
    _currentImageUrl = widget.produto['imagem_url'];

    // Inicializar lista de imagens
    final imagensData = widget.produto['imagens'];
    if (imagensData != null && imagensData is List && imagensData.isNotEmpty) {
      _productImages = List<String>.from(imagensData);
    } else if (_currentImageUrl != null && _currentImageUrl!.isNotEmpty) {
      // Se só tem imagem_url antiga, adiciona na lista
      _productImages = [_currentImageUrl!];
    }

    // Inicializar valor de desconto
    final valorDesconto = widget.produto['valor_desconto'];
    final precoAnterior = widget.produto['preco_anterior'];

    debugPrint('📦 Produto inicial: ${widget.produto['nome']}');
    debugPrint('💰 Preço: ${widget.produto['preco']}');
    debugPrint('💰 Preço anterior: $precoAnterior');
    debugPrint('🎁 Valor desconto: $valorDesconto');
    debugPrint('🏷️ Promoção: ${widget.produto['promocao']}');

    _valorDescontoController = TextEditingController(
      text: valorDesconto != null && valorDesconto > 0
          ? valorDesconto.toString()
          : '',
    );

    // Inicializar preço formatado como R$ X,XX
    final precoRaw = widget.produto['preco'];
    if (precoRaw != null) {
      _precoController = TextEditingController(
        text: _formatCurrencyText(precoRaw),
      );
    } else {
      _precoController = TextEditingController();
    }

    // Verificar se tem múltiplos tamanhos
    final tamanhos = widget.produto['tamanhos'];
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      _hasMultipleSizes = true;
      for (var tamanho in tamanhos) {
        _sizes.add({
          'nameController': TextEditingController(text: tamanho['nome'] ?? ''),
          'precoController': TextEditingController(
            text: _formatCurrencyText(tamanho['preco']),
          ),
        });
      }
    }

    final sabores = ProductVariantUtils.extractFlavors(
      widget.produto['sabores'],
    );
    if (sabores.isNotEmpty) {
      _hasMultipleFlavors = true;
      for (final sabor in sabores) {
        final flavorKey = _nextFlavorKey++;
        final imagens = ProductVariantUtils.optionImages(sabor);
        _flavors.add({
          'key': flavorKey,
          'nameController': TextEditingController(
            text: ProductVariantUtils.optionName(sabor) ?? '',
          ),
          'iconController': TextEditingController(
            text: ProductVariantUtils.optionEmoji(sabor) ?? '',
          ),
          'iconImage': ProductVariantUtils.optionImageIcon(sabor),
          'iconFile': null,
        });
        for (final imagem in imagens) {
          if (!_productImages.contains(imagem)) {
            _productImages.add(imagem);
          }
          _imageFlavorAssignments[imagem] = flavorKey;
        }
      }
    }
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

  // Função helper para converter valores formatados (R$ 10,00) para double
  double _parseFormattedPrice(String formattedPrice) {
    // Remove "R$ ", espaços e substitui vírgula por ponto
    String cleaned = formattedPrice
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    return double.parse(cleaned);
  }

  void _addSize() {
    setState(() {
      _sizes.add({
        'nameController': TextEditingController(),
        'precoController': TextEditingController(),
      });
    });
  }

  void _removeSize(int index) {
    setState(() {
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
      final flavorKey = _flavors[index]['key'] as int;
      _flavors[index]['nameController']?.dispose();
      _flavors[index]['iconController']?.dispose();
      _flavors.removeAt(index);
      _imageFlavorAssignments.removeWhere((_, value) => value == flavorKey);
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

  Set<String> _currentUploadedFlavorIconUrls() {
    return ProductVariantUtils.extractFlavors(widget.produto['sabores'])
        .map(ProductVariantUtils.optionImageIcon)
        .whereType<String>()
        .where((icon) => icon.startsWith('http'))
        .toSet();
  }

  Future<void> _uploadPendingFlavorIcons() async {
    if (!_hasMultipleFlavors || _flavors.isEmpty) return;

    for (var i = 0; i < _flavors.length; i++) {
      final iconFile = _flavors[i]['iconFile'] as File?;
      if (iconFile == null) continue;

      final fileName =
          'flavor_icon_${widget.produto['id']}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
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

  Future<void> _deleteUnusedUploadedFlavorIcons(
    Set<String> previousIconUrls,
    List<Map<String, dynamic>>? savedFlavors,
  ) async {
    final currentIconUrls = (savedFlavors ?? const <Map<String, dynamic>>[])
        .map(ProductVariantUtils.optionImageIcon)
        .whereType<String>()
        .where((icon) => icon.startsWith('http'))
        .toSet();

    for (final oldUrl in previousIconUrls.difference(currentIconUrls)) {
      await ImageService.deleteProductImage(oldUrl);
    }
  }

  Widget _buildFeatureCheckbox({
    required String title,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool?> onChanged,
  }) {
    return Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        title: Text(title),
        value: value,
        activeColor: activeColor,
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _ensureFlavorPersistence(
    dynamic produtoId,
    List<Map<String, dynamic>>? expectedSabores,
  ) async {
    final client = Supabase.instance.client;
    final currentProduct = await client
        .from('produtos')
        .select('sabores')
        .eq('id', produtoId)
        .maybeSingle();

    if (ProductVariantUtils.flavorOptionsMatch(
      currentProduct?['sabores'],
      expectedSabores,
    )) {
      return;
    }

    debugPrint(
      'RPC nao persistiu sabores; tentando update direto na coluna sabores.',
    );

    try {
      await client
          .from('produtos')
          .update(<String, dynamic>{
            'sabores': expectedSabores,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', produtoId);
    } catch (updateError) {
      debugPrint('Update direto de sabores falhou: $updateError');
    }

    final verifiedProduct = await client
        .from('produtos')
        .select('sabores')
        .eq('id', produtoId)
        .maybeSingle();

    if (!ProductVariantUtils.flavorOptionsMatch(
      verifiedProduct?['sabores'],
      expectedSabores,
    )) {
      throw Exception(
        'Os sabores nao foram salvos. Atualize a funcao update_produto_admin no Supabase para gravar a coluna sabores.',
      );
    }
  }

  Future<void> _updateProduct() async {
    debugPrint('🚀 _updateProduct chamado!');

    // Validações
    if (_nomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nome do produto é obrigatório'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione uma categoria'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validação de preço baseado no modo
    if (!_hasMultipleSizes) {
      if (_precoController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preço é obrigatório'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Validar desconto se estiver marcado como promoção
      if (_isPromocao && _valorDescontoController.text.trim().isNotEmpty) {
        final desconto = _parseFormattedPrice(
          _valorDescontoController.text.trim(),
        );
        final preco = _parseFormattedPrice(_precoController.text.trim());
        if (desconto >= preco) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('O desconto deve ser menor que o preço'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    } else {
      // Validar tamanhos
      if (_sizes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adicione pelo menos um tamanho'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      for (var size in _sizes) {
        if (size['nameController'].text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos os tamanhos devem ter um nome'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (size['precoController'].text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Todos os tamanhos devem ter um preço'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // Validar desconto para múltiplos tamanhos
      if (_isPromocao && _valorDescontoController.text.trim().isNotEmpty) {
        final desconto = _parseFormattedPrice(
          _valorDescontoController.text.trim(),
        );
        for (var size in _sizes) {
          final preco = _parseFormattedPrice(
            size['precoController'].text.trim(),
          );
          if (desconto >= preco) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'O desconto (R\$ ${desconto.toStringAsFixed(2)}) deve ser menor que todos os preços',
                ),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }
        }
      }
    }

    if (_hasMultipleFlavors) {
      if (_flavors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adicione pelo menos um sabor'),
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

    try {
      final previousFlavorIconUrls = _currentUploadedFlavorIconUrls();
      await _uploadPendingFlavorIcons();

      double preco;
      double? precoAnterior;
      double? valorDesconto;
      List<Map<String, dynamic>>? tamanhos;
      List<Map<String, dynamic>>? tamanhosOriginais;

      // Processar desconto
      if (_isPromocao && _valorDescontoController.text.trim().isNotEmpty) {
        valorDesconto = _parseFormattedPrice(
          _valorDescontoController.text.trim(),
        );
        // Se o valor do desconto for 0, considerar como sem desconto
        if (valorDesconto <= 0) {
          valorDesconto = null;
        }
      } else {
        valorDesconto = null;
      }

      if (_hasMultipleSizes) {
        // Com múltiplos tamanhos - salvar preços originais e com desconto
        tamanhosOriginais = _sizes.map((size) {
          double precoOriginal = _parseFormattedPrice(
            size['precoController'].text.trim(),
          );
          return {
            'nome': size['nameController'].text.trim(),
            'preco': precoOriginal,
          };
        }).toList();

        tamanhos = _sizes.map((size) {
          double precoOriginal = _parseFormattedPrice(
            size['precoController'].text.trim(),
          );
          // Aplicar o desconto ao preço do tamanho
          double precoFinal = precoOriginal;
          if (valorDesconto != null && valorDesconto > 0) {
            precoFinal = precoOriginal - valorDesconto;
            // Garantir que o preço final não seja negativo
            if (precoFinal < 0) precoFinal = 0;
          }
          return {
            'nome': size['nameController'].text.trim(),
            'preco': precoFinal, // Salva o preço já com desconto aplicado
          };
        }).toList();

        // Usar o menor preço como referência
        preco = tamanhos
            .map((t) => t['preco'] as double)
            .reduce((a, b) => a < b ? a : b);

        // Para múltiplos tamanhos com desconto, salvar o menor preço original como referência
        if (valorDesconto != null && valorDesconto > 0) {
          precoAnterior = tamanhosOriginais
              .map((t) => t['preco'] as double)
              .reduce((a, b) => a < b ? a : b);
        } else {
          precoAnterior = null;
        }
      } else {
        // Preço simples
        double precoOriginal = _parseFormattedPrice(
          _precoController.text.trim(),
        );

        if (valorDesconto != null && valorDesconto > 0) {
          precoAnterior = precoOriginal;
          preco = precoOriginal - valorDesconto;
          if (preco < 0) preco = 0;
        } else {
          preco = precoOriginal;
          precoAnterior = null;
        }
      }

      List<Map<String, dynamic>>? sabores;
      if (_hasMultipleFlavors && _flavors.isNotEmpty) {
        sabores = _flavors.map((flavor) {
          final nameController =
              flavor['nameController'] as TextEditingController;
          final emojiController =
              flavor['iconController'] as TextEditingController;
          final flavorKey = flavor['key'] as int;
          final imagens = _productImages
              .where(
                (imageUrl) => _imageFlavorAssignments[imageUrl] == flavorKey,
              )
              .toList();
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

      final updateData = {
        'nome': _nomeController.text.trim(),
        'descricao': _descricaoController.text.trim().isEmpty
            ? null
            : _descricaoController.text.trim(),
        'preco': preco,
        'preco_anterior': precoAnterior,
        'valor_desconto': valorDesconto,
        'categoria_id': int.parse(_selectedCategoryId!),
        'imagem_url': _productImages.isNotEmpty
            ? _productImages.first
            : null, // Primeira imagem como principal
        'imagens': _productImages.isNotEmpty
            ? _productImages
            : null, // Todas as imagens
        'ativo': _isDisponivel,
        'mais_vendido': _isMaisVendido,
        'novidade': _isNovidade,
        'promocao': _isPromocao && valorDesconto != null && valorDesconto > 0,
        'tamanhos': tamanhos,
        if (widget.produto.containsKey('sabores') || sabores != null)
          'sabores': sabores,
        'updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint('Atualizando produto ${widget.produto['id']}');
      debugPrint('Tipo do ID: ${widget.produto['id'].runtimeType}');
      debugPrint('Dados: $updateData');

      // Verificar se o produto existe
      final checkExists = await Supabase.instance.client
          .from('produtos')
          .select('id, nome, preco, preco_anterior, ativo')
          .eq('id', widget.produto['id'])
          .maybeSingle();

      debugPrint('Produto existe? $checkExists');

      if (checkExists == null) {
        throw Exception('Produto ID ${widget.produto['id']} nao existe!');
      }

      // Testar update simples primeiro
      debugPrint('Testando update simples...');

      try {
        // Tentar chamar função RPC que bypassa RLS
        final rpcResult = await Supabase.instance.client.rpc(
          'update_produto_admin',
          params: {'produto_id': widget.produto['id'], 'dados': updateData},
        );
        debugPrint('RPC result: $rpcResult');

        if (updateData.containsKey('sabores')) {
          await _ensureFlavorPersistence(widget.produto['id'], sabores);
        }
        await _deleteUnusedUploadedFlavorIcons(previousFlavorIconUrls, sabores);

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Produto atualizado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
          CatalogSyncService.instance.notifyCatalogChanged();
          widget.onProductUpdated();
        }
        return;
      } catch (rpcError) {
        debugPrint('RPC falhou: $rpcError');
        // Continuar com update normal
      }

      final testUpdate = await Supabase.instance.client
          .from('produtos')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', widget.produto['id'])
          .select();

      debugPrint('Test update result: $testUpdate');

      // Se funcionar, tentar update completo
      final response = await Supabase.instance.client
          .from('produtos')
          .update(updateData)
          .eq('id', widget.produto['id'])
          .select();

      debugPrint('Resposta: $response');
      debugPrint('Qtd: ${response.length}');

      if (response.isEmpty) {
        throw Exception(
          'Produto não encontrado no banco de dados (ID: ${widget.produto['id']})',
        );
      }

      if (updateData.containsKey('sabores') &&
          !ProductVariantUtils.flavorOptionsMatch(
            response.first['sabores'],
            sabores,
          )) {
        await _ensureFlavorPersistence(widget.produto['id'], sabores);
      }
      await _deleteUnusedUploadedFlavorIcons(previousFlavorIconUrls, sabores);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        CatalogSyncService.instance.notifyCatalogChanged();
        widget.onProductUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar produto: $e'),
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
            colors: [Colors.blue, Colors.indigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.edit, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Editar ${widget.produto['nome']}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nome
          Container(
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: TextField(
              controller: _nomeController,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Nome do Produto *',
                labelStyle: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(Icons.shopping_bag, color: Colors.blue),
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

          // Campo de Preço (sempre visível se não tem tamanhos)
          if (!_hasMultipleSizes)
            Container(
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: TextField(
                controller: _precoController,
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Preço *',
                  labelStyle: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                  prefixIcon: const Icon(
                    Icons.payments_outlined,
                    color: Colors.blue,
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
          const SizedBox(height: 16),

          // Categoria
          Container(
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedCategoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Categoria *',
                labelStyle: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(Icons.category, color: Colors.blue),
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
                            categoryName: categoria['nome'],
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

          // Upload de Imagens (Múltiplas)
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
                Row(
                  children: [
                    const Text(
                      'Imagens do Produto',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_productImages.isNotEmpty)
                      Text(
                        '${_productImages.length} ${_productImages.length == 1 ? "imagem" : "imagens"}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _hasMultipleFlavors
                      ? 'Arraste para reordenar. A primeira imagem será a principal. Atribua fotos aos sabores aqui.'
                      : 'Arraste para reordenar. A primeira imagem será a principal.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),

                // Grid de imagens com reordenação
                if (_productImages.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _productImages.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _productImages.removeAt(oldIndex);
                        _productImages.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final imageUrl = _productImages[index];
                      return Container(
                        key: ValueKey(imageUrl),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: index == 0 ? Colors.blue : Colors.grey[300]!,
                            width: index == 0 ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                // Imagem
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(7),
                                  ),
                                  child: Row(
                                    children: [
                                      // Handle para arrastar
                                      Container(
                                        width: 40,
                                        height: 120,
                                        color: Colors.grey[100],
                                        child: const Icon(
                                          Icons.drag_indicator,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      // Imagem
                                      Expanded(
                                        child: Image.network(
                                          imageUrl,
                                          height: 120,
                                          fit: BoxFit.cover,
                                          cacheWidth: 240,
                                          cacheHeight: 240,
                                          filterQuality: FilterQuality.medium,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  height: 120,
                                                  color: Colors.grey[200],
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.error,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                );
                                              },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Badge "Principal"
                                if (index == 0)
                                  Positioned(
                                    top: 8,
                                    left: 48,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(4),
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

                                // Botão deletar
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: InkWell(
                                    onTap: () async {
                                      final scaffoldMessenger =
                                          ScaffoldMessenger.of(context);

                                      // Deletar do storage
                                      await ImageService.deleteProductImage(
                                        imageUrl,
                                      );

                                      // Remover da lista local
                                      setState(() {
                                        _productImages.removeAt(index);
                                        _imageFlavorAssignments.remove(
                                          imageUrl,
                                        );
                                      });

                                      // Atualizar imediatamente no banco de dados
                                      try {
                                        await Supabase.instance.client
                                            .from('produtos')
                                            .update({
                                              'imagens':
                                                  _productImages.isNotEmpty
                                                  ? _productImages
                                                  : null,
                                              'imagem_url':
                                                  _productImages.isNotEmpty
                                                  ? _productImages.first
                                                  : null,
                                            })
                                            .eq('id', widget.produto['id']);
                                      } catch (e) {
                                        debugPrint(
                                          'Erro ao atualizar imagens no banco: $e',
                                        );
                                      }

                                      if (mounted) {
                                        scaffoldMessenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('Imagem removida!'),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_hasMultipleFlavors && _flavors.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: DropdownButtonFormField<int>(
                                  key: ValueKey(
                                    'product_image_${imageUrl}_${_imageFlavorAssignments[imageUrl] ?? -1}_${_flavors.length}',
                                  ),
                                  initialValue:
                                      _imageFlavorAssignments[imageUrl] ?? -1,
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
                                      final label =
                                          controller.text.trim().isEmpty
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
                                      if (value == null || value == -1) {
                                        _imageFlavorAssignments.remove(
                                          imageUrl,
                                        );
                                      } else {
                                        _imageFlavorAssignments[imageUrl] =
                                            value;
                                      }
                                    });
                                  },
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                if (_productImages.isNotEmpty) const SizedBox(height: 16),

                // Botões de ação
                if (_isUploadingImages)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final scaffoldMessenger = ScaffoldMessenger.of(
                            context,
                          );
                          final images =
                              await ImageService.pickMultipleImagesFromGallery();

                          if (images.isNotEmpty && mounted) {
                            setState(() {
                              _isUploadingImages = true;
                            });

                            final uploadedUrls =
                                await ImageService.uploadMultipleProductImages(
                                  imageFiles: images,
                                  productId: widget.produto['id'],
                                  onProgress: (current, total) {
                                    debugPrint('Upload: $current/$total');
                                  },
                                );

                            if (mounted) {
                              setState(() {
                                _productImages.addAll(uploadedUrls);
                                _isUploadingImages = false;
                              });

                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${uploadedUrls.length} ${uploadedUrls.length == 1 ? "imagem adicionada" : "imagens adicionadas"}!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.add_photo_alternate),
                        label: Text(
                          _productImages.isEmpty
                              ? 'Adicionar Imagens'
                              : 'Adicionar Mais',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final scaffoldMessenger = ScaffoldMessenger.of(
                            context,
                          );
                          final image =
                              await ImageService.pickImageFromCamera();

                          if (image != null && mounted) {
                            setState(() {
                              _isUploadingImages = true;
                            });

                            final imageUrl =
                                await ImageService.uploadProductImage(
                                  imageFile: image,
                                  productId: widget.produto['id'],
                                );

                            if (imageUrl != null && mounted) {
                              setState(() {
                                _productImages.add(imageUrl);
                                _isUploadingImages = false;
                              });

                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Imagem adicionada!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                            if (imageUrl == null && mounted) {
                              setState(() {
                                _isUploadingImages = false;
                              });
                            }
                          }
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Tirar Foto'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Características
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              children: [
                const Row(
                  children: [
                    Icon(Icons.star, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Características',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                _buildFeatureCheckbox(
                  title: 'Produto Disponível',
                  value: _isDisponivel,
                  activeColor: Colors.green,
                  onChanged: (value) {
                    setState(() {
                      _isDisponivel = value ?? true;
                    });
                  },
                ),
                _buildFeatureCheckbox(
                  title: 'Mais Vendido',
                  value: _isMaisVendido,
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _isMaisVendido = value ?? false;
                    });
                  },
                ),
                _buildFeatureCheckbox(
                  title: 'Novidade',
                  value: _isNovidade,
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _isNovidade = value ?? false;
                    });
                  },
                ),
                _buildFeatureCheckbox(
                  title: 'Produto em Promoção',
                  value: _isPromocao,
                  activeColor: Colors.orange,
                  onChanged: (value) {
                    setState(() {
                      _isPromocao = value ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Campo de Desconto (visível quando marcado como promoção)
          if (_isPromocao)
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
          if (_isPromocao) const SizedBox(height: 16),

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
                        'Ative para diferentes tamanhos com preços variados',
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
                        _addSize();
                      } else if (!value) {
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

          // Lista de Tamanhos
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
                  const Row(
                    children: [
                      Icon(Icons.format_size, color: Colors.purple, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Tamanhos e Preços',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._sizes.asMap().entries.map((entry) {
                    final index = entry.key;
                    final size = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple[100]!),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: size['nameController'],
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Tamanho',
                                hintText: 'Ex: P, M, G',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: size['precoController'],
                              keyboardType: TextInputType.number,
                              inputFormatters: [CurrencyInputFormatter()],
                              decoration: InputDecoration(
                                labelText: 'Preço',
                                hintText: 'R\$ 0,00',
                                hintStyle: TextStyle(
                                  color: Colors.grey.withValues(alpha: 0.28),
                                ),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _removeSize(index),
                            icon: Image.asset(
                              'assets/icons/menu/delete_button.png',
                              width: 20,
                              height: 20,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addSize,
                      icon: Image.asset(
                        'assets/icons/menu/add_button.png',
                        width: 18,
                        height: 18,
                      ),
                      label: const Text('Adicionar Tamanho'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purple,
                        side: BorderSide(color: Colors.purple[200]!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ], // Fecha o if (_hasMultipleSizes)
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
                        _imageFlavorAssignments.clear();
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
                  Row(
                    children: [
                      const Icon(Icons.tune, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Sabores',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
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
                                onPressed: () => _removeFlavor(index),
                                icon: Image.asset(
                                  'assets/icons/menu/delete_button.png',
                                  width: 20,
                                  height: 20,
                                  color: Colors.red,
                                ),
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
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Sabor',
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
        ], // Fecha children do Column
      ), // Fecha Column
      actions: SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _updateProduct,
                icon: const Icon(Icons.save, size: 18),
                label: const Text(
                  'Salvar Alterações',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

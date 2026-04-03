import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/catalog_sync_service.dart';
import '../services/image_service.dart';
import 'form_dialogs.dart'; // Para usar CurrencyInputFormatter
import 'category_icon_widget.dart';

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
  late TextEditingController _imagemController;

  String? _selectedCategoryId;
  bool _isDisponivel = true;
  bool _isMaisVendido = false;
  bool _isNovidade = false;
  bool _isPromocao = false;
  bool _hasMultipleSizes = false;

  // Lista de tamanhos
  final List<Map<String, dynamic>> _sizes = [];
  String? _currentImageUrl;

  // Lista de imagens do produto (suporte a múltiplas imagens)
  List<String> _productImages = [];
  bool _isUploadingImages = false;

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

    // DEBUG: Imprimir estrutura completa do produto
    debugPrint('🔍 PRODUTO COMPLETO: ${widget.produto}');
    debugPrint('🔍 Keys do produto: ${widget.produto.keys.toList()}');

    // Inicializar controladores com dados do produto
    _nomeController = TextEditingController(text: widget.produto['nome'] ?? '');
    _descricaoController = TextEditingController(
      text: widget.produto['descricao'] ?? '',
    );
    _imagemController = TextEditingController(
      text: widget.produto['imagem_url'] ?? '',
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
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _valorDescontoController.dispose();
    _imagemController.dispose();
    for (final size in _sizes) {
      size['nameController']?.dispose();
      size['precoController']?.dispose();
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

    try {
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
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: RepaintBoundary(
            child: Column(
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
                    enableInteractiveSelection: false,
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
                    enableInteractiveSelection: false,
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
                      enableInteractiveSelection: false,
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
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Arraste para reordenar. A primeira imagem será a principal.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),

                      // Grid de imagens com reordenação
                      if (_productImages.isNotEmpty)
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _productImages.length,
                          onReorder: (oldIndex, newIndex) {
                            if (oldIndex < newIndex) newIndex--;
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
                                  color: index == 0
                                      ? Colors.blue
                                      : Colors.grey[300]!,
                                  width: index == 0 ? 2 : 1,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  // Imagem
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
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
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _imagemController,
                        enableInteractiveSelection: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Ou cole uma URL da imagem',
                          prefixIcon: Icon(Icons.link),
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          if (value.trim().isNotEmpty &&
                              !_productImages.contains(value.trim())) {
                            setState(() {
                              _productImages.add(value.trim());
                              _imagemController.clear();
                            });
                          }
                        },
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
                      CheckboxListTile(
                        title: const Text('Produto Disponível'),
                        value: _isDisponivel,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setState(() {
                            _isDisponivel = value ?? true;
                          });
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('Mais Vendido'),
                        value: _isMaisVendido,
                        activeColor: Colors.orange,
                        onChanged: (value) {
                          setState(() {
                            _isMaisVendido = value ?? false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('Novidade'),
                        value: _isNovidade,
                        activeColor: Colors.orange,
                        onChanged: (value) {
                          setState(() {
                            _isNovidade = value ?? false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('Produto em Promoção'),
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
                          enableInteractiveSelection: false,
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
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
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
                            Icon(
                              Icons.format_size,
                              color: Colors.purple,
                              size: 20,
                            ),
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
                                    enableInteractiveSelection: false,
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
                                    enableInteractiveSelection: false,
                                    decoration: InputDecoration(
                                      labelText: 'Preço',
                                      hintText: 'R\$ 0,00',
                                      hintStyle: TextStyle(
                                        color: Colors.grey.withValues(
                                          alpha: 0.28,
                                        ),
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
              ], // Fecha children do Column
            ), // Fecha Column
          ), // Fecha RepaintBoundary
        ), // Fecha SingleChildScrollView
      ), // Fecha SizedBox
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
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../services/image_service.dart';

// Formatter personalizado para entrada de preço
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue(
        text: 'R\$ 0,00',
        selection: TextSelection.collapsed(offset: 7),
      );
    }

    // Remove tudo que não é dígito
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: 'R\$ 0,00',
        selection: TextSelection.collapsed(offset: 7),
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
  final _precoController = TextEditingController(text: 'R\$ 0,00');
  final _precoAnteriorController = TextEditingController(text: 'R\$ 0,00');
  final _precoComDescontoController = TextEditingController(text: 'R\$ 0,00');
  final _valorDescontoController = TextEditingController(text: 'R\$ 0,00');
  final _imagemUrlController = TextEditingController();
  String? _selectedCategoryId;
  bool _isDisponivel = true;
  bool _isMaisVendido = false;
  bool _isNovidade = false;
  bool _isComDesconto = false;
  bool _hasMultipleSizes = false; // Nova opção para produtos com tamanhos

  // Campos para upload de imagem
  File? _selectedImage;
  String? _uploadedImageUrl;

  // Lista de tamanhos e preços
  final List<Map<String, dynamic>> _sizes = [];

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _precoAnteriorController.dispose();
    _precoComDescontoController.dispose();
    _valorDescontoController.dispose();
    _imagemUrlController.dispose();
    super.dispose();
  }

  void _addSize() {
    setState(() {
      _sizes.add({
        'nome': '',
        'preco': 0.0,
        'nameController': TextEditingController(),
        'precoController': TextEditingController(text: 'R\$ 0,00'),
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

  Future<void> _selectImage() async {
    debugPrint('🖼️ Iniciando seleção de imagem...');
    final image = await ImageService.showImagePickerDialog(context);
    debugPrint('🖼️ Imagem retornada: ${image?.path ?? "null"}');

    if (image != null) {
      debugPrint('🖼️ Atualizando estado com imagem: ${image.path}');
      setState(() {
        _selectedImage = image;
        _uploadedImageUrl = null; // Limpar URL anterior se houver
      });
      debugPrint(
        '🖼️ Estado atualizado! _selectedImage: ${_selectedImage?.path}',
      );

      // Mostrar confirmação visual
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Imagem selecionada! Clique em "Enviar" para fazer upload.',
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      debugPrint('🖼️ Nenhuma imagem foi selecionada ou retornou null');
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

      // Usar imagem enviada se disponível, senão usar URL manual
      final imagemUrl =
          _uploadedImageUrl ??
          (_imagemUrlController.text.trim().isEmpty
              ? null
              : _imagemUrlController.text.trim());

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

      final produtoData = {
        'nome': nomeProduto,
        'descricao': _descricaoController.text.trim().isEmpty
            ? null
            : _descricaoController.text.trim(),
        'preco': preco, // Menor preço quando tem múltiplos tamanhos
        'preco_anterior': precoAnterior,
        'categoria_id': int.parse(_selectedCategoryId!),
        'imagem_url': imagemUrl,
        'ativo': _isDisponivel,
        'mais_vendido': _isMaisVendido,
        'novidade': _isNovidade,
        'promocao':
            precoAnterior != null, // Automaticamente true se tem desconto
        'tamanhos': tamanhos, // Array JSON de tamanhos e preços
      };

      try {
        // Tentar chamar função RPC que bypassa RLS
        await Supabase.instance.client.rpc(
          'insert_produto_admin',
          params: {'dados': produtoData},
        );
      } catch (rpcError) {
        debugPrint('RPC insert falhou: $rpcError');
        // Tentar insert normal
        await Supabase.instance.client.from('produtos').insert(produtoData);
      }

      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Produto adicionado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: RepaintBoundary(
            child: Column(
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
                          Icons.attach_money,
                          color: Colors.green,
                        ),
                        hintText: 'R\$ 0,00',
                        hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
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
                        hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
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
                        hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
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
                            Text(
                              categoria['icone'] ?? '📦',
                              style: const TextStyle(fontSize: 16),
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

                  // Upload de Imagem
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A primeira imagem será a principal.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),

                        // Preview da imagem
                        if (_selectedImage != null || _uploadedImageUrl != null)
                          Container(
                            width: double.infinity,
                            height: 120,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue, width: 2),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: _selectedImage != null
                                  ? Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.cover,
                                    )
                                  : _uploadedImageUrl != null
                                  ? Image.network(
                                      _uploadedImageUrl!,
                                      fit: BoxFit.cover,
                                      cacheWidth: 240,
                                      cacheHeight: 240,
                                      filterQuality: FilterQuality.medium,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: Icon(
                                              Icons.error,
                                              color: Colors.red,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : null,
                            ),
                          ),

                        // Botões de ação
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _selectImage,
                                icon: const Icon(Icons.add_photo_alternate),
                                label: Text(
                                  _selectedImage != null || _uploadedImageUrl != null
                                      ? 'Adicionar Mais'
                                      : 'Adicionar Imagens',
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
                                  final image = await ImageService.pickImageFromCamera();
                                  if (image != null) {
                                    setState(() {
                                      _selectedImage = image;
                                      _uploadedImageUrl = null;
                                    });
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
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.grey[600],
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Ou cole uma URL:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _imagemUrlController,
                                decoration: const InputDecoration(
                                  labelText: 'URL da imagem',
                                  labelStyle: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.link,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  hintText: 'https://exemplo.com/imagem.jpg',
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(8),
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                                onChanged: (url) {
                                  if (url.isNotEmpty) {
                                    setState(() {
                                      _uploadedImageUrl = url;
                                    });
                                  }
                                },
                              ),
                            ],
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
                              color: _isMaisVendido
                                  ? Colors.amber
                                  : Colors.grey,
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
                              _isNovidade
                                  ? Icons.fiber_new
                                  : Icons.fiber_new_outlined,
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
                          _isComDesconto
                              ? Icons.discount
                              : Icons.discount_outlined,
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
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
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
                          color: _hasMultipleSizes
                              ? Colors.purple
                              : Colors.grey,
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
                                icon: const Icon(Icons.add, size: 18),
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
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
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
                                                controller:
                                                    size['nameController'],
                                                decoration: InputDecoration(
                                                  labelText: 'Tamanho *',
                                                  hintText:
                                                      'Ex: P, M, G, 300ml',
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
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
                                                controller:
                                                    size['precoController'],
                                                keyboardType:
                                                    TextInputType.number,
                                                inputFormatters: [
                                                  CurrencyInputFormatter(),
                                                ],
                                                decoration: InputDecoration(
                                                  labelText: 'Preço *',
                                                  hintText: 'R\$ 0,00',
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
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
                                                  final precoText = value
                                                      .trim();
                                                  final precoNumerico =
                                                      precoText
                                                          .replaceAll(
                                                            'R\$ ',
                                                            '',
                                                          )
                                                          .replaceAll(',', '.');
                                                  size['preco'] =
                                                      double.tryParse(
                                                        precoNumerico,
                                                      ) ??
                                                      0.0;
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                              ),
                                              onPressed: () =>
                                                  _removeSize(index),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
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
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
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
                  child: const Text(
                    'Adicionar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

      await Supabase.instance.client.from('categorias').insert({
        'nome': nomeCategoria,
        'icone': _iconeController.text.trim().isEmpty
            ? '📦'
            : _iconeController.text.trim(),
        'ativo': true,
        'ordem': nextOrdem,
      });

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
        child: const Row(
          children: [
            Icon(Icons.add_circle, color: Colors.white, size: 28),
            SizedBox(width: 12),
            Text(
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
                    decoration: const InputDecoration(
                      labelText: 'Nome da Categoria *',
                      labelStyle: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Icon(Icons.category, color: Colors.blue),
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
                      hintText: '🍰 (emoji da categoria)',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                      helperText: 'Obrigatório - Use um emoji',
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
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
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
                  child: const Text(
                    'Adicionar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/image_service.dart';
import 'form_dialogs.dart'; // Para usar CurrencyInputFormatter

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
  late TextEditingController _precoAnteriorController;
  late TextEditingController _precoComDescontoController;
  late TextEditingController _imagemController;

  String? _selectedCategoryId;
  bool _isMaisVendido = false;
  bool _isNovidade = false;
  bool _isPromocao = false;
  bool _isComDesconto = false;
  bool _hasMultipleSizes = false;

  // Lista de tamanhos
  final List<Map<String, dynamic>> _sizes = [];
  String? _currentImageUrl;

  @override
  void initState() {
    super.initState();

    // Inicializar controladores com dados do produto
    _nomeController = TextEditingController(text: widget.produto['nome'] ?? '');
    _descricaoController = TextEditingController(
      text: widget.produto['descricao'] ?? '',
    );
    _imagemController = TextEditingController(
      text: widget.produto['imagem_url'] ?? '',
    );

    _selectedCategoryId = widget.produto['categoria_id']?.toString();
    _isMaisVendido = widget.produto['mais_vendido'] ?? false;
    _isNovidade = widget.produto['novidade'] ?? false;
    _isPromocao = widget.produto['promocao'] ?? false;
    _currentImageUrl = widget.produto['imagem_url'];

    // Verificar se tem preço anterior (produto com desconto)
    final precoAnterior = widget.produto['preco_anterior'];
    if (precoAnterior != null && precoAnterior > 0) {
      _isComDesconto = true;
      _precoAnteriorController = TextEditingController(
        text: precoAnterior.toString(),
      );
      _precoComDescontoController = TextEditingController(
        text: widget.produto['preco']?.toString() ?? '',
      );
      _precoController = TextEditingController();
    } else {
      _precoController = TextEditingController(
        text: widget.produto['preco']?.toString() ?? '',
      );
      _precoAnteriorController = TextEditingController();
      _precoComDescontoController = TextEditingController();
    }

    // Verificar se tem múltiplos tamanhos
    final tamanhos = widget.produto['tamanhos'];
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      _hasMultipleSizes = true;
      for (var tamanho in tamanhos) {
        _sizes.add({
          'nameController': TextEditingController(text: tamanho['nome'] ?? ''),
          'precoController': TextEditingController(
            text: tamanho['preco']?.toString() ?? '',
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
    _precoAnteriorController.dispose();
    _precoComDescontoController.dispose();
    _imagemController.dispose();
    for (var size in _sizes) {
      size['nameController']?.dispose();
      size['precoController']?.dispose();
    }
    super.dispose();
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
      if (_isComDesconto) {
        if (_precoAnteriorController.text.trim().isEmpty ||
            _precoComDescontoController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preencha o preço anterior e o preço com desconto'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } else {
        if (_precoController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preço é obrigatório'),
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
    }

    try {
      double preco;
      double? precoAnterior;
      List<Map<String, dynamic>>? tamanhos;

      if (_hasMultipleSizes) {
        // Com múltiplos tamanhos
        tamanhos = _sizes.map((size) {
          return {
            'nome': size['nameController'].text.trim(),
            'preco': double.parse(size['precoController'].text.trim()),
          };
        }).toList();

        // Usar o menor preço como referência
        preco = tamanhos
            .map((t) => t['preco'] as double)
            .reduce((a, b) => a < b ? a : b);
      } else if (_isComDesconto) {
        // Com desconto
        precoAnterior = double.parse(_precoAnteriorController.text.trim());
        preco = double.parse(_precoComDescontoController.text.trim());
      } else {
        // Preço simples
        preco = double.parse(_precoController.text.trim());
      }

      final updateData = {
        'nome': _nomeController.text.trim(),
        'descricao': _descricaoController.text.trim().isEmpty
            ? null
            : _descricaoController.text.trim(),
        'preco': preco,
        'preco_anterior': precoAnterior,
        'categoria_id': int.parse(_selectedCategoryId!),
        'imagem_url': _imagemController.text.trim().isEmpty
            ? null
            : _imagemController.text.trim(),
        'mais_vendido': _isMaisVendido,
        'novidade': _isNovidade,
        'promocao': _isPromocao,
        'tamanhos': tamanhos,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client
          .from('produtos')
          .update(updateData)
          .eq('id', widget.produto['id']);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
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
                  decoration: const InputDecoration(
                    labelText: 'Descrição',
                    prefixIcon: Icon(Icons.description),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Campo de Preço (se não tem tamanhos nem desconto)
              if (!_hasMultipleSizes && !_isComDesconto)
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
                    decoration: const InputDecoration(
                      labelText: 'Preço *',
                      labelStyle: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Icon(Icons.attach_money, color: Colors.blue),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),

              // Campos de Desconto
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
                    decoration: const InputDecoration(
                      labelText: 'Preço Anterior *',
                      labelStyle: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Icon(Icons.money_off, color: Colors.orange),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
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
                    decoration: const InputDecoration(
                      labelText: 'Preço com Desconto *',
                      labelStyle: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                      prefixIcon: Icon(Icons.local_offer, color: Colors.green),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
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
                      child: Text('${categoria['icone']} ${categoria['nome']}'),
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
                  children: [
                    if (_currentImageUrl != null &&
                        _currentImageUrl!.isNotEmpty)
                      Container(
                        height: 200,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _currentImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.error, size: 50),
                              );
                            },
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final scaffoldMessenger = ScaffoldMessenger.of(
                                context,
                              );
                              final image =
                                  await ImageService.showImagePickerDialog(
                                    context,
                                  );
                              if (image != null && mounted) {
                                final imageUrl =
                                    await ImageService.uploadProductImage(
                                      imageFile: image,
                                      productId: widget.produto['id'],
                                      oldImageUrl: _currentImageUrl,
                                    );
                                if (imageUrl != null && mounted) {
                                  setState(() {
                                    _currentImageUrl = imageUrl;
                                    _imagemController.text = imageUrl;
                                  });
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Imagem atualizada!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Alterar Imagem'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        if (_currentImageUrl != null &&
                            _currentImageUrl!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () async {
                              final scaffoldMessenger = ScaffoldMessenger.of(
                                context,
                              );
                              await ImageService.deleteProductImage(
                                _currentImageUrl!,
                              );
                              if (mounted) {
                                setState(() {
                                  _currentImageUrl = null;
                                  _imagemController.clear();
                                });
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Imagem removida!'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.delete, color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _imagemController,
                      decoration: const InputDecoration(
                        labelText: 'Ou cole uma URL da imagem',
                        prefixIcon: Icon(Icons.link),
                        border: InputBorder.none,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _currentImageUrl = value;
                        });
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
                      title: const Text('Promoção'),
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

              // Switch para Desconto
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
                          ? Icons.local_offer
                          : Icons.local_offer_outlined,
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
                            'Ative para definir preço anterior e com desconto',
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
                                  decoration: const InputDecoration(
                                    labelText: 'Preço',
                                    hintText: 'R\$ 0,00',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.all(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () => _removeSize(index),
                                icon: const Icon(
                                  Icons.delete,
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
                          icon: const Icon(Icons.add),
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
              ],
            ],
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
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _updateProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Atualizar',
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

import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Tipo de ação a ser executada após seleção do tamanho
enum SizeSelectionAction { buyNow, addToCart }

/// Diálogo para seleção de tamanho de produto
class SizeSelectorDialog extends StatefulWidget {
  final Map<String, dynamic> produto;
  final Function(Map<String, dynamic> selectedSize) onSizeSelected;
  final SizeSelectionAction action;

  const SizeSelectorDialog({
    super.key,
    required this.produto,
    required this.onSizeSelected,
    this.action = SizeSelectionAction.addToCart,
  });

  @override
  State<SizeSelectorDialog> createState() => _SizeSelectorDialogState();
}

class _SizeSelectorDialogState extends State<SizeSelectorDialog> {
  Map<String, dynamic>? _selectedSize;

  @override
  void initState() {
    super.initState();
    final tamanhos = widget.produto['tamanhos'];
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      _selectedSize = tamanhos[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tamanhos = widget.produto['tamanhos'] as List<dynamic>? ?? [];

    if (tamanhos.isEmpty) {
      return AlertDialog(
        title: const Text('Erro'),
        content: const Text('Este produto não possui tamanhos disponíveis.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Escolha o tamanho',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.produto['nome'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Lista de tamanhos
            Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tamanhos.length,
                itemBuilder: (context, index) {
                  final tamanho = tamanhos[index];
                  final isSelected = _selectedSize == tamanho;
                  final preco = tamanho['preco']?.toDouble() ?? 0.0;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSize = tamanho;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected
                            ? Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.1)
                            : Colors.white,
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.grey[400],
                          ),
                        ),
                        title: Text(
                          tamanho['nome'] ?? 'Tamanho ${index + 1}',
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: tamanho['descricao'] != null
                            ? Text(
                                tamanho['descricao'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              )
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            CurrencyFormatter.format(preco),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Botão de confirmar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedSize != null
                      ? () {
                          widget.onSizeSelected(_selectedSize!);
                          Navigator.pop(context);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.action == SizeSelectionAction.buyNow
                        ? Colors.black
                        : Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.action == SizeSelectionAction.buyNow
                            ? Icons.shopping_bag
                            : Icons.add_shopping_cart,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.action == SizeSelectionAction.buyNow
                            ? 'Comprar Agora'
                            : 'Adicionar ao Carrinho',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

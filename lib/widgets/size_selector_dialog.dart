import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/product_variant_utils.dart';
import 'adaptive_dropdown_menu.dart';
import 'flavor_icon_widget.dart';

/// Tipo de ação a ser executada após seleção das opções
enum SizeSelectionAction { buyNow, addToCart }

class ProductOptionsSelection {
  final Map<String, dynamic>? selectedSize;
  final Map<String, dynamic>? selectedFlavor;

  const ProductOptionsSelection({this.selectedSize, this.selectedFlavor});
}

/// Diálogo para seleção de tamanho e/ou sabor de produto.
class SizeSelectorDialog extends StatefulWidget {
  final Map<String, dynamic> produto;
  final Function(Map<String, dynamic> selectedSize)? onSizeSelected;
  final Function(ProductOptionsSelection selection)? onOptionsSelected;
  final SizeSelectionAction action;

  const SizeSelectorDialog({
    super.key,
    required this.produto,
    this.onSizeSelected,
    this.onOptionsSelected,
    this.action = SizeSelectionAction.addToCart,
  });

  @override
  State<SizeSelectorDialog> createState() => _SizeSelectorDialogState();
}

class _SizeSelectorDialogState extends State<SizeSelectorDialog> {
  Map<String, dynamic>? _selectedSize;
  Map<String, dynamic>? _selectedFlavor;

  late final List<Map<String, dynamic>> _sizes;
  late final List<Map<String, dynamic>> _flavors;

  @override
  void initState() {
    super.initState();
    _sizes = ProductVariantUtils.extractSizes(widget.produto['tamanhos']);
    _flavors = ProductVariantUtils.extractFlavors(widget.produto['sabores']);

    if (_sizes.isNotEmpty) {
      _selectedSize = _sizes.first;
    }
    if (_flavors.isNotEmpty) {
      _selectedFlavor = _flavors.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sizes.isEmpty && _flavors.isEmpty) {
      return AlertDialog(
        title: const Text('Erro'),
        content: const Text('Este produto não possui opções disponíveis.'),
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
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFlavorPreview(),
                    if (_flavors.isNotEmpty) ...[
                      _buildFlavorDropdown(),
                      const SizedBox(height: 16),
                    ],
                    if (_sizes.isNotEmpty) _buildSizeDropdown(),
                  ],
                ),
              ),
            ),
            _buildConfirmButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final title = _sizes.isNotEmpty && _flavors.isNotEmpty
        ? 'Escolha as opções'
        : _flavors.isNotEmpty
        ? 'Escolha o sabor'
        : 'Escolha o tamanho';

    return Container(
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
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.produto['nome'] ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
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
    );
  }

  Widget _buildFlavorPreview() {
    final images = ProductVariantUtils.productImages(
      widget.produto,
      selectedFlavor: _selectedFlavor,
    );
    if (images.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.network(
            images.first,
            fit: BoxFit.cover,
            cacheWidth: 640,
            cacheHeight: 360,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.orange[50],
              child: const Center(
                child: Icon(Icons.fastfood, color: Colors.orange, size: 42),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlavorDropdown() {
    final selectedIcon = ProductVariantUtils.optionIcon(_selectedFlavor);

    return LayoutBuilder(
      builder: (context, constraints) {
        return AdaptiveDropdownMenu<Map<String, dynamic>>(
          items: _flavors,
          selectedItem: _selectedFlavor,
          menuWidth: constraints.maxWidth,
          itemHeight: 56,
          maxVisibleItems: 5,
          onSelected: (value) {
            setState(() {
              _selectedFlavor = value;
            });
          },
          buttonBuilder: (context, isOpen) {
            final selectedName =
                ProductVariantUtils.optionName(_selectedFlavor) ?? 'Sabor';
            return Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[600]!),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  if (selectedIcon != null) ...[
                    FlavorIconWidget(icon: selectedIcon, size: 24),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      selectedName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Icon(
                    isOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.black54,
                  ),
                ],
              ),
            );
          },
          itemBuilder: (context, flavor, isSelected) {
            final name = ProductVariantUtils.optionName(flavor) ?? 'Sabor';
            final icon = ProductVariantUtils.optionIcon(flavor);
            return Container(
              color: isSelected ? Colors.orange[50] : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (icon != null) ...[
                    FlavorIconWidget(icon: icon, size: 24),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                  if (isSelected)
                    Icon(
                      Icons.check_rounded,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSizeDropdown() {
    return DropdownButtonFormField<Map<String, dynamic>>(
      initialValue: _selectedSize,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Tamanho',
        prefixIcon: Icon(Icons.format_size),
        border: OutlineInputBorder(),
      ),
      items: _sizes.map((size) {
        final name = ProductVariantUtils.optionName(size) ?? 'Tamanho';
        final price = ProductVariantUtils.toDouble(size['preco']);
        final label = price == null
            ? name
            : '$name - ${CurrencyFormatter.format(price)}';
        return DropdownMenuItem<Map<String, dynamic>>(
          value: size,
          child: Text(label, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedSize = value;
        });
      },
    );
  }

  Widget _buildConfirmButton(BuildContext context) {
    final canConfirm =
        (_sizes.isEmpty || _selectedSize != null) &&
        (_flavors.isEmpty || _selectedFlavor != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: canConfirm
              ? () {
                  final selection = ProductOptionsSelection(
                    selectedSize: _selectedSize,
                    selectedFlavor: _selectedFlavor,
                  );
                  widget.onOptionsSelected?.call(selection);
                  if (widget.onSizeSelected != null && _selectedSize != null) {
                    widget.onSizeSelected!(_selectedSize!);
                  }
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
    );
  }
}

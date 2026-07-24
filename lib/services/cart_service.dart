import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../utils/product_variant_utils.dart';

class CartItem {
  final String id;
  final String nome;
  final double preco;
  final String? imagemUrl;
  final String? categoriaId;
  final String? categoriaNome;
  final String? categoriaIcone;
  int quantidade;
  String? observacoes;
  final bool isBuyNow; // Identifica se foi adicionado via "Comprar"
  final String? tamanhoSelecionado; // Tamanho selecionado (ex: "P", "M", "G")
  final String? saborSelecionado; // Sabor selecionado (ex: "Chocolate")

  CartItem({
    required this.id,
    required this.nome,
    required this.preco,
    this.imagemUrl,
    this.categoriaId,
    this.categoriaNome,
    this.categoriaIcone,
    this.quantidade = 1,
    this.observacoes,
    this.isBuyNow = false,
    this.tamanhoSelecionado,
    this.saborSelecionado,
  });

  double get subtotal => preco * quantidade;

  String get cartKey => buildCartKey(
    id,
    tamanhoSelecionado: tamanhoSelecionado,
    saborSelecionado: saborSelecionado,
    isBuyNow: isBuyNow,
  );

  static String buildCartKey(
    String productId, {
    String? tamanhoSelecionado,
    String? saborSelecionado,
    bool isBuyNow = false,
  }) {
    return [
      productId,
      tamanhoSelecionado ?? '',
      saborSelecionado ?? '',
      isBuyNow ? 'buyNow' : 'cart',
    ].join('|');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'preco': preco,
      'imagemUrl': imagemUrl,
      'categoriaId': categoriaId,
      'categoriaNome': categoriaNome,
      'categoriaIcone': categoriaIcone,
      'quantidade': quantidade,
      'observacoes': observacoes,
      'isBuyNow': isBuyNow,
      'tamanhoSelecionado': tamanhoSelecionado,
      'saborSelecionado': saborSelecionado,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      nome: json['nome'],
      preco: ProductVariantUtils.toDouble(json['preco']) ?? 0.0,
      imagemUrl: json['imagemUrl'],
      categoriaId: json['categoriaId'],
      categoriaNome: json['categoriaNome'],
      categoriaIcone: json['categoriaIcone'],
      quantidade: json['quantidade'] ?? 1,
      observacoes: json['observacoes'],
      isBuyNow: json['isBuyNow'] ?? false,
      tamanhoSelecionado: json['tamanhoSelecionado'],
      saborSelecionado: json['saborSelecionado'],
    );
  }
}

class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  List<CartItem> _items = [];
  String? _orderObservation;
  bool _isLoading = false;

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.length;
  String? get orderObservation => _orderObservation;

  // Total de itens no carrinho (considerando quantidade de cada item)
  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantidade);

  // Total do carrinho
  double get total => _items.fold(0.0, (sum, item) => sum + item.subtotal);

  // Carregar carrinho do armazenamento local
  Future<void> loadCart() async {
    try {
      _isLoading = true;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      final cartData = prefs.getString('cart_items');
      _orderObservation = prefs.getString('cart_order_observation');

      if (cartData != null) {
        final List<dynamic> cartJson = json.decode(cartData);
        _items = cartJson.map((item) => CartItem.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Erro ao carregar carrinho: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Salvar carrinho no armazenamento local
  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartJson = _items.map((item) => item.toJson()).toList();
      await prefs.setString('cart_items', json.encode(cartJson));
      final observation = _orderObservation?.trim();
      if (observation == null || observation.isEmpty || _items.isEmpty) {
        await prefs.remove('cart_order_observation');
      } else {
        await prefs.setString('cart_order_observation', observation);
      }
    } catch (e) {
      debugPrint('Erro ao salvar carrinho: $e');
    }
  }

  // Adicionar item ao carrinho
  Future<void> addItem(
    Map<String, dynamic> produto, {
    int quantidade = 1,
    String? observacoes,
    bool isBuyNow = false,
  }) async {
    final productId = produto['id'].toString();

    // Converter tamanho_selecionado para string se necessário
    String? tamanhoSelecionadoString;
    if (produto['tamanho_selecionado'] != null) {
      if (produto['tamanho_selecionado'] is Map) {
        tamanhoSelecionadoString = json.encode(produto['tamanho_selecionado']);
      } else {
        tamanhoSelecionadoString = produto['tamanho_selecionado'].toString();
      }
    }

    String? saborSelecionadoString;
    if (produto['sabor_selecionado'] != null) {
      if (produto['sabor_selecionado'] is Map) {
        saborSelecionadoString = json.encode(produto['sabor_selecionado']);
      } else {
        saborSelecionadoString = produto['sabor_selecionado'].toString();
      }
    }

    // Se for "Comprar Agora", remover itens anteriores marcados como buyNow
    if (isBuyNow) {
      _items.removeWhere((item) => item.isBuyNow);
    }

    // Verificar se o produto já existe no carrinho (considerando tamanho/sabor e não sendo buyNow)
    final existingIndex = _items.indexWhere(
      (item) =>
          item.id == productId &&
          item.tamanhoSelecionado == tamanhoSelecionadoString &&
          item.saborSelecionado == saborSelecionadoString &&
          !item.isBuyNow,
    );

    if (existingIndex >= 0 && !isBuyNow) {
      // Se existe e não é buyNow, aumentar a quantidade
      _items[existingIndex].quantidade += quantidade;
      if (observacoes != null && observacoes.trim().isNotEmpty) {
        _items[existingIndex].observacoes = observacoes.trim();
      }
    } else {
      final rawCategory = produto['categorias'];
      Map<dynamic, dynamic>? relatedCategory;
      if (rawCategory is Map) {
        relatedCategory = rawCategory;
      } else if (rawCategory is List &&
          rawCategory.isNotEmpty &&
          rawCategory.first is Map) {
        relatedCategory = rawCategory.first as Map;
      }

      // Se não existe ou é buyNow, adicionar nova entrada
      final cartItem = CartItem(
        id: productId,
        nome: produto['nome'] ?? 'Produto sem nome',
        preco: ProductVariantUtils.toDouble(produto['preco']) ?? 0.0,
        imagemUrl:
            produto['imagem_url'] ??
            (produto['imagens'] is List &&
                    (produto['imagens'] as List).isNotEmpty
                ? (produto['imagens'] as List)[0]
                : null),
        categoriaId: produto['categoria_id']?.toString(),
        categoriaNome:
            produto['categoria_nome'] ?? relatedCategory?['nome']?.toString(),
        categoriaIcone:
            produto['categoria_icone'] ?? relatedCategory?['icone']?.toString(),
        quantidade: quantidade,
        observacoes: observacoes?.trim().isEmpty == true
            ? null
            : observacoes?.trim(),
        isBuyNow: isBuyNow,
        tamanhoSelecionado: tamanhoSelecionadoString,
        saborSelecionado: saborSelecionadoString,
      );
      _items.add(cartItem);
    }

    await _saveCart();
    notifyListeners();
  }

  // Remover item do carrinho
  Future<void> removeItem(String itemKey) async {
    _items.removeWhere((item) => item.cartKey == itemKey);
    if (_items.isEmpty) {
      _orderObservation = null;
    }
    await _saveCart();
    notifyListeners();
  }

  // Atualizar quantidade de um item
  Future<void> updateQuantity(String itemKey, int newQuantity) async {
    if (newQuantity <= 0) {
      await removeItem(itemKey);
      return;
    }

    final index = _items.indexWhere((item) => item.cartKey == itemKey);
    if (index >= 0) {
      _items[index].quantidade = newQuantity;
      await _saveCart();
      notifyListeners();
    }
  }

  Future<void> updateOrderObservation(String? observation) async {
    final normalized = observation?.trim();
    _orderObservation = normalized == null || normalized.isEmpty
        ? null
        : observation;
    await _saveCart();
    notifyListeners();
  }

  Future<void> updateObservations(String itemKey, String? observations) async {
    final index = _items.indexWhere((item) => item.cartKey == itemKey);
    if (index < 0) return;

    final normalized = observations?.trim();
    _items[index].observacoes = normalized == null || normalized.isEmpty
        ? null
        : observations;
    await _saveCart();
    notifyListeners();
  }

  // Limpar carrinho
  Future<void> clearCart() async {
    _items.clear();
    _orderObservation = null;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove('cart_items'),
      prefs.remove('cart_order_observation'),
    ]);
    notifyListeners();
  }

  // Limpar apenas itens de "Comprar Agora"
  Future<void> clearBuyNowItems() async {
    final hadBuyNowItems = _items.any((item) => item.isBuyNow);
    _items.removeWhere((item) => item.isBuyNow);

    if (hadBuyNowItems) {
      if (_items.isEmpty) {
        _orderObservation = null;
      }
      await _saveCart();
      notifyListeners();
    }
  }

  // Confirmar compra (converte itens buyNow em itens normais do carrinho)
  Future<void> confirmBuyNowItems() async {
    // Esta função não é mais necessária pois vamos limpar no checkout
    // Mas mantemos para compatibilidade futura
  }

  // Verificar se há itens de "Comprar Agora" no carrinho
  bool hasBuyNowItems() {
    return _items.any((item) => item.isBuyNow);
  }

  // Verificar se um produto está no carrinho
  bool isInCart(String productId) {
    return _items.any((item) => item.id == productId);
  }

  // Obter quantidade de um produto no carrinho
  int getQuantity(String productId) {
    final item = _items.firstWhere(
      (item) => item.id == productId,
      orElse: () => CartItem(id: '', nome: '', preco: 0.0),
    );
    return item.id.isNotEmpty ? item.quantidade : 0;
  }
}

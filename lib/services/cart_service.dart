import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CartItem {
  final String id;
  final String nome;
  final double preco;
  final String? imagemUrl;
  final String? categoriaId;
  final String? categoriaNome;
  int quantidade;
  String? observacoes;
  final bool isBuyNow; // Identifica se foi adicionado via "Comprar"
  final String? tamanhoSelecionado; // Tamanho selecionado (ex: "P", "M", "G")

  CartItem({
    required this.id,
    required this.nome,
    required this.preco,
    this.imagemUrl,
    this.categoriaId,
    this.categoriaNome,
    this.quantidade = 1,
    this.observacoes,
    this.isBuyNow = false,
    this.tamanhoSelecionado,
  });

  double get subtotal => preco * quantidade;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'preco': preco,
      'imagemUrl': imagemUrl,
      'categoriaId': categoriaId,
      'categoriaNome': categoriaNome,
      'quantidade': quantidade,
      'observacoes': observacoes,
      'isBuyNow': isBuyNow,
      'tamanhoSelecionado': tamanhoSelecionado,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'],
      nome: json['nome'],
      preco: json['preco']?.toDouble() ?? 0.0,
      imagemUrl: json['imagemUrl'],
      categoriaId: json['categoriaId'],
      categoriaNome: json['categoriaNome'],
      quantidade: json['quantidade'] ?? 1,
      observacoes: json['observacoes'],
      isBuyNow: json['isBuyNow'] ?? false,
      tamanhoSelecionado: json['tamanhoSelecionado'],
    );
  }
}

class CartService extends ChangeNotifier {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  List<CartItem> _items = [];
  bool _isLoading = false;

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.length;

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

    // Se for "Comprar Agora", remover itens anteriores marcados como buyNow
    if (isBuyNow) {
      _items.removeWhere((item) => item.isBuyNow);
    }

    // Verificar se o produto já existe no carrinho (considerando tamanho e não sendo buyNow)
    final existingIndex = _items.indexWhere(
      (item) =>
          item.id == productId &&
          item.tamanhoSelecionado == tamanhoSelecionadoString &&
          !item.isBuyNow,
    );

    if (existingIndex >= 0 && !isBuyNow) {
      // Se existe e não é buyNow, aumentar a quantidade
      _items[existingIndex].quantidade += quantidade;
      // Atualizar observações se fornecidas
      if (observacoes != null && observacoes.isNotEmpty) {
        _items[existingIndex].observacoes = observacoes;
      }
    } else {
      // Se não existe ou é buyNow, adicionar nova entrada
      final cartItem = CartItem(
        id: productId,
        nome: produto['nome'] ?? 'Produto sem nome',
        preco: (produto['preco'] ?? 0.0).toDouble(),
        imagemUrl: produto['imagem_url'],
        categoriaId: produto['categoria_id']?.toString(),
        categoriaNome: produto['categoria_nome'],
        quantidade: quantidade,
        observacoes: observacoes,
        isBuyNow: isBuyNow,
        tamanhoSelecionado: tamanhoSelecionadoString,
      );
      _items.add(cartItem);
    }

    await _saveCart();
    notifyListeners();
  }

  // Remover item do carrinho
  Future<void> removeItem(String productId) async {
    _items.removeWhere((item) => item.id == productId);
    await _saveCart();
    notifyListeners();
  }

  // Atualizar quantidade de um item
  Future<void> updateQuantity(String productId, int newQuantity) async {
    if (newQuantity <= 0) {
      await removeItem(productId);
      return;
    }

    final index = _items.indexWhere((item) => item.id == productId);
    if (index >= 0) {
      _items[index].quantidade = newQuantity;
      await _saveCart();
      notifyListeners();
    }
  }

  // Atualizar observações de um item
  Future<void> updateObservations(String productId, String? observacoes) async {
    final index = _items.indexWhere((item) => item.id == productId);
    if (index >= 0) {
      _items[index].observacoes = observacoes;
      await _saveCart();
      notifyListeners();
    }
  }

  // Limpar carrinho
  Future<void> clearCart() async {
    _items.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cart_items');
    notifyListeners();
  }

  // Limpar apenas itens de "Comprar Agora"
  Future<void> clearBuyNowItems() async {
    final hadBuyNowItems = _items.any((item) => item.isBuyNow);
    _items.removeWhere((item) => item.isBuyNow);

    if (hadBuyNowItems) {
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

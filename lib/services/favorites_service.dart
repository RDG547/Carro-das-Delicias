import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Serviço para gerenciar produtos favoritos
class FavoritesService extends ChangeNotifier {
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final Set<String> _favoriteIds = {};
  bool _isLoaded = false;

  Set<String> get favoriteIds => _favoriteIds;
  int get totalFavorites => _favoriteIds.length;

  /// Carrega favoritos do usuário
  Future<void> loadFavorites() async {
    if (_isLoaded) return;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        // Se não está autenticado, carregar do cache local
        await _loadFromCache();
        return;
      }

      // Tentar carregar do Supabase
      try {
        final response = await _supabase
            .from('favoritos')
            .select('produto_id')
            .eq('user_id', user.id);

        _favoriteIds.clear();
        for (var item in response) {
          _favoriteIds.add(item['produto_id'].toString());
        }

        // Salvar no cache
        await _saveToCache();
        _isLoaded = true;
        notifyListeners();
      } catch (e) {
        // Se a tabela não existe ainda, carregar do cache
        debugPrint('Tabela favoritos ainda não existe, usando cache: $e');
        await _loadFromCache();
      }
    } catch (e) {
      debugPrint('Erro ao carregar favoritos: $e');
      await _loadFromCache();
    }
  }

  /// Verifica se um produto é favorito
  bool isFavorite(String productId) {
    return _favoriteIds.contains(productId);
  }

  /// Adiciona ou remove um produto dos favoritos
  Future<void> toggleFavorite(String productId) async {
    final wasFavorite = _favoriteIds.contains(productId);

    if (wasFavorite) {
      await _removeFavorite(productId);
    } else {
      await _addFavorite(productId);
    }
  }

  /// Adiciona um produto aos favoritos
  Future<void> _addFavorite(String productId) async {
    try {
      final user = _supabase.auth.currentUser;

      // Adicionar localmente primeiro
      _favoriteIds.add(productId);
      notifyListeners();
      await _saveToCache();

      // Se estiver autenticado, salvar no Supabase
      if (user != null) {
        try {
          await _supabase.from('favoritos').insert({
            'user_id': user.id,
            'produto_id': int.parse(productId),
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint('Erro ao salvar favorito no Supabase: $e');
          // Mantém no cache mesmo se falhar no Supabase
        }
      }
    } catch (e) {
      debugPrint('Erro ao adicionar favorito: $e');
      _favoriteIds.remove(productId);
      notifyListeners();
    }
  }

  /// Remove um produto dos favoritos
  Future<void> _removeFavorite(String productId) async {
    try {
      final user = _supabase.auth.currentUser;

      // Remover localmente primeiro
      _favoriteIds.remove(productId);
      notifyListeners();
      await _saveToCache();

      // Se estiver autenticado, remover do Supabase
      if (user != null) {
        try {
          await _supabase
              .from('favoritos')
              .delete()
              .eq('user_id', user.id)
              .eq('produto_id', int.parse(productId));
        } catch (e) {
          debugPrint('Erro ao remover favorito do Supabase: $e');
          // Mantém removido do cache mesmo se falhar no Supabase
        }
      }
    } catch (e) {
      debugPrint('Erro ao remover favorito: $e');
      _favoriteIds.add(productId);
      notifyListeners();
    }
  }

  /// Salva favoritos no cache local
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = jsonEncode(_favoriteIds.toList());
      await prefs.setString('favorites', favoritesJson);
    } catch (e) {
      debugPrint('Erro ao salvar favoritos no cache: $e');
    }
  }

  /// Carrega favoritos do cache local
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = prefs.getString('favorites');

      if (favoritesJson != null) {
        final List<dynamic> favoritesList = jsonDecode(favoritesJson);
        _favoriteIds.clear();
        _favoriteIds.addAll(favoritesList.cast<String>());
        _isLoaded = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao carregar favoritos do cache: $e');
    }
  }

  /// Limpa todos os favoritos
  Future<void> clearFavorites() async {
    _favoriteIds.clear();
    await _saveToCache();
    notifyListeners();
  }
}

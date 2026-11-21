import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import '../screens/product_detail_screen.dart';
import '../utils/product_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late AppLinks _appLinks;
  BuildContext? _context;
  StreamSubscription<Uri>? _subscription;
  VoidCallback? onPasswordRecovery;
  String? _lastAuthLink;

  void init(BuildContext context) {
    _context = context;
    _appLinks = AppLinks();
    _listenForDeepLinks();
  }

  void _listenForDeepLinks() {
    // Escutar deep links quando o app já está aberto
    _subscription?.cancel();
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Erro ao processar deep link: $err');
      },
    );
  }

  Future<void> checkInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        _handleDeepLink(uri);
      }
    } catch (e) {
      debugPrint('Erro ao verificar link inicial: $e');
    }
  }

  void _handleDeepLink(Uri uri) async {
    debugPrint('Link recebido: ${uri.host}${uri.path}');

    if (await _handleAuthCallback(uri)) {
      return;
    }

    final productId = ProductLinks.productIdFrom(uri);
    if (productId != null) await _openProduct(productId);
  }

  Future<bool> _handleAuthCallback(Uri uri) async {
    final isAuth =
        uri.scheme == 'carrodasdelicias' &&
        (uri.host == 'login-callback' || uri.host == 'auth-callback');
    if (!isAuth) return false;
    if (_lastAuthLink == uri.toString()) return true;
    _lastAuthLink = uri.toString();
    Map<String, String> fragment;
    try {
      fragment = Uri.splitQueryString(uri.fragment);
    } catch (_) {
      fragment = {};
    }
    final type = uri.queryParameters['type'] ?? fragment['type'];
    final tokenHash = uri.queryParameters['token_hash'];
    try {
      if (tokenHash != null) {
        await Supabase.instance.client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: type == 'recovery' ? OtpType.recovery : OtpType.email,
        );
      } else {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      }
      if (type == 'recovery' &&
          Supabase.instance.client.auth.currentSession != null) {
        onPasswordRecovery?.call();
      }
    } catch (_) {
      _lastAuthLink = null;
      if (_context?.mounted == true) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text(
              'O link expirou ou já foi utilizado. Solicite um novo email.',
            ),
          ),
        );
      }
    }
    // Este serviço é o único responsável por trocar os códigos de links de auth.
    return true;
  }

  Future<void> _openProduct(String produtoId) async {
    if (_context == null || !_context!.mounted) {
      debugPrint('Contexto não disponível para abrir produto');
      return;
    }

    try {
      // Buscar produto do Supabase
      final response = await Supabase.instance.client
          .from('produtos')
          .select('''
            *,
            categorias:categoria_id (
              id,
              nome,
              icone
            )
          ''')
          .eq('id', produtoId)
          .single();

      if (_context!.mounted) {
        // Formatar dados do produto
        final produto = Map<String, dynamic>.from(response);
        if (produto['categorias'] != null) {
          produto['categoria_nome'] = produto['categorias']['nome'];
          produto['categoria_icone'] = produto['categorias']['icone'];
        }

        // Navegar para a tela de detalhes do produto
        Navigator.of(_context!).push(
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(produto: produto),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao buscar produto: $e');
      if (_context != null && _context!.mounted) {
        ScaffoldMessenger.of(_context!).showSnackBar(
          const SnackBar(
            content: Text('Produto não encontrado'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void updateContext(BuildContext context) {
    _context = context;
  }
}

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import '../screens/product_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late AppLinks _appLinks;
  BuildContext? _context;

  void init(BuildContext context) {
    _context = context;
    _appLinks = AppLinks();
    _listenForDeepLinks();
  }

  void _listenForDeepLinks() {
    // Escutar deep links quando o app já está aberto
    _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Erro ao processar deep link: $err');
    });
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
    debugPrint('Deep link recebido: $uri');

    // Verificar se é um link de produto: https://carrodasdelicias.app/produto/[id]
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'produto') {
      final produtoId = uri.pathSegments[1];
      await _openProduct(produtoId);
    }
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/form_dialogs.dart';
import '../widgets/edit_product_dialog.dart';
import '../widgets/category_icon_widget.dart';
import '../widgets/favorite_heart_animation.dart';
import '../widgets/app_menu.dart';
import '../utils/custom_fab_location.dart';
import '../utils/constants.dart';
import '../services/favorites_service.dart';
import '../services/cart_service.dart';
import '../services/fuzzy_search_service.dart';
import '../widgets/main_navigation_provider.dart';
import 'product_detail_screen.dart';

// CurrencyInputFormatter para formatação de preços
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (newText.isEmpty) {
      return const TextEditingValue(
        text: 'R\$ 0,00',
        selection: TextSelection.collapsed(offset: 7),
      );
    }

    double value = double.parse(newText) / 100;
    String formatted = 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool isGuestMode;

  const HomeScreen({super.key, this.isGuestMode = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode();
  final _searchQueryNotifier = ValueNotifier<String>('');
  final _selectedCategoryNotifier = ValueNotifier<String>('Todos');
  Timer? _searchDebounce;

  // Getters para compatibilidade
  String get _searchQuery => _searchQueryNotifier.value;
  String get _selectedCategory => _selectedCategoryNotifier.value;

  // Cache para resultados filtrados
  List<Map<String, dynamic>>? _cachedFilteredProducts;
  String _lastSearchQuery = '';
  String _lastSelectedCategory = '';

  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, dynamic>> _categorias = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _isOfflineMode = false;
  bool _adminStatusChecked = false;
  bool _hasScrolledDown = false; // Flag para controlar primeira rolagem
  final _favoritesService = FavoritesService();
  final _cartService = CartService();
  RealtimeChannel? _productsChannel;
  late final AudioPlayer _audioPlayer;

  // Referência centralizada ao mapa de overrides de ícones
  static const Map<String, String> _categoryIconOverrides =
      CategoryIconWidget.categoryIconOverrides;

  // Getter para categorias com favoritos dinâmico
  List<Map<String, dynamic>> get _categoriasComFavoritos {
    final categorias = List<Map<String, dynamic>>.from(_categorias);

    // Adicionar categoria Favoritos se o usuário tiver favoritos
    if (_favoritesService.totalFavorites > 0) {
      categorias.insert(0, {
        'nome': 'Favoritos',
        'icone': '❤️',
        'id': 'favoritos',
      });
    }

    return categorias;
  }

  // Debug helper - só funciona em debug mode
  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[HomeScreen] $message');
    }
  }

  // Verifica se o erro é de conexão de rede
  bool _isConnectionError(dynamic error) {
    if (error == null) return false;
    final errorString = error.toString().toLowerCase();
    return errorString.contains('socketexception') ||
        errorString.contains('no route to host') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timed out') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('errno = 113') ||
        errorString.contains('errno = 111') ||
        errorString.contains('clientexception');
  }

  // Mostra snackbar de erro de conexão
  void _showConnectionErrorSnackbar() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sem conexão com o servidor. Verifique sua internet.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Tentar novamente',
            textColor: Colors.white,
            onPressed: _refreshData,
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Verificar se consegue conectar com o Supabase
  Future<bool> _checkSupabaseConnection() async {
    try {
      _debugLog('🔍 Testando conectividade com Supabase...');
      final supabase = Supabase.instance.client;

      // Tentar uma consulta simples com timeout mais rápido
      await supabase
          .from('categorias')
          .select('count')
          .limit(1)
          .timeout(const Duration(seconds: 3));

      _debugLog('✅ Conectividade OK - dados online disponíveis');
      return true;
    } catch (e) {
      _debugLog('❌ Falha na conectividade: $e');
      _debugLog('🔧 Possíveis causas: DNS, firewall, ou rede indisponível');
      return false;
    }
  }

  // Mostrar erro de conectividade sem dados fictícios
  void _showConnectivityError() {
    _debugLog('❌ Sem conectividade - não carregando dados fictícios');

    if (mounted) {
      setState(() {
        _categorias = [];
        _produtos = [];
        _isLoading = false;
        _isOfflineMode = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sem conexão com a internet. Verifique sua conexão.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Tentar novamente',
            textColor: Colors.white,
            onPressed: _loadData,
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    // Configurar volume máximo
    _audioPlayer.setVolume(1.0);
    _searchController.addListener(_onSearchChanged);

    // Invalidar cache quando categoria muda
    _selectedCategoryNotifier.addListener(_onCategoryChanged);

    // Carregar favoritos e escutar mudanças
    _favoritesService.addListener(_onFavoritesChanged);
    _favoritesService.loadFavorites();

    // Carregar dados após um pequeno delay para garantir que o widget esteja pronto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _setupRealtimeSubscription();
    });
  }

  void _setupRealtimeSubscription() {
    try {
      final supabase = Supabase.instance.client;

      Timer? debounceTimer;

      // Criar canal de subscription para produtos
      _productsChannel = supabase
          .channel('produtos-changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'produtos',
            callback: (payload) {
              debugPrint(
                '🔄 Atualização em tempo real detectada: ${payload.eventType}',
              );

              // Debounce para evitar múltiplas recargas
              debounceTimer?.cancel();
              debounceTimer = Timer(const Duration(milliseconds: 500), () {
                // Recarregar dados preservando posição do scroll
                if (mounted) {
                  debugPrint(
                    '📥 Recarregando dados após atualização em tempo real',
                  );
                  _loadData(preserveScrollPosition: true);
                }
              });
            },
          )
          .subscribe();

      debugPrint('✅ Subscription de tempo real configurada');
    } catch (e) {
      debugPrint('❌ Erro ao configurar subscription: $e');
    }
  }

  void _onFavoritesChanged() {
    // Invalidar cache e forçar rebuild quando favoritos mudarem
    if (mounted) {
      setState(() {
        _cachedFilteredProducts = null;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Só verificar admin status se não estiver carregando para evitar interferir com scroll
    if (!_isLoading) {
      _checkAdminStatus();
    }
  }

  Future<void> _checkAdminStatus() async {
    if (!widget.isGuestMode && !_isLoading && !_adminStatusChecked) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        try {
          final response = await Supabase.instance.client
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .single();

          if (mounted && !_isLoading) {
            final newAdminStatus = response['role'] == 'admin';
            // Só fazer setState se o status realmente mudou
            if (_isAdmin != newAdminStatus) {
              setState(() {
                _isAdmin = newAdminStatus;
                _adminStatusChecked = true;
              });
            } else {
              _adminStatusChecked = true;
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Erro ao verificar status admin: $e');
          }
          _adminStatusChecked =
              true; // Marcar como verificado mesmo em caso de erro
        }
      } else {
        _adminStatusChecked = true; // Marcar como verificado se não há usuário
      }
    }
  }

  void _onCategoryChanged() {
    _cachedFilteredProducts = null; // Invalidar cache para forçar rebuild
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    _selectedCategoryNotifier.dispose();
    _favoritesService.removeListener(_onFavoritesChanged);
    _productsChannel?.unsubscribe();
    super.dispose();
  }

  void _onSearchChanged() {
    // Cancelar timer anterior se existir
    _searchDebounce?.cancel();

    // Criar novo timer com delay de 150ms para resposta mais rápida
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        // Atualizar apenas o valor da busca sem setState - mantém o foco!
        _searchQueryNotifier.value = _searchController.text;
      }
    });
  }

  Future<void> _loadData({bool preserveScrollPosition = false}) async {
    // Salvar posição atual do scroll apenas se solicitado
    double? currentScrollPosition;
    if (preserveScrollPosition && _scrollController.hasClients) {
      currentScrollPosition = _scrollController.position.pixels;
    }

    setState(() {
      _isLoading = true;
      _produtos.clear(); // Limpar produtos existentes
      _cachedFilteredProducts = null; // Invalidar cache
    });

    // Verificar conectividade primeiro
    final hasConnection = await _checkSupabaseConnection();

    if (!hasConnection) {
      _debugLog('⚠️ Sem conectividade - mostrando erro');
      _showConnectivityError();
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      _debugLog('🔄 Iniciando carregamento de dados...');

      // Executar todas as operações em paralelo para melhorar performance
      final futures = <Future<dynamic>>[];

      // 1. Verificação de admin (não bloqueia o carregamento)
      if (!widget.isGuestMode) {
        final user = supabase.auth.currentUser;
        if (user != null) {
          futures.add(
            supabase
                .from('profiles')
                .select('role')
                .eq('id', user.id)
                .single()
                .catchError((e) => {'role': 'user'}), // fallback
          );
        } else {
          futures.add(Future.value({'role': 'user'}));
        }
      } else {
        futures.add(Future.value({'role': 'user'}));
      }

      // 2. Carregar categorias (com fallback mais robusto)
      futures.add(
        supabase
            .from('categorias')
            .select('*')
            .order('ordem', ascending: true)
            .then((data) => data as List<dynamic>)
            .catchError((e) {
              _debugLog('⚠️ Erro ao carregar categorias: $e');
              return <dynamic>[];
            }),
      );

      // 3. Carregar todos os produtos com categoria (sem paginação)
      futures.add(
        supabase
            .from('produtos')
            .select('''
              *,
              categorias!inner(
                id,
                nome,
                icone
              )
            ''')
            .eq('ativo', true)
            .order('created_at', ascending: false)
            .then((data) => data as List<dynamic>)
            .catchError((e) {
              _debugLog('⚠️ Erro ao carregar produtos: $e');
              return <dynamic>[];
            }),
      );

      // Executar todas as consultas em paralelo
      _debugLog('📡 Executando consultas ao banco...');
      final results = await Future.wait(futures);
      _debugLog('✅ Consultas concluídas!');

      // Se chegou aqui, a conectividade foi restaurada
      _isOfflineMode = false;

      // Processar resultados
      if (!widget.isGuestMode) {
        final profileResult = results[0] as Map<String, dynamic>;
        _isAdmin = profileResult['role'] == 'admin';
        _debugLog('👤 Role do usuário: ${profileResult['role']}');
      }

      final categoriasResponse = results[1] as List<dynamic>;
      final produtosResponse = results[2] as List<dynamic>;

      _debugLog('📂 Categorias encontradas: ${categoriasResponse.length}');
      _debugLog('🍰 Produtos encontrados: ${produtosResponse.length}');

      if (categoriasResponse.isNotEmpty) {
        _debugLog('📂 Primeira categoria: ${categoriasResponse[0]}');
      }
      if (produtosResponse.isNotEmpty) {
        _debugLog('🍰 Primeiro produto: ${produtosResponse[0]}');
      }

      // Configurar categorias com fallback otimizado
      if (categoriasResponse.isNotEmpty) {
        // Usar a ordem do banco de dados (campo 'ordem')
        List<Map<String, dynamic>> sortedCategorias =
            List<Map<String, dynamic>>.from(categoriasResponse);
        // As categorias já vêm ordenadas do banco pela query .order('ordem', ascending: true)

        // Aplicar overrides de ícones customizados (apenas se o banco não tem ícone definido)
        for (int i = 0; i < sortedCategorias.length; i++) {
          final nome = sortedCategorias[i]['nome'];
          final iconeAtual = sortedCategorias[i]['icone'];
          final iconeVazio =
              iconeAtual == null || iconeAtual.toString().isEmpty;
          if (iconeVazio && _categoryIconOverrides.containsKey(nome)) {
            sortedCategorias[i] = {
              ...sortedCategorias[i],
              'icone': _categoryIconOverrides[nome],
            };
          } else if (iconeAtual != null &&
              iconeAtual.toString().startsWith('asset:') == false &&
              _categoryIconOverrides.containsKey(nome)) {
            // Se o banco tem um emoji, NÃO sobrescrever - o emoji do admin prevalece
          } else if (iconeVazio) {
            // Categoria sem override e sem ícone - usar default
            sortedCategorias[i] = {
              ...sortedCategorias[i],
              'icone': 'asset:assets/icons/todos_category.svg',
            };
          }
        }

        _categorias = [
          {
            'id': 0,
            'nome': 'Todos',
            'icone': 'asset:assets/icons/todos_category.svg',
          },
          ...sortedCategorias,
        ];
      } else {
        // Se não há categorias no banco, usar apenas "Todos"
        _categorias = [
          {
            'id': 0,
            'nome': 'Todos',
            'icone': 'asset:assets/icons/todos_category.svg',
          },
        ];
        _debugLog('📂 Nenhuma categoria encontrada no banco');
      }

      // Processar produtos com informações da categoria
      if (produtosResponse.isNotEmpty) {
        _produtos = produtosResponse.map<Map<String, dynamic>>((produto) {
          final categoria = produto['categorias'];
          if (categoria != null) {
            final categoriaNome = categoria['nome'] as String?;
            String? categoriaIcone = categoria['icone'];
            // Aplicar override de ícone apenas se o banco não tem ícone definido
            if ((categoriaIcone == null || categoriaIcone.isEmpty) &&
                categoriaNome != null &&
                _categoryIconOverrides.containsKey(categoriaNome)) {
              categoriaIcone = _categoryIconOverrides[categoriaNome];
            }
            return {
              ...produto,
              'categoria_nome': categoriaNome,
              'categoria_icone': categoriaIcone,
            };
          } else {
            // Fallback se não há categoria associada
            return {
              ...produto,
              'categoria_nome': 'Outros',
              'categoria_icone': '🍰',
            };
          }
        }).toList();

        _debugLog('📊 Produtos processados com categorias:');
        for (int i = 0; i < _produtos.length && i < 3; i++) {
          _debugLog(
            '  • ${_produtos[i]['nome']} → ${_produtos[i]['categoria_nome']}',
          );
        }
      } else {
        // Se não há produtos no banco, deixar vazio
        _produtos = [];
        _debugLog('📭 Nenhum produto encontrado no banco de dados');
      }

      _debugLog('🎉 Carregamento concluído com sucesso!');
      _debugLog('📊 Total de produtos carregados: ${_produtos.length}');
      _debugLog('📂 Total de categorias carregadas: ${_categorias.length}');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _adminStatusChecked =
              true; // Marcar admin status como verificado após carregamento inicial
        });

        // Restaurar posição do scroll apenas se foi solicitado e existe
        if (preserveScrollPosition &&
            currentScrollPosition != null &&
            currentScrollPosition > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients && mounted) {
              _scrollController.jumpTo(currentScrollPosition!);
            }
          });
        }
      }
    } catch (error) {
      _debugLog('❌ Erro ao carregar dados: $error');
      _debugLog('🔍 Tipo do erro: ${error.runtimeType}');

      // Verificar se é erro de conexão
      final isConnError = _isConnectionError(error);

      if (mounted) {
        setState(() {
          _categorias = [];
          _produtos = [];
          _isLoading = false;
          _isOfflineMode = true;
        });

        if (isConnError) {
          _showConnectionErrorSnackbar();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Erro: ${error.toString().substring(0, error.toString().length > 100 ? 100 : error.toString().length)}',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Tentar novamente',
                textColor: Colors.white,
                onPressed: _loadData,
              ),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      }
    }
  }

  // Método de refresh que recarrega completamente os dados
  Future<void> _refreshData() async {
    // Só fazer refresh se não estiver carregando
    if (_isLoading) {
      return;
    }

    debugPrint('🔄 Refresh manual iniciado');

    // Recarregar todos os dados do zero
    await _loadData();

    debugPrint('✅ Refresh manual concluído');
  }

  List<Map<String, dynamic>> get _filteredProducts {
    // Verificar se precisa reprocessar o cache
    if (_cachedFilteredProducts == null ||
        _lastSearchQuery != _searchQuery ||
        _lastSelectedCategory != _selectedCategory) {
      _debugLog(
        '🔍 Filtrando produtos: busca="$_searchQuery", categoria="$_selectedCategory"',
      );

      // Primeiro, filtrar por categoria
      var categoryFiltered = _produtos.where((produto) {
        if (_selectedCategory == 'Todos') return true;
        if (_selectedCategory == 'Favoritos') {
          final productId = produto['id'].toString();
          return _favoritesService.isFavorite(productId);
        }
        return produto['categoria_nome'] == _selectedCategory;
      }).toList();

      // Depois, aplicar busca fuzzy inteligente
      if (_searchQuery.isNotEmpty) {
        _cachedFilteredProducts = FuzzySearchService.searchProducts(
          categoryFiltered,
          _searchQuery,
        );
      } else {
        _cachedFilteredProducts = categoryFiltered;
      }

      // Atualizar cache
      _lastSearchQuery = _searchQuery;
      _lastSelectedCategory = _selectedCategory;
    }

    return _cachedFilteredProducts!;
  }

  List<Map<String, dynamic>> get _maisVendidos {
    var produtos = _produtos.where((p) => p['mais_vendido'] == true);

    // Filtrar por categoria se não for 'Todos' e não for 'Favoritos'
    if (_selectedCategory != 'Todos' && _selectedCategory != 'Favoritos') {
      produtos = produtos.where(
        (p) => p['categoria_nome'] == _selectedCategory,
      );
    }

    return produtos.take(5).toList();
  }

  List<Map<String, dynamic>> get _novidades {
    var produtos = _produtos.where((p) => p['novidade'] == true);

    // Filtrar por categoria se não for 'Todos' e não for 'Favoritos'
    if (_selectedCategory != 'Todos' && _selectedCategory != 'Favoritos') {
      produtos = produtos.where(
        (p) => p['categoria_nome'] == _selectedCategory,
      );
    }

    return produtos.take(5).toList();
  }

  List<Map<String, dynamic>> _getProdutosEmDestaque() {
    // Produtos em destaque são os que são novidades OU mais vendidos
    var produtos = _produtos.where(
      (p) => p['novidade'] == true || p['mais_vendido'] == true,
    );

    // Filtrar por categoria se não for 'Todos' e não for 'Favoritos'
    if (_selectedCategory != 'Todos' && _selectedCategory != 'Favoritos') {
      produtos = produtos.where(
        (p) => p['categoria_nome'] == _selectedCategory,
      );
    }

    return produtos.take(5).toList();
  }

  String _getCategoryIcon(String categoryName) {
    final category = _categorias.firstWhere(
      (cat) => cat['nome'] == categoryName,
      orElse: () => {'icone': '🍰'},
    );
    return category['icone'] ?? '🍰';
  }

  /// Constrói o widget do ícone de categoria (suporta SVG asset, PNG asset, URL de imagem e emoji)
  Widget _buildCategoryIconWidget(String? icone, {double size = 24}) {
    if (icone == null) return const SizedBox.shrink();
    if (icone.startsWith('asset:')) {
      final assetPath = icone.replaceFirst('asset:', '');
      if (assetPath.endsWith('.svg')) {
        return SvgPicture.asset(assetPath, width: size, height: size);
      } else {
        return Image.asset(assetPath, width: size, height: size);
      }
    } else if (icone.startsWith('http')) {
      return Image.network(
        icone,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, size: 16),
      );
    } else {
      return Text(icone, style: TextStyle(fontSize: size * 0.67));
    }
  }

  // Constrói as seções especiais (Destaque, Mais Vendidos, Novidades)
  List<Widget> _buildSpecialSections() {
    final List<Widget> slivers = [];

    // Seção de Produtos em Destaque
    if (_getProdutosEmDestaque().isNotEmpty) {
      slivers.addAll([
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '⭐ Produtos em Destaque',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 280,
            child: _getProdutosEmDestaque().length == 1
                ? Center(
                    child: SizedBox(
                      width: 200,
                      child: _buildProductCard(
                        _getProdutosEmDestaque()[0],
                        tipo: 'destaque',
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _getProdutosEmDestaque().length,
                    itemBuilder: (context, index) {
                      final produtos = _getProdutosEmDestaque();
                      if (index >= produtos.length) {
                        return const SizedBox.shrink();
                      }
                      final produto = produtos[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index == _getProdutosEmDestaque().length - 1
                              ? 0
                              : 8,
                        ),
                        child: SizedBox(
                          width: 200,
                          child: _buildProductCard(produto, tipo: 'destaque'),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]);
    }

    // Seção de Mais Vendidos
    if (_maisVendidos.isNotEmpty) {
      slivers.addAll([
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              '🔥 Mais Vendidos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 280,
            child: _maisVendidos.length == 1
                ? Center(
                    child: SizedBox(
                      width: 200,
                      child: _buildProductCard(
                        _maisVendidos[0],
                        tipo: 'vendidos',
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _maisVendidos.length,
                    itemBuilder: (context, index) {
                      if (index >= _maisVendidos.length) {
                        return const SizedBox.shrink();
                      }
                      final produto = _maisVendidos[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index == _maisVendidos.length - 1 ? 0 : 8,
                        ),
                        child: SizedBox(
                          width: 200,
                          child: _buildProductCard(produto, tipo: 'vendidos'),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]);
    }

    // Seção Novidades
    if (_novidades.isNotEmpty) {
      slivers.addAll([
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(
              '✨ Novidades',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 280,
            child: _novidades.length == 1
                ? Center(
                    child: SizedBox(
                      width: 200,
                      child: _buildProductCard(
                        _novidades[0],
                        tipo: 'novidades',
                      ),
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _novidades.length,
                    itemBuilder: (context, index) {
                      if (index >= _novidades.length) {
                        return const SizedBox.shrink();
                      }
                      final produto = _novidades[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index == _novidades.length - 1 ? 0 : 8,
                        ),
                        child: SizedBox(
                          width: 200,
                          child: _buildProductCard(produto, tipo: 'novidades'),
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]);
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: _isOfflineMode ? 'Início (Offline)' : 'Início',
      showBackButton: false,
      padding: EdgeInsets.zero,
      actions: [
        AppMenu(
          isGuestMode: widget.isGuestMode,
          isAdmin: _isAdmin,
          onAdminReturn: _refreshData,
        ),
      ],
      floatingActionButton: (!widget.isGuestMode && _isAdmin)
          ? FloatingActionButton(
              onPressed: _showAddOptionsDialog,
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              child: Image.asset(
                'assets/icons/menu/add_button.png',
                width: 24,
                height: 24,
                color: Colors.white,
              ),
            )
          : null,
      floatingActionButtonLocation: const CustomFabLocation(),
      child: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Carregando delícias...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('🍰', style: TextStyle(fontSize: 32)),
                ],
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                // Marcar que o usuário já rolou a tela (sem setState para evitar rebuild)
                if (scrollInfo.metrics.pixels > 100 && !_hasScrolledDown) {
                  _hasScrolledDown = true;
                }
                return false; // Permitir que outras notificações continuem
              },
              child: Builder(
                builder: (context) {
                  return RefreshIndicator(
                    onRefresh: _refreshData,
                    displacement: 80.0,
                    edgeOffset: 0.0,
                    strokeWidth: 2.0,
                    backgroundColor: Colors.white,
                    color: Colors.black,
                    child: CustomScrollView(
                      key: const PageStorageKey<String>('homeScrollView'),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Barra de pesquisa
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              decoration: InputDecoration(
                                hintText: 'Buscar produtos...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: ValueListenableBuilder<String>(
                                  valueListenable: _searchQueryNotifier,
                                  builder: (context, searchQuery, child) {
                                    return searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              _searchController.clear();
                                              _searchQueryNotifier.value = '';
                                            },
                                          )
                                        : const SizedBox.shrink();
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Filtro de categorias - reativo sem rebuild completo
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 50,
                            child: ValueListenableBuilder<String>(
                              valueListenable: _selectedCategoryNotifier,
                              builder: (context, selectedCategory, child) {
                                return ListView.builder(
                                  addRepaintBoundaries: true,
                                  key: const PageStorageKey<String>(
                                    'categoriesListView',
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: _categoriasComFavoritos.length,
                                  itemBuilder: (context, index) {
                                    if (index >=
                                        _categoriasComFavoritos.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final categoria =
                                        _categoriasComFavoritos[index];
                                    final isSelected =
                                        selectedCategory == categoria['nome'];

                                    // Pular categoria 'Todos' e 'Favoritos' para long press admin
                                    final isSystemCategory =
                                        categoria['nome'] == 'Todos' ||
                                        categoria['nome'] == 'Favoritos';

                                    final filterChip = FilterChip(
                                      label: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth:
                                              120, // Limitar largura máxima
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (categoria['icone'] != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 4,
                                                ),
                                                child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: Center(
                                                    child:
                                                        _buildCategoryIconWidget(
                                                          categoria['icone'],
                                                          size: 18,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            Flexible(
                                              child: Text(
                                                categoria['nome'],
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      selected: isSelected,
                                      onSelected: (bool selected) {
                                        // Atualizar categoria sem setState para manter posição do scroll
                                        _selectedCategoryNotifier.value =
                                            categoria['nome'];
                                      },
                                      backgroundColor: Colors.grey[200],
                                      selectedColor: Colors.black,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.black,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    );

                                    // Adicionar long press para admin em categorias do banco
                                    if (!isSystemCategory && _isAdmin) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        child: GestureDetector(
                                          onLongPress: () =>
                                              _showCategoryAdminOptions(
                                                categoria,
                                              ),
                                          child: filterChip,
                                        ),
                                      );
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: filterChip,
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // Seções de produtos especiais - reativas à categoria e busca
                        ValueListenableBuilder<String>(
                          valueListenable: _searchQueryNotifier,
                          builder: (context, searchQuery, child) {
                            return ValueListenableBuilder<String>(
                              valueListenable: _selectedCategoryNotifier,
                              builder: (context, selectedCategory, child) {
                                // Não mostrar seções em Favoritos ou durante busca
                                if (searchQuery.isNotEmpty ||
                                    selectedCategory == 'Favoritos') {
                                  return const SliverToBoxAdapter(
                                    child: SizedBox.shrink(),
                                  );
                                }

                                // Retornar seções especiais como MultiSliver
                                final slivers = _buildSpecialSections();
                                if (slivers.isEmpty) {
                                  return const SliverToBoxAdapter(
                                    child: SizedBox.shrink(),
                                  );
                                }

                                // Usar SliverMainAxisGroup para agrupar múltiplos slivers
                                return SliverMainAxisGroup(slivers: slivers);
                              },
                            );
                          },
                        ),

                        // Título da seção principal - reativo à categoria
                        SliverToBoxAdapter(
                          child: ValueListenableBuilder<String>(
                            valueListenable: _selectedCategoryNotifier,
                            builder: (context, selectedCategory, child) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_searchQuery.isNotEmpty) ...[
                                      const Text(
                                        '🔍 ',
                                        style: TextStyle(fontSize: 20),
                                      ),
                                      const Text(
                                        'Resultados da busca',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ] else if (selectedCategory == 'Todos') ...[
                                      _buildCategoryIconWidget(
                                        _getCategoryIcon('Todos'),
                                        size: 28,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Todos os Produtos',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ] else if (selectedCategory ==
                                        'Favoritos') ...[
                                      const Text(
                                        '❤️ ',
                                        style: TextStyle(fontSize: 20),
                                      ),
                                      const Text(
                                        'Favoritos',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ] else ...[
                                      _buildCategoryIconWidget(
                                        _getCategoryIcon(selectedCategory),
                                        size: 24,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        selectedCategory,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 12)),

                        // Lista de produtos filtrados - reativo à busca E categoria
                        ValueListenableBuilder<String>(
                          valueListenable: _searchQueryNotifier,
                          builder: (context, searchQuery, child) {
                            return ValueListenableBuilder<String>(
                              valueListenable: _selectedCategoryNotifier,
                              builder: (context, selectedCategory, child) {
                                return _filteredProducts.isEmpty
                                    ? SliverToBoxAdapter(
                                        child: Center(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 32,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                const SizedBox(height: 60),
                                                Icon(
                                                  _isOfflineMode
                                                      ? Icons.wifi_off
                                                      : _searchQuery.isNotEmpty
                                                      ? Icons.search_off
                                                      : Icons
                                                            .shopping_cart_outlined,
                                                  size: 64,
                                                  color: _isOfflineMode
                                                      ? Colors.red
                                                      : Colors.grey,
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  _isOfflineMode
                                                      ? 'Sem conexão'
                                                      : _searchQuery.isNotEmpty
                                                      ? 'Nenhum produto encontrado'
                                                      : 'Nenhum produto nesta categoria',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.headlineSmall,
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  _isOfflineMode
                                                      ? 'Verifique sua conexão com a internet'
                                                      : _searchQuery.isNotEmpty
                                                      ? 'Tente buscar por outro termo'
                                                      : 'Produtos serão adicionados em breve!',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                if (_isOfflineMode) ...[
                                                  const SizedBox(height: 16),
                                                  ElevatedButton.icon(
                                                    onPressed: _loadData,
                                                    icon: const Icon(
                                                      Icons.refresh,
                                                    ),
                                                    label: const Text(
                                                      'Tentar novamente',
                                                    ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.blue,
                                                          foregroundColor:
                                                              Colors.white,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : SliverList(
                                        delegate: SliverChildBuilderDelegate((
                                          context,
                                          index,
                                        ) {
                                          // Proteção contra índice fora do range durante rebuilds
                                          if (index >=
                                              _filteredProducts.length) {
                                            return const SizedBox.shrink();
                                          }

                                          final produto =
                                              _filteredProducts[index];
                                          return RepaintBoundary(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 6,
                                                  ),
                                              child: AnimatedProductCard(
                                                produto: produto,
                                                onTap: widget.isGuestMode
                                                    ? () =>
                                                          _onProductTap(produto)
                                                    : null, // Usar comportamento padrão se não for guest mode
                                                onProductDeleted: _refreshData,
                                                isAdmin:
                                                    _isAdmin, // Passar status de admin explicitamente
                                              ),
                                            ),
                                          );
                                        }, childCount: _filteredProducts.length),
                                      );
                              },
                            );
                          },
                        ),

                        // Espaço extra no final
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _onProductTap(Map<String, dynamic> produto) async {
    if (widget.isGuestMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Faça login para interagir com produtos'),
          action: SnackBarAction(
            label: 'Login',
            textColor: Colors.green,
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/auth',
                (route) => false,
              );
            },
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      // Navegar para a tela de detalhes do produto
      try {
        debugPrint('🔗 Navegando para detalhes do produto: ${produto['nome']}');
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(produto: produto),
          ),
        );
        if (result == 'go_to_cart' && mounted) {
          final provider = MainNavigationProvider.of(context);
          provider?.navigateToPageDirect?.call(4);
        }
      } catch (e) {
        debugPrint('❌ Erro ao navegar para detalhes: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao abrir detalhes do produto: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showAdminOptions(Map<String, dynamic> produto) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                produto['nome'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Editar Produto'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditProductDialog(produto);
                },
              ),
              const Divider(),
              ListTile(
                leading: Image.asset(
                  'assets/icons/menu/delete_button.png',
                  width: 24,
                  height: 24,
                  color: Colors.black,
                ),
                title: const Text('Excluir Produto'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(produto);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditProductDialog(Map<String, dynamic> produto) async {
    try {
      // Buscar categorias do Supabase
      final response = await Supabase.instance.client
          .from('categorias')
          .select()
          .order('ordem', ascending: true);

      final categorias = List<Map<String, dynamic>>.from(response);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => EditProductDialog(
          produto: produto,
          categorias: categorias,
          onProductUpdated: () {
            // Recarregar dados
            _refreshData();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Produto atualizado com sucesso!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar categorias: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmation(Map<String, dynamic> produto) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir o produto "${produto['nome']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icons/menu/cancel_button.png',
                  width: 18,
                  height: 18,
                ),
                const SizedBox(width: 4),
                const Text('Cancelar'),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icons/menu/delete_button.png',
                  width: 18,
                  height: 18,
                  color: Colors.black,
                ),
                const SizedBox(width: 4),
                const Text('Excluir'),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteProduct(produto);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> produto) async {
    try {
      await Supabase.instance.client
          .from('produtos')
          .delete()
          .eq('id', produto['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto excluído com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );

        // Recarregar dados
        await _refreshData();
      }
    } catch (e) {
      if (mounted) {
        if (_isConnectionError(e)) {
          _showConnectionErrorSnackbar();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir produto: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showAddOptionsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'O que deseja adicionar?',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          content: const Text(
            'Selecione uma opção para adicionar ao aplicativo:',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showAddProductDialog();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fastfood, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  const Text(
                    'Produto',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showAddCategoryDialog();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/menu/add_category.png',
                    width: 24,
                    height: 24,
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Categoria',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          AddProductDialog(categorias: _categorias, onProductAdded: _loadData),
    );
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AddCategoryDialog(onCategoryAdded: _loadData),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> produto, {String? tipo}) {
    final imagens = produto['imagens'];
    final hasImage = imagens is List && imagens.isNotEmpty;

    // Definir ícone e cor baseado no tipo
    String badgeIcon = '';
    Color badgeColor = Colors.grey;

    if (tipo == 'destaque') {
      badgeIcon = '⭐';
      badgeColor = Colors.amber;
    } else if (tipo == 'vendidos') {
      badgeIcon = '🔥';
      badgeColor = Colors.orange;
    } else if (tipo == 'novidades') {
      badgeIcon = '✨';
      badgeColor = Colors.purple;
    }

    return GestureDetector(
      onTap: () {
        _onProductTap(produto);
      },
      onLongPress: (!widget.isGuestMode && _isAdmin)
          ? () => _showAdminOptions(produto)
          : null,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagem com badge
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: hasImage
                      ? Image.network(
                          imagens[0],
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.orange[100]!,
                                    Colors.pink[100]!,
                                  ],
                                ),
                              ),
                              child: Center(
                                child: CategoryIconWidget(
                                  icone: produto['categoria_icone'],
                                  size: 50,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Colors.orange[100]!, Colors.pink[100]!],
                            ),
                          ),
                          child: Center(
                            child: CategoryIconWidget(
                              icone: produto['categoria_icone'],
                              size: 50,
                            ),
                          ),
                        ),
                ),
                // Botão favorito
                Positioned(
                  top: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () async {
                      final productId = produto['id'].toString();
                      final wasFavorite = _favoritesService.isFavorite(
                        productId,
                      );
                      // Capture overlay before any async gaps
                      final overlay = Overlay.of(context);

                      // Feedback sonoro customizado
                      try {
                        debugPrint('🔊 Tentando reproduzir som de feedback...');
                        if (wasFavorite) {
                          await _audioPlayer.play(
                            AssetSource('sounds/favorite_off.wav'),
                            mode: PlayerMode.lowLatency,
                          );
                        } else {
                          await _audioPlayer.play(
                            AssetSource('sounds/favorite_on.wav'),
                            mode: PlayerMode.lowLatency,
                          );
                        }
                        debugPrint('✅ Comando de som enviado');
                      } catch (e) {
                        debugPrint('❌ Erro ao reproduzir som: $e');
                      }

                      await _favoritesService.toggleFavorite(productId);

                      setState(() {});

                      // Mostrar animação de coração
                      if (mounted) {
                        FavoriteHeartAnimation.showWithOverlay(
                          overlay,
                          isFavoriting: !wasFavorite,
                        );
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              wasFavorite
                                  ? 'Removido dos favoritos'
                                  : 'Adicionado aos favoritos',
                            ),
                            backgroundColor: wasFavorite
                                ? Colors.grey
                                : Colors.pink,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        _favoritesService.isFavorite(produto['id'].toString())
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color:
                            _favoritesService.isFavorite(
                              produto['id'].toString(),
                            )
                            ? Colors.pink
                            : Colors.grey,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                // Badge indicador
                if (tipo != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        badgeIcon,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
              ],
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nome
                    Text(
                      produto['nome'] ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // Descrição
                    if (produto['descricao'] != null &&
                        produto['descricao'].toString().isNotEmpty)
                      Text(
                        produto['descricao'],
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    // Preço
                    _buildProductPrice(produto),
                    const SizedBox(height: 6),
                    // Botões
                    Row(
                      children: [
                        // Botão Comprar (esquerda)
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 32,
                            child: ElevatedButton(
                              onPressed: () {
                                _onProductTap(produto);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shopping_bag, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Comprar',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Botão Adicionar ao Carrinho (direita)
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: OutlinedButton(
                              onPressed: () async {
                                try {
                                  await _cartService.addItem(
                                    produto,
                                    quantidade: 1,
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            const Icon(
                                              Icons.shopping_cart,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${produto['nome']} adicionado!',
                                              ),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: Colors.green,
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 3),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        action: SnackBarAction(
                                          label: 'Ver Carrinho',
                                          textColor: Colors.white,
                                          onPressed: () {
                                            final provider =
                                                MainNavigationProvider.of(
                                                  context,
                                                );
                                            if (provider
                                                    ?.navigateToPageDirect !=
                                                null) {
                                              provider!.navigateToPageDirect!(
                                                4,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro: $e'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: const BorderSide(color: Colors.orange),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Icon(
                                Icons.add_shopping_cart,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Métodos de admin para categorias
  void _showCategoryAdminOptions(Map<String, dynamic> categoria) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child:
                          categoria['icone'] != null &&
                              categoria['icone'].toString().startsWith('asset:')
                          ? _buildCategoryIconWidget(
                              categoria['icone'],
                              size: 24,
                            )
                          : Text(
                              categoria['icone'] ?? '📦',
                              style: const TextStyle(fontSize: 24),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      categoria['nome'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Editar Categoria'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditCategoryDialog(categoria);
                },
              ),
              const Divider(),
              ListTile(
                leading: Image.asset(
                  'assets/icons/menu/delete_button.png',
                  width: 24,
                  height: 24,
                  color: Colors.black,
                ),
                title: const Text('Excluir Categoria'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteCategoryConfirmation(categoria);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showEditCategoryDialog(Map<String, dynamic> categoria) {
    final nomeController = TextEditingController(text: categoria['nome'] ?? '');
    final iconeController = TextEditingController(
      text: categoria['icone'] ?? '',
    );
    bool isAtivo = categoria['ativo'] ?? true;
    final iconeOriginal = categoria['icone'] ?? '📦';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        key: const Key('edit_category_dialog'),
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.purple, Colors.deepPurple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CategoryIconWidget(icone: iconeOriginal, size: 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editar ${categoria['nome']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  // Campo Nome - Obrigatório
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.purple[200]!),
                    ),
                    child: TextField(
                      controller: nomeController,
                      decoration: const InputDecoration(
                        labelText: 'Nome da Categoria',
                        labelStyle: TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: Icon(Icons.category, color: Colors.purple),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                        helperText: 'Obrigatório',
                        helperStyle: TextStyle(color: Colors.purple),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Campo Ícone - Opcional
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: TextField(
                      controller: iconeController,
                      onChanged: (value) {
                        // Atualizar preview quando o valor mudar
                        setDialogState(() {});
                      },
                      style: const TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Ícone (Emoji ou asset)',
                        labelStyle: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CategoryIconWidget(
                              icone: iconeController.text.isEmpty
                                  ? iconeOriginal
                                  : iconeController.text,
                              size: 24,
                            ),
                          ),
                        ),
                        hintText: '🍰 ou asset:assets/icons/icone.svg',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                        helperText:
                            iconeController.text.startsWith('asset:') ||
                                (iconeController.text.isEmpty &&
                                    iconeOriginal.startsWith('asset:'))
                            ? 'Ícone padrão do asset (coloque um emoji para substituir)'
                            : 'Emoji ou caminho do asset',
                        helperStyle: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Preview do ícone
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.preview, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Preview:',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: CategoryIconWidget(
                            icone: iconeController.text.isEmpty
                                ? iconeOriginal
                                : iconeController.text,
                            size: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Configurações da Categoria
                  Container(
                    width: double.infinity,
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
                              Icons.settings,
                              color: Colors.purple,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Configurações',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.purple,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Categoria Ativa',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: isAtivo,
                              activeThumbColor: Colors.purple,
                              onChanged: (value) {
                                setDialogState(() {
                                  isAtivo = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            Row(
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
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nomeController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('O nome da categoria é obrigatório'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      try {
                        final iconeValue = iconeController.text.trim();
                        final updateData = {
                          'nome': nomeController.text.trim(),
                          'icone': iconeValue.isEmpty
                              ? (iconeOriginal.startsWith('asset:')
                                    ? iconeOriginal
                                    : '')
                              : iconeValue,
                          'ativo': isAtivo,
                        };

                        // Garantir que o ID seja int
                        final catId = categoria['id'];
                        final catIdInt = catId is int
                            ? catId
                            : int.parse(catId.toString());

                        debugPrint(
                          '📝 Atualizando categoria ID: $catIdInt com dados: $updateData',
                        );

                        bool updated = false;
                        try {
                          // Tentar update direto primeiro, com .select() para verificar se realmente atualizou
                          final result = await Supabase.instance.client
                              .from('categorias')
                              .update(updateData)
                              .eq('id', catIdInt)
                              .select();
                          debugPrint('📝 Resultado update direto: $result');
                          updated = (result as List).isNotEmpty;
                        } catch (updateError) {
                          debugPrint('❌ Update direto falhou: $updateError');
                        }

                        if (!updated) {
                          debugPrint(
                            '⚠️ Update direto não atualizou - tentando RPC...',
                          );
                          // Fallback: tentar via RPC que bypassa RLS
                          try {
                            await Supabase.instance.client.rpc(
                              'update_categoria_admin',
                              params: {
                                'categoria_id': catIdInt,
                                'novo_nome': updateData['nome'],
                                'novo_icone': updateData['icone'],
                                'novo_ativo': updateData['ativo'],
                              },
                            );
                            debugPrint('✅ Update via RPC bem-sucedido');
                          } catch (rpcError) {
                            debugPrint('❌ RPC update também falhou: $rpcError');
                            final rpcErrorMsg = rpcError
                                .toString()
                                .toLowerCase();
                            if (rpcErrorMsg.contains('function') &&
                                rpcErrorMsg.contains('does not exist')) {
                              debugPrint(
                                '⚠️ Função update_categoria_admin não existe no Supabase!',
                              );
                              throw Exception(
                                'Função de atualização não encontrada no servidor. '
                                'Execute o SQL update_categoria_admin.sql no Supabase.',
                              );
                            }
                            rethrow;
                          }
                        }

                        if (mounted) {
                          navigator.pop();
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Categoria atualizada com sucesso!',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                          _refreshData();
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Erro ao atualizar categoria: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Salvar Alterações'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteCategoryConfirmation(
    Map<String, dynamic> categoria,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          'Tem certeza que deseja excluir a categoria "${categoria['nome']}"?\n\n'
          '⚠️ Produtos associados a esta categoria poderão ficar sem categoria!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icons/menu/cancel_button.png',
                  width: 18,
                  height: 18,
                ),
                const SizedBox(width: 4),
                const Text('Cancelar'),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icons/menu/delete_button.png',
                  width: 18,
                  height: 18,
                  color: Colors.black,
                ),
                const SizedBox(width: 4),
                const Text('Excluir'),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteCategory(categoria);
    }
  }

  Future<void> _deleteCategory(Map<String, dynamic> categoria) async {
    final catId = categoria['id'];
    final catIdInt = catId is int ? catId : int.parse(catId.toString());

    debugPrint(
      '🗑️ [_deleteCategory] Iniciando exclusão - id: $catIdInt, nome: ${categoria['nome']}',
    );

    try {
      // Tentar delete direto primeiro
      debugPrint('🗑️ [_deleteCategory] Tentando delete direto...');
      final deleteResult = await Supabase.instance.client
          .from('categorias')
          .delete()
          .eq('id', catIdInt)
          .select();

      debugPrint(
        '🗑️ [_deleteCategory] Resultado do delete direto: $deleteResult',
      );

      // Se o delete não retornou nada, pode ser que o RLS bloqueou
      if (deleteResult.isEmpty) {
        debugPrint(
          '⚠️ [_deleteCategory] Delete direto retornou vazio - tentando RPC',
        );

        // Fallback: tentar via RPC que bypassa RLS
        try {
          debugPrint(
            '🗑️ [_deleteCategory] Chamando RPC delete_categoria_admin com id: $catIdInt',
          );
          await Supabase.instance.client.rpc(
            'delete_categoria_admin',
            params: {'categoria_id': catIdInt},
          );
          debugPrint('✅ [_deleteCategory] RPC delete bem-sucedido');
        } catch (rpcError) {
          debugPrint('❌ [_deleteCategory] RPC delete falhou: $rpcError');
          final rpcErrorMsg = rpcError.toString().toLowerCase();
          if (rpcErrorMsg.contains('foreign key') ||
              rpcErrorMsg.contains('23503') ||
              rpcErrorMsg.contains('referential integrity')) {
            throw Exception(
              'Não é possível excluir esta categoria porque existem produtos vinculados a ela.',
            );
          }
          // Se há múltiplas funções com o mesmo nome
          if (rpcErrorMsg.contains('could not choose') ||
              rpcErrorMsg.contains('multiple choices')) {
            throw Exception(
              'Erro de configuração no servidor. Contate o administrador.',
            );
          }
          rethrow;
        }
      } else {
        debugPrint('✅ [_deleteCategory] Delete direto bem-sucedido');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Categoria excluída com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        // Resetar categoria selecionada se era a que foi excluída
        if (_selectedCategoryNotifier.value == categoria['nome']) {
          _selectedCategoryNotifier.value = 'Todos';
        }
        _refreshData();
      }
    } catch (e) {
      debugPrint('❌ [_deleteCategory] Erro final: $e');
      if (mounted) {
        if (_isConnectionError(e)) {
          _showConnectionErrorSnackbar();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao excluir categoria: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Widget _buildProductPrice(Map<String, dynamic> produto) {
    final tamanhos = produto['tamanhos'];
    final preco = produto['preco'];
    final precoAnterior = produto['preco_anterior'];

    // Se tem tamanhos, mostrar o menor preço
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      final precos = <double>{};
      for (var tamanho in tamanhos) {
        final precoTamanho = tamanho['preco']?.toDouble() ?? 0.0;
        if (precoTamanho > 0) precos.add(precoTamanho);
      }

      if (precos.isEmpty) {
        return const Text(
          'Sem preço',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        );
      }

      final menorPreco = precos.reduce((a, b) => a < b ? a : b);
      final temMultiplosPrecos = precos.length > 1;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            temMultiplosPrecos ? 'A partir de' : 'Preço',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          Text(
            CurrencyFormatter.format(menorPreco),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      );
    }

    if (preco == null) {
      return const Text(
        'Sem preço',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    final precoAtual = preco.toDouble();
    final hasDesconto = precoAnterior != null && precoAnterior > precoAtual;

    if (hasDesconto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CurrencyFormatter.format(precoAnterior),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(
            CurrencyFormatter.format(precoAtual),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Preço', style: TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          CurrencyFormatter.format(precoAtual),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}

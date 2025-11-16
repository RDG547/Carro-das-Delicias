import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/form_dialogs.dart';
import '../widgets/product_carousel.dart';
import '../widgets/app_menu.dart';
import '../utils/constants.dart';
import '../utils/custom_fab_location.dart';
import '../services/favorites_service.dart';
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
  final _isLoadingMoreNotifier = ValueNotifier<bool>(false);
  bool _isAdmin = false;
  bool _isOfflineMode = false;
  bool _adminStatusChecked = false;
  bool _hasScrolledDown = false; // Flag para controlar primeira rolagem
  final _favoritesService = FavoritesService();

  // Paginação
  static const int _pageSize = 20;
  int _currentPage = 0;
  bool _hasMoreProducts = true;

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

  // Remove acentos e caracteres especiais para busca normalizada
  String _removeAccents(String text) {
    const withAccents =
        'àáâãäåòóôõöøèéêëçìíîïùúûüÿñÀÁÂÃÄÅÒÓÔÕÖØÈÉÊËÇÌÍÎÏÙÚÛÜŸÑ';
    const withoutAccents =
        'aaaaaaooooooeeeeciiiuuuuynAAAAAOOOOOOEEEECIIIUUUUYN';

    String result = text;
    for (int i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result;
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
        _hasMoreProducts = false;
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
    _searchController.addListener(_onSearchChanged);

    // Invalidar cache quando categoria muda
    _selectedCategoryNotifier.addListener(_onCategoryChanged);

    // Carregar favoritos e escutar mudanças
    _favoritesService.addListener(_onFavoritesChanged);
    _favoritesService.loadFavorites();

    // Carregar dados após um pequeno delay para garantir que o widget esteja pronto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
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

  Future<void> _showReportsDialog() async {
    try {
      // Estatísticas básicas
      final totalProdutos = _produtos.length;
      final totalCategorias = _categorias.length;

      // Produtos por categoria
      Map<String, int> produtosPorCategoria = {};
      for (var produto in _produtos) {
        String categoria = produto['categoria_nome'] ?? 'Sem categoria';
        produtosPorCategoria[categoria] =
            (produtosPorCategoria[categoria] ?? 0) + 1;
      }

      // Média de preços
      double mediaPrecos = 0;
      if (_produtos.isNotEmpty) {
        double somaPrecos = _produtos.fold(
          0,
          (sum, produto) => sum + (produto['preco'] ?? 0),
        );
        mediaPrecos = somaPrecos / _produtos.length;
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('📊 Relatórios'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Estatísticas gerais
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estatísticas Gerais',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Total de Produtos: $totalProdutos'),
                        Text('Total de Categorias: $totalCategorias'),
                        Text(
                          'Preço Médio: ${CurrencyFormatter.format(mediaPrecos)}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Produtos por categoria
                const Text(
                  'Produtos por Categoria',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...produtosPorCategoria.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${entry.value}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar relatórios: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    _selectedCategoryNotifier.dispose();
    _favoritesService.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  Future<void> _loadMoreProducts() async {
    // Verificações mais rigorosas para evitar múltiplas chamadas
    if (_isLoadingMoreNotifier.value ||
        !_hasMoreProducts ||
        _isLoading ||
        _isOfflineMode) {
      return;
    }

    // Verificar se realmente está próximo do final
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels <
            _scrollController.position.maxScrollExtent * 0.7) {
      return;
    }

    // Salvar posição atual do scroll antes de começar
    final currentScrollPosition = _scrollController.position.pixels;

    setState(() {
      _isLoadingMoreNotifier.value = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final offset = (_currentPage + 1) * _pageSize;

      final moreProducts = await supabase
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
          .range(offset, offset + _pageSize - 1);

      if (moreProducts.isNotEmpty) {
        final processedProducts = moreProducts.map<Map<String, dynamic>>((
          produto,
        ) {
          final categoria = produto['categorias'];
          return {
            ...produto,
            'categoria_nome': categoria['nome'],
            'categoria_icone': categoria['icone'],
          };
        }).toList();

        setState(() {
          _produtos.addAll(processedProducts);
          _currentPage++;
          _hasMoreProducts = moreProducts.length == _pageSize;
          _cachedFilteredProducts = null; // Invalidar cache
        });

        _isLoadingMoreNotifier.value = false;

        // Restaurar posição do scroll após o rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && mounted) {
            _scrollController.jumpTo(currentScrollPosition);
          }
        });
      } else {
        setState(() {
          _hasMoreProducts = false;
        });
        _isLoadingMoreNotifier.value = false;
      }
    } catch (e) {
      _isLoadingMoreNotifier.value = false;
    }
  }

  void _onSearchChanged() {
    // Cancelar timer anterior se existir
    _searchDebounce?.cancel();

    // Criar novo timer com delay de 300ms
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
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
      _currentPage = 0;
      _hasMoreProducts = true;
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

      // 3. Carregar produtos com categoria (com fallback mais robusto)
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
            .range(0, _pageSize - 1)
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

        _categorias = [
          {'id': 0, 'nome': 'Todos', 'icone': '🍰'},
          ...sortedCategorias,
        ];
      } else {
        // Se não há categorias no banco, usar apenas "Todos"
        _categorias = [
          {'id': 0, 'nome': 'Todos', 'icone': '🍰'},
        ];
        _debugLog('📂 Nenhuma categoria encontrada no banco');
      }

      // Processar produtos com informações da categoria
      if (produtosResponse.isNotEmpty) {
        _produtos = produtosResponse.map<Map<String, dynamic>>((produto) {
          final categoria = produto['categorias'];
          if (categoria != null) {
            return {
              ...produto,
              'categoria_nome': categoria['nome'],
              'categoria_icone': categoria['icone'],
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

      // Não mostrar dados fictícios - apenas informar o erro
      if (mounted) {
        setState(() {
          _categorias = [];
          _produtos = [];
          _isLoading = false;
          _hasMoreProducts = false;
          _isOfflineMode = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Erro ao carregar dados. Verifique sua conexão.'),
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

  // Método de refresh que recarrega completamente os dados
  Future<void> _refreshData() async {
    // Só fazer refresh se não estiver carregando
    if (_isLoading || _isLoadingMoreNotifier.value) {
      return;
    }

    // Não fazer refresh durante a primeira rolagem do usuário
    if (!_hasScrolledDown) {
      return;
    }

    // Resetar flag de scroll ao fazer refresh
    _hasScrolledDown = false;

    // Recarregar todos os dados do zero
    await _loadData();
  }

  List<Map<String, dynamic>> get _filteredProducts {
    // Verificar se precisa reprocessar o cache
    if (_cachedFilteredProducts == null ||
        _lastSearchQuery != _searchQuery ||
        _lastSelectedCategory != _selectedCategory) {
      _debugLog(
        '🔍 Filtrando produtos: busca="$_searchQuery", categoria="$_selectedCategory"',
      );

      _cachedFilteredProducts = _produtos.where((produto) {
        // Filtro por categoria
        bool categoryMatch;
        if (_selectedCategory == 'Todos') {
          categoryMatch = true;
        } else if (_selectedCategory == 'Favoritos') {
          // Filtro especial para favoritos
          final productId = produto['id'].toString();
          categoryMatch = _favoritesService.isFavorite(productId);
        } else {
          categoryMatch = produto['categoria_nome'] == _selectedCategory;
        }

        // Filtro por busca (normalizado sem acentos)
        bool searchMatch = _searchQuery.isEmpty;
        if (!searchMatch) {
          final normalizedSearch = _removeAccents(_searchQuery.toLowerCase());
          final normalizedNome = _removeAccents(
            produto['nome'].toString().toLowerCase(),
          );
          final normalizedDescricao = _removeAccents(
            (produto['descricao'] ?? '').toString().toLowerCase(),
          );

          searchMatch =
              normalizedNome.contains(normalizedSearch) ||
              normalizedDescricao.contains(normalizedSearch);
        }

        return categoryMatch && searchMatch;
      }).toList();

      // Atualizar cache
      _lastSearchQuery = _searchQuery;
      _lastSelectedCategory = _selectedCategory;
    }

    return _cachedFilteredProducts!;
  }

  List<Map<String, dynamic>> get _maisVendidos {
    return _produtos.where((p) => p['mais_vendido'] == true).take(5).toList();
  }

  List<Map<String, dynamic>> get _novidades {
    return _produtos.where((p) => p['novidade'] == true).take(5).toList();
  }

  List<Map<String, dynamic>> _getProdutosEmDestaque() {
    // Produtos em destaque são os que são novidades OU mais vendidos
    return _produtos
        .where((p) => p['novidade'] == true || p['mais_vendido'] == true)
        .take(5)
        .toList();
  }

  String _getCategoryIcon(String categoryName) {
    final category = _categorias.firstWhere(
      (cat) => cat['nome'] == categoryName,
      orElse: () => {'icone': '🍰'},
    );
    return category['icone'] ?? '🍰';
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: _isOfflineMode ? 'Início (Offline)' : 'Início',
      showBackButton: false,
      padding: EdgeInsets.zero,
      actions: [
        // Botão de Relatórios (só para admins)
        if (!widget.isGuestMode && _isAdmin)
          IconButton(
            onPressed: _showReportsDialog,
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Relatórios',
          ),
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
              child: const Icon(Icons.add),
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

                // Só carregar mais produtos se:
                // 1. Não estiver carregando mais produtos
                // 2. Ainda há mais produtos para carregar
                // 3. Está próximo do final (85%)
                // 4. É uma atualização de scroll (não apenas notificação de término)
                if (scrollInfo is ScrollUpdateNotification &&
                    !_isLoadingMoreNotifier.value &&
                    _hasMoreProducts &&
                    !_isLoading &&
                    scrollInfo.metrics.pixels > 0 &&
                    scrollInfo.metrics.pixels >=
                        scrollInfo.metrics.maxScrollExtent * 0.85) {
                  _loadMoreProducts();
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
                                  key: const PageStorageKey<String>(
                                    'categoriesListView',
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: _categoriasComFavoritos.length,
                                  itemBuilder: (context, index) {
                                    final categoria =
                                        _categoriasComFavoritos[index];
                                    final isSelected =
                                        selectedCategory == categoria['nome'];

                                    return Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: FilterChip(
                                        label: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (categoria['icone'] != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: Text(
                                                  categoria['icone'],
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            Text(categoria['nome']),
                                          ],
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
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(child: SizedBox(height: 16)),

                        // Carrosséis de produtos especiais (se não houver busca ativa)
                        if (_searchQuery.isEmpty &&
                            _selectedCategory == 'Todos') ...[
                          // Carrossel de Produtos em Destaque
                          SliverToBoxAdapter(
                            child: ProductCarousel(
                              items: _getProdutosEmDestaque(),
                              title: '⭐ Produtos em Destaque',
                              backgroundColor:
                                  Colors.grey[50] ?? Colors.grey.shade50,
                            ),
                          ),

                          // Carrossel de Mais Vendidos
                          if (_maisVendidos.isNotEmpty)
                            SliverToBoxAdapter(
                              child: ProductCarousel(
                                items: _maisVendidos,
                                title: '🔥 Mais Vendidos',
                                backgroundColor:
                                    Colors.orange[50] ?? Colors.orange.shade50,
                                titleColor:
                                    Colors.orange[800] ??
                                    Colors.orange.shade800,
                              ),
                            ),
                        ],

                        // Seção Novidades (se não houver busca ativa)
                        if (_searchQuery.isEmpty &&
                            _selectedCategory == 'Todos' &&
                            _novidades.isNotEmpty) ...[
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                '✨ Novidades',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 200,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: _novidades.length,
                                itemBuilder: (context, index) {
                                  final produto = _novidades[index];
                                  return Container(
                                    width: 160,
                                    margin: const EdgeInsets.only(right: 12),
                                    child: AnimatedProductCard(
                                      produto: produto,
                                      onTap: widget.isGuestMode
                                          ? () => _onProductTap(produto)
                                          : null, // Usar comportamento padrão se não for guest mode
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],

                        // Título da seção principal - reativo à categoria
                        SliverToBoxAdapter(
                          child: ValueListenableBuilder<String>(
                            valueListenable: _selectedCategoryNotifier,
                            builder: (context, selectedCategory, child) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  _searchQuery.isNotEmpty
                                      ? '🔍 Resultados da busca'
                                      : selectedCategory == 'Todos'
                                      ? '🍰 Todos os Produtos'
                                      : selectedCategory == 'Favoritos'
                                      ? '❤️ Favoritos'
                                      : '${_getCategoryIcon(selectedCategory)} $selectedCategory',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
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
                                          final produto =
                                              _filteredProducts[index];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 6,
                                            ),
                                            child: AnimatedProductCard(
                                              produto: produto,
                                              onTap: widget.isGuestMode
                                                  ? () => _onProductTap(produto)
                                                  : null, // Usar comportamento padrão se não for guest mode
                                            ),
                                          );
                                        }, childCount: _filteredProducts.length),
                                      );
                              },
                            );
                          },
                        ),

                        // Indicador de carregamento para lazy loading
                        ValueListenableBuilder<bool>(
                          valueListenable: _isLoadingMoreNotifier,
                          builder: (context, isLoadingMore, _) {
                            if (!isLoadingMore) {
                              return const SliverToBoxAdapter();
                            }

                            return const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                  ),
                                ),
                              ),
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

  void _onProductTap(Map<String, dynamic> produto) {
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
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(produto: produto),
          ),
        );
      } catch (e) {
        debugPrint('❌ Erro ao navegar para detalhes: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir detalhes do produto: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
            'Choose uma opção para adicionar ao sistema:',
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
                  Icon(Icons.category, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  const Text(
                    'Categoria',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
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
}

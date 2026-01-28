import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../widgets/animated_widgets.dart';
import '../widgets/form_dialogs.dart';
import '../widgets/edit_product_dialog.dart';
import '../widgets/app_menu.dart';
import '../utils/custom_fab_location.dart';
import '../utils/constants.dart';
import '../services/favorites_service.dart';
import '../services/cart_service.dart';
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
        'aaaaaaooooooeeeeciiiiuuuuynAAAAAAOOOOOOEEEECIIIIUUUUYN';

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
                leading: const Icon(Icons.delete, color: Colors.red),
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
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir produto: $e'),
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
                              child: const Center(
                                child: Icon(
                                  Icons.fastfood,
                                  size: 50,
                                  color: Colors.white,
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
                          child: const Center(
                            child: Icon(
                              Icons.fastfood,
                              size: 50,
                              color: Colors.white,
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

                      await _favoritesService.toggleFavorite(productId);

                      setState(() {});

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
                                        content: Text(
                                          '${produto['nome']} adicionado!',
                                        ),
                                        backgroundColor: Colors.green,
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 2),
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

  Widget _buildProductPrice(Map<String, dynamic> produto) {
    final tamanhos = produto['tamanhos'];
    final preco = produto['preco'];
    final precoAnterior = produto['preco_anterior'];

    // Se tem múltiplos tamanhos, mostrar o menor preço
    if (tamanhos != null && tamanhos is List && tamanhos.isNotEmpty) {
      double menorPreco = double.infinity;
      for (var tamanho in tamanhos) {
        final precoTamanho = tamanho['preco']?.toDouble() ?? 0.0;
        if (precoTamanho < menorPreco && precoTamanho > 0) {
          menorPreco = precoTamanho;
        }
      }

      if (menorPreco == double.infinity) {
        return const Text(
          'Sem preço',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A partir de',
            style: TextStyle(fontSize: 10, color: Colors.grey),
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

    return Text(
      CurrencyFormatter.format(precoAtual),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.green,
      ),
    );
  }
}

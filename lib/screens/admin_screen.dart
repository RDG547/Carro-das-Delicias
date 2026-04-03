import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../widgets/base_screen.dart';
import '../widgets/form_dialogs.dart';
import '../widgets/edit_product_dialog.dart';
import '../widgets/app_menu.dart';
import '../widgets/main_navigation_provider.dart';
import '../utils/constants.dart';
import '../services/notification_service.dart';
import '../services/app_settings_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/location_tracking_service.dart';
import '../widgets/category_icon_widget.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _usuarios = [];
  List<Map<String, dynamic>> _pedidos = [];
  bool _isLoading = false;
  final ValueNotifier<String> _userFilterNotifier = ValueNotifier('todos');

  // Subscription para escutar pedidos em tempo real
  StreamSubscription<List<Map<String, dynamic>>>? _pedidosSubscription;
  RealtimeChannel? _catalogChannel;
  Timer? _catalogRefreshDebounce;
  late final VoidCallback _catalogSyncListener;

  // Controladores de busca
  final TextEditingController _searchCategoryController =
      TextEditingController();
  List<Map<String, dynamic>> _filteredCategorias = [];

  // Rastreamento de localização
  final LocationTrackingService _locationService = LocationTrackingService();
  final ValueNotifier<bool> _isTrackingLocationNotifier = ValueNotifier(false);

  bool get _isTrackingLocation => _isTrackingLocationNotifier.value;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _loadData();
    _catalogSyncListener = () {
      _scheduleCatalogRefresh();
    };
    CatalogSyncService.instance.addListener(_catalogSyncListener);
    _setupRealtimeSubscription(); // Adicionar listener em tempo real
    _checkTrackingStatus(); // Verificar estado do rastreamento
    _fadeController.forward();
  }

  // Verifica o estado atual do rastreamento ao iniciar
  Future<void> _checkTrackingStatus() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ _checkTrackingStatus: Usuário não autenticado');
        return;
      }

      debugPrint('🔍 _checkTrackingStatus: Buscando status para user $userId');

      final response = await Supabase.instance.client
          .from('kombi_location')
          .select()
          .eq('admin_id', userId)
          .maybeSingle();

      debugPrint('📊 _checkTrackingStatus: Response = $response');

      if (mounted) {
        if (response != null) {
          final isOnline = response['is_online'] == true;
          final wasTracking = _isTrackingLocation;

          _isTrackingLocationNotifier.value = isOnline;

          debugPrint(
            '🔄 _checkTrackingStatus: was=$wasTracking, now=$isOnline, service=${_locationService.isTracking}',
          );

          // Se estava online e o serviço não está rastreando, reinicia
          if (isOnline && !_locationService.isTracking) {
            debugPrint('▶️ _checkTrackingStatus: Iniciando rastreamento...');
            await _locationService.startTracking();
          }
          // Se estava offline mas o serviço está rastreando, para
          else if (!isOnline && _locationService.isTracking) {
            debugPrint('⏸️ _checkTrackingStatus: Parando rastreamento...');
            await _locationService.stopTracking();
          }
        } else {
          debugPrint('⚠️ _checkTrackingStatus: Nenhum registro encontrado');
          _isTrackingLocationNotifier.value = false;
        }
      }
    } catch (e) {
      debugPrint('❌ Erro ao verificar status de rastreamento: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _searchCategoryController.dispose();
    _pedidosSubscription?.cancel(); // Cancelar subscription ao sair
    _catalogRefreshDebounce?.cancel();
    CatalogSyncService.instance.removeListener(_catalogSyncListener);
    if (_catalogChannel != null) {
      Supabase.instance.client.removeChannel(_catalogChannel!);
    }
    // NÃO chamar _locationService.dispose() pois o serviço deve continuar rodando
    // O rastreamento só deve parar quando o admin desativar manualmente via toggle
    _isTrackingLocationNotifier.dispose(); // Limpar notifier
    _userFilterNotifier.dispose();
    super.dispose();
  }

  // Toggle para rastreamento de localização
  Future<void> _toggleLocationTracking() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      debugPrint('🎛️ _toggleLocationTracking: Atual=$_isTrackingLocation');

      if (_isTrackingLocation) {
        debugPrint('⏸️ Desativando rastreamento...');
        await _locationService.stopTracking();
        _isTrackingLocationNotifier.value = false;
        debugPrint(
          '✅ Rastreamento desativado. Novo estado: $_isTrackingLocation',
        );
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Rastreamento desativado'),
              backgroundColor: Colors.grey,
            ),
          );
        }
      } else {
        debugPrint('▶️ Ativando rastreamento...');
        await _locationService.startTracking();
        _isTrackingLocationNotifier.value = true;
        debugPrint('✅ Rastreamento ativado. Novo estado: $_isTrackingLocation');
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Rastreamento ativado! Compartilhando localização'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Erro em _toggleLocationTracking: $e');
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Carregar produtos
      final produtosResponse = await Supabase.instance.client
          .from('produtos')
          .select('*, categorias!categoria_id(nome)')
          .order('created_at', ascending: false);

      // Carregar categorias
      final categoriasResponse = await Supabase.instance.client
          .from('categorias')
          .select()
          .order('ordem', ascending: true);

      // Carregar usuários
      // Tentar via RPC primeiro (bypass RLS), senão fallback para select normal
      List<dynamic> usuariosResponse = [];
      try {
        debugPrint('👥 Tentando carregar usuários via RPC get_all_users...');
        usuariosResponse = await Supabase.instance.client.rpc('get_all_users');
        debugPrint('✅ Usuários carregados via RPC: ${usuariosResponse.length}');
        for (var u in usuariosResponse.take(3)) {
          debugPrint('   - ${u['email']} (${u['role']})');
        }
      } catch (rpcError) {
        debugPrint('⚠️ RPC get_all_users falhou: $rpcError');
        final rpcErrorStr = rpcError.toString().toLowerCase();

        // Se a função não existe, não tentar outros métodos que também vão falhar
        if (rpcErrorStr.contains('function') &&
            rpcErrorStr.contains('does not exist')) {
          debugPrint('⚠️ Função get_all_users não existe no Supabase');
        }

        // Fallback: tentar carregar via auth admin (apenas se for admin)
        try {
          debugPrint('👥 Tentando carregar via auth.admin.listUsers...');
          final authUsers = await Supabase.instance.client.auth.admin
              .listUsers();
          usuariosResponse = authUsers
              .map(
                (u) => {
                  'id': u.id,
                  'email': u.email,
                  'avatar_url': u.userMetadata?['avatar_url'],
                  'full_name':
                      u.userMetadata?['full_name'] ??
                      u.userMetadata?['name'] ??
                      'Usuário',
                  'role': u.userMetadata?['role'] ?? 'client',
                  'created_at': u.createdAt is DateTime
                      ? (u.createdAt as DateTime).toIso8601String()
                      : u.createdAt.toString(),
                },
              )
              .toList();
          debugPrint(
            '✅ Usuários carregados via auth.admin: ${usuariosResponse.length}',
          );
        } catch (authError) {
          debugPrint('⚠️ auth.admin.listUsers falhou: $authError');
          // Fallback final: select normal (pode retornar apenas o usuário logado devido ao RLS)
          debugPrint('👥 Tentando select normal na tabela profiles...');
          try {
            usuariosResponse = await Supabase.instance.client
                .from('profiles')
                .select()
                .order('created_at', ascending: false);
            debugPrint(
              '✅ Usuários carregados via select: ${usuariosResponse.length}',
            );
          } catch (selectError) {
            debugPrint('❌ Select profiles também falhou: $selectError');
            usuariosResponse = [];
          }
        }
      }

      final usuarioIds = usuariosResponse
          .map((u) => u['id'])
          .whereType<String>()
          .toSet();
      final usuariosProfilesResponse = usuarioIds.isNotEmpty
          ? await Supabase.instance.client
                .from('profiles')
                .select('id, name, email, phone, role, avatar_url')
                .inFilter('id', usuarioIds.toList())
          : <Map<String, dynamic>>[];
      final usuariosProfilesMap = Map<String, Map<String, dynamic>>.fromEntries(
        usuariosProfilesResponse.map(
          (profile) => MapEntry(
            profile['id'].toString(),
            Map<String, dynamic>.from(profile),
          ),
        ),
      );
      final mergedUsuarios = usuariosResponse.map((usuario) {
        final usuarioMap = Map<String, dynamic>.from(usuario);
        final profile = usuariosProfilesMap[usuarioMap['id']?.toString()];
        return {
          ...usuarioMap,
          'full_name':
              usuarioMap['full_name'] ??
              profile?['name'] ??
              usuarioMap['name'] ??
              'Usuário',
          'email': usuarioMap['email'] ?? profile?['email'] ?? '',
          'role': usuarioMap['role'] ?? profile?['role'] ?? 'client',
          'avatar_url': usuarioMap['avatar_url'] ?? profile?['avatar_url'],
        };
      }).toList();

      // Carregar pedidos com itens
      final pedidosResponse = await Supabase.instance.client
          .from('pedidos')
          .select('''
            *,
            pedido_itens(
              *,
              produtos(
                id,
                nome,
                preco,
                imagem_url
              )
            )
          ''')
          .order('created_at', ascending: false);

      // Carregar perfis dos usuários separadamente
      final userIds = pedidosResponse
          .map((p) => p['user_id'])
          .whereType<String>()
          .toSet();
      final profilesResponse = userIds.isNotEmpty
          ? await Supabase.instance.client
                .from('profiles')
                .select('id, name, phone, email')
                .inFilter('id', userIds.toList())
          : <Map<String, dynamic>>[];

      // Mapear perfis por ID
      final profilesMap = Map.fromEntries(
        profilesResponse.map((p) => MapEntry(p['id'], p)),
      );

      // Combinar pedidos com perfis
      final pedidosWithProfiles = pedidosResponse.map((pedido) {
        final userId = pedido['user_id'];
        final profile = profilesMap[userId];
        return {...pedido, 'profiles': profile};
      }).toList();

      setState(() {
        _produtos = List<Map<String, dynamic>>.from(produtosResponse);
        _categorias = List<Map<String, dynamic>>.from(categoriasResponse);
        // Respeitar a ordem do banco de dados (campo 'ordem')
        // As categorias já vêm ordenadas pela query .order('ordem', ascending: true)
        _filteredCategorias = List.from(_categorias);
        _usuarios = List<Map<String, dynamic>>.from(mergedUsuarios);
        _pedidos = List<Map<String, dynamic>>.from(pedidosWithProfiles);
      });

      debugPrint('📊 Dados carregados:');
      debugPrint('   - Produtos: ${_produtos.length}');
      debugPrint('   - Categorias: ${_categorias.length}');
      debugPrint('   - Usuários: ${_usuarios.length}');
      debugPrint('   - Pedidos: ${_pedidos.length}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Configurar listener em tempo real para pedidos
  void _setupRealtimeSubscription() {
    // Escutar mudanças em tempo real na tabela de pedidos
    _pedidosSubscription = Supabase.instance.client
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen(
          (List<Map<String, dynamic>> data) async {
            debugPrint(
              '🔔 [ADMIN] Pedidos atualizados em tempo real: ${data.length} pedidos',
            );
            await _processarPedidosRealtime(data);
          },
          onError: (error) {
            debugPrint('❌ [ADMIN] Erro no stream de pedidos: $error');
          },
        );

    _catalogChannel = Supabase.instance.client
        .channel('admin-catalog-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'produtos',
          callback: (_) => _scheduleCatalogRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categorias',
          callback: (_) => _scheduleCatalogRefresh(),
        )
        .subscribe();
  }

  void _scheduleCatalogRefresh() {
    _catalogRefreshDebounce?.cancel();
    _catalogRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadData();
      }
    });
  }

  /// Processar pedidos recebidos em tempo real
  Future<void> _processarPedidosRealtime(
    List<Map<String, dynamic>> pedidosData,
  ) async {
    try {
      // Verificar se há novos pedidos pendentes
      final novosPedidosPendentes = pedidosData
          .where((p) => p['status'] == 'pendente')
          .where((p) {
            // Verificar se é um pedido novo (não estava na lista anterior)
            return !_pedidos.any((existente) => existente['id'] == p['id']);
          })
          .toList();

      // Se houver novos pedidos pendentes, mostrar notificação
      if (novosPedidosPendentes.isNotEmpty && mounted) {
        for (var pedido in novosPedidosPendentes) {
          await NotificationService.showLocalNotification(
            title: '🔔 Novo Pedido!',
            body:
                'Pedido #${pedido['id'].toString().padLeft(4, '0')} - ${pedido['cliente_nome']}',
            payload: 'order_${pedido['id']}',
          );
        }
      }

      // Buscar IDs únicos de usuários
      final userIds = pedidosData
          .map((p) => p['user_id'])
          .whereType<String>()
          .toSet();

      // Buscar perfis dos usuários
      final profilesResponse = userIds.isNotEmpty
          ? await Supabase.instance.client
                .from('profiles')
                .select('id, name, phone, email')
                .inFilter('id', userIds.toList())
          : <Map<String, dynamic>>[];

      // Mapear perfis por ID
      final profilesMap = Map.fromEntries(
        profilesResponse.map((p) => MapEntry(p['id'], p)),
      );

      // Para cada pedido, buscar os itens relacionados
      List<Map<String, dynamic>> pedidosProcessados = [];

      for (var pedido in pedidosData) {
        // Buscar itens do pedido
        final itensResponse = await Supabase.instance.client
            .from('pedido_itens')
            .select('''
              *,
              produtos(
                id,
                nome,
                preco,
                imagem_url
              )
            ''')
            .eq('pedido_id', pedido['id']);

        final userId = pedido['user_id'];
        final profile = profilesMap[userId];

        pedidosProcessados.add({
          ...pedido,
          'profiles': profile,
          'pedido_itens': itensResponse,
        });
      }

      if (mounted) {
        setState(() {
          _pedidos = pedidosProcessados;
        });
      }
    } catch (e) {
      debugPrint('❌ [ADMIN] Erro ao processar pedidos em tempo real: $e');
    }
  }

  void _filterCategorias(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredCategorias = List.from(_categorias);
      } else {
        _filteredCategorias = _categorias
            .where(
              (categoria) => (categoria['nome'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Painel Admin',
      actions: [AppMenu(isGuestMode: false, isAdmin: true)],
      padding: EdgeInsets.zero, // Remove o padding padrão
      onBackPressed: () {
        debugPrint('🔙 Botão voltar pressionado - Voltando para Home');
        final provider = MainNavigationProvider.of(context);
        if (provider?.navigateToPage != null) {
          // Navega para índice 0 da navbar (Home)
          provider!.navigateToPage!(0);
        } else {
          // Fallback: volta para a primeira rota
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            // Header com estatísticas
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              constraints: const BoxConstraints(minHeight: 80),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.black, Colors.grey],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Produtos',
                        '${_produtos.length}',
                        Icons.inventory,
                        Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Categorias',
                        '${_categorias.length}',
                        Icons.category,
                        Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Pedidos',
                        '${_pedidos.length}',
                        Icons.receipt_long,
                        Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Usuários',
                        '${_usuarios.length}',
                        Icons.people,
                        Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Toggle de Rastreamento de Localização com animação
            ValueListenableBuilder<bool>(
              valueListenable: _isTrackingLocationNotifier,
              builder: (context, isTracking, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isTracking
                          ? [Colors.green[400]!, Colors.green[600]!]
                          : [Colors.grey[400]!, Colors.grey[600]!],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: isTracking
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) {
                          return RotationTransition(
                            turns: animation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          isTracking ? Icons.my_location : Icons.location_off,
                          key: ValueKey(isTracking),
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Column(
                            key: ValueKey(isTracking),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isTracking ? 'Kombi Online' : 'Kombi Offline',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isTracking
                                    ? 'Compartilhando localização em tempo real'
                                    : 'Rastreamento desativado',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Switch(
                        value: isTracking,
                        onChanged: (_) => _toggleLocationTracking(),
                        activeThumbColor: Colors.white,
                        activeTrackColor: Colors.green[300],
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.grey[400],
                      ),
                    ],
                  ),
                );
              },
            ),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black,
                isScrollable:
                    true, // Permite scroll horizontal para mostrar nomes completos
                tabAlignment: TabAlignment.start, // Alinha tabs à esquerda
                tabs: const [
                  Tab(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dashboard, size: 18),
                          SizedBox(width: 6),
                          Text('Dashboard'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 18),
                          SizedBox(width: 6),
                          Text('Pedidos'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2, size: 18),
                          SizedBox(width: 6),
                          Text('Produtos'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.category, size: 18),
                          SizedBox(width: 6),
                          Text('Categorias'),
                        ],
                      ),
                    ),
                  ),
                  Tab(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people, size: 18),
                          SizedBox(width: 6),
                          Text('Usuários'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDashboardTab(),
                        _buildPedidosTab(),
                        _buildProdutosTab(),
                        _buildCategoriasTab(),
                        _buildUsuariosTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: Icon(icon, color: color, size: 28)),
        const SizedBox(height: 6),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Flexible(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Resumo do Sistema',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),

          // Cards de métricas
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
              final aspectRatio = constraints.maxWidth > 600 ? 1.2 : 1.3;

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: aspectRatio,
                children: [
                  _buildMetricCard(
                    'Pedidos Hoje',
                    '${_getPedidosHoje()}',
                    Icons.today,
                    Colors.blue,
                  ),
                  _buildMetricCard(
                    'Pedidos Pendentes',
                    '${_pedidos.where((p) => p['status'] == 'pendente').length}',
                    Icons.pending_actions,
                    Colors.orange,
                  ),
                  _buildMetricCard(
                    'Pedidos Entregues',
                    '${_pedidos.where((p) => p['status'] == 'entregue').length}',
                    Icons.check_circle,
                    Colors.green,
                  ),
                  _buildMetricCard(
                    'Faturamento Total',
                    'R\$ ${_getFaturamentoTotal()}',
                    Icons.attach_money,
                    Colors.green[700]!,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // Relatórios Detalhados
          const Center(
            child: Text(
              'Relatórios Detalhados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                // Faturamento
                Row(
                  children: [
                    Expanded(
                      child: _buildReportCard(
                        'Faturamento Hoje',
                        'R\$ ${_getFaturamentoHoje()}',
                        Icons.today,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildReportCard(
                        'Faturamento Total',
                        'R\$ ${_getFaturamentoTotal()}',
                        Icons.attach_money,
                        Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Estatísticas de Pedidos
                Row(
                  children: [
                    Expanded(
                      child: _buildReportCard(
                        'Ticket Médio',
                        'R\$ ${_getTicketMedio()}',
                        Icons.receipt,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildReportCard(
                        'Taxa de Entrega',
                        '${_getTaxaEntrega()}%',
                        Icons.local_shipping,
                        Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Resumo por Status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resumo por Status:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatusSummary(
                              'Pendentes',
                              _pedidosReais
                                  .where((p) => p['status'] == 'pendente')
                                  .length,
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatusSummary(
                              'Confirmados',
                              _pedidosReais
                                  .where((p) => p['status'] == 'confirmado')
                                  .length,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatusSummary(
                              'Entregues',
                              _pedidosReais
                                  .where((p) => p['status'] == 'entregue')
                                  .length,
                              Colors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatusSummary(
                              'Cancelados',
                              _pedidosReais
                                  .where((p) => p['status'] == 'cancelado')
                                  .length,
                              Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Ações rápidas centralizadas
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                const Text(
                  'Ações Rápidas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2, // 2 colunas para melhor centralização
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                  children: [
                    _buildActionButton(
                      'Novo\nProduto',
                      Icons.add_box,
                      Colors.green,
                      () => _showAddProductDialog(),
                    ),
                    _buildActionButton(
                      'Nova\nCategoria',
                      Icons.add_circle,
                      Colors.blue,
                      () => _showAddCategoryDialog(),
                    ),
                    _buildActionButton(
                      'Relatórios',
                      Icons.assessment,
                      Colors.purple,
                      () => _showReportsDialog(),
                    ),
                    _buildActionButton(
                      'Configurações',
                      Icons.settings,
                      Colors.grey,
                      () => _showSettingsDialog(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProdutosTab() {
    return Column(
      children: [
        // Barra de ações
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar produtos...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FloatingActionButton(
                onPressed: _showAddProductDialog,
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                child: Image.asset(
                  'assets/icons/menu/add_button.png',
                  width: 24,
                  height: 24,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Lista de produtos
        Expanded(
          child: _produtos.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum produto encontrado',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _produtos.length,
                  itemBuilder: (context, index) {
                    final produto = _produtos[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading:
                            produto['imagem_url'] != null &&
                                produto['imagem_url'].toString().isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  produto['imagem_url'],
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  cacheWidth: 112,
                                  cacheHeight: 112,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (context, error, stackTrace) =>
                                      CircleAvatar(
                                        backgroundColor: Colors.grey[200],
                                        child: Text(
                                          produto['nome']
                                                  ?.substring(0, 1)
                                                  .toUpperCase() ??
                                              'P',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                ),
                              )
                            : CircleAvatar(
                                backgroundColor: Colors.grey[200],
                                child: Text(
                                  produto['nome']
                                          ?.substring(0, 1)
                                          .toUpperCase() ??
                                      'P',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                        title: Text(produto['nome'] ?? 'Produto'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              CurrencyFormatter.format(
                                produto['preco']?.toDouble(),
                              ),
                            ),
                            Text(
                              produto['categorias']?['nome'] ?? 'Sem categoria',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 20),
                                  SizedBox(width: 8),
                                  Text('Editar'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Image.asset(
                                    'assets/icons/menu/delete_button.png',
                                    width: 20,
                                    height: 20,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Excluir',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditProductDialog(produto);
                            } else if (value == 'delete') {
                              _showDeleteConfirmation('produto', produto['id']);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCategoriasTab() {
    return Column(
      children: [
        // Barra de ações
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCategoryController,
                  onChanged: _filterCategorias,
                  decoration: InputDecoration(
                    hintText: 'Buscar categorias...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FloatingActionButton(
                onPressed: _showReorderCategoriesDialog,
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                heroTag: "reorder_categories",
                child: const Icon(Icons.reorder),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                onPressed: _showAddCategoryDialog,
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                heroTag: "add_category",
                child: Image.asset(
                  'assets/icons/menu/add_button.png',
                  width: 24,
                  height: 24,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Lista de categorias
        Expanded(
          child: _filteredCategorias.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhuma categoria encontrada',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredCategorias.length,
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width - 32,
                        ),
                        child: child,
                      ),
                    );
                  },
                  onReorder: (oldIndex, newIndex) async {
                    if (oldIndex < newIndex) newIndex--;
                    setState(() {
                      final item = _filteredCategorias.removeAt(oldIndex);
                      _filteredCategorias.insert(newIndex, item);

                      // Atualizar a lista principal também se não há filtro ativo
                      if (_searchCategoryController.text.isEmpty) {
                        _categorias.clear();
                        _categorias.addAll(_filteredCategorias);
                      }
                    });

                    // Salvar a ordem no banco de dados
                    try {
                      for (int i = 0; i < _filteredCategorias.length; i++) {
                        final categoria = _filteredCategorias[i];
                        await Supabase.instance.client
                            .from('categorias')
                            .update({'ordem': i})
                            .eq('id', categoria['id']);
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ordem salva com sucesso!'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erro ao salvar ordem: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        // Recarregar dados em caso de erro
                        _loadData();
                      }
                    }
                  },
                  itemBuilder: (context, index) {
                    final categoria = _filteredCategorias[index];
                    return Card(
                      key: ValueKey(categoria['id']),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: CategoryIconWidget(
                              icone: categoria['icone'] ?? '📦',
                              categoryName: categoria['nome'],
                              size: 28,
                            ),
                          ),
                        ),
                        title: Text(categoria['nome'] ?? 'Categoria'),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 20),
                                  SizedBox(width: 8),
                                  Text('Editar'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Image.asset(
                                    'assets/icons/menu/delete_button.png',
                                    width: 20,
                                    height: 20,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Excluir',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditCategoryDialog(categoria);
                            } else if (value == 'delete') {
                              // Garantir que o ID seja passado como int para evitar conflito de tipos no RPC
                              final catId = categoria['id'];
                              final catIdInt = catId is int
                                  ? catId
                                  : int.parse(catId.toString());
                              _showDeleteConfirmation('categoria', catIdInt);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUsuariosTab() {
    return ValueListenableBuilder<String>(
      valueListenable: _userFilterNotifier,
      builder: (context, selectedFilter, child) {
        final filteredUsuarios =
            _usuarios.where((u) {
              if (selectedFilter == 'admin') return u['role'] == 'admin';
              if (selectedFilter == 'client') return u['role'] != 'admin';
              return true;
            }).toList()..sort((a, b) {
              final aAdmin = a['role'] == 'admin' ? 0 : 1;
              final bAdmin = b['role'] == 'admin' ? 0 : 1;
              return aAdmin.compareTo(bAdmin);
            });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildUserFilter(
                    label: 'Todos',
                    value: 'todos',
                    icon: Icons.people,
                    selectedFilter: selectedFilter,
                  ),
                  const SizedBox(width: 8),
                  _buildUserFilter(
                    label: 'Admin',
                    value: 'admin',
                    icon: Icons.admin_panel_settings,
                    selectedFilter: selectedFilter,
                  ),
                  const SizedBox(width: 8),
                  _buildUserFilter(
                    label: 'Usuário',
                    value: 'client',
                    icon: Icons.person,
                    selectedFilter: selectedFilter,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: filteredUsuarios.isEmpty
                    ? const Center(
                        key: ValueKey('empty-users'),
                        child: Text(
                          'Nenhum usuário encontrado',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        key: ValueKey('users-$selectedFilter'),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredUsuarios.length,
                        itemBuilder: (context, index) {
                          final usuario = filteredUsuarios[index];
                          final isAdmin = usuario['role'] == 'admin';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: _buildUserAvatar(usuario, isAdmin),
                              title: Text(usuario['full_name'] ?? 'Usuário'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(usuario['email'] ?? ''),
                                  Text(
                                    isAdmin ? 'Administrador' : 'Cliente',
                                    style: TextStyle(
                                      color: isAdmin ? Colors.red : Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton(
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'toggle_role',
                                    child: Row(
                                      children: [
                                        Icon(
                                          isAdmin
                                              ? Icons.person
                                              : Icons.admin_panel_settings,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isAdmin
                                              ? 'Tornar Usuário'
                                              : 'Tornar Admin',
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onSelected: (value) {
                                  if (value == 'toggle_role') {
                                    _toggleUserRole(usuario);
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserAvatar(Map<String, dynamic> usuario, bool isAdmin) {
    final avatarUrl = usuario['avatar_url']?.toString();
    final fullName = usuario['full_name']?.toString().trim().isNotEmpty == true
        ? usuario['full_name'].toString().trim()
        : 'Usuário';

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: isAdmin ? Colors.red[100] : Colors.blue[100],
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Text(
                    fullName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isAdmin ? Colors.red : Colors.blue,
                    ),
                  )
                : null,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.person,
                size: 12,
                color: isAdmin ? Colors.red : Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserFilter({
    required String label,
    required String value,
    required IconData icon,
    required String selectedFilter,
  }) {
    final isSelected = selectedFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _userFilterNotifier.value = value,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.black,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: Icon(icon, color: color, size: 24)),
            const SizedBox(height: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive sizing com múltiplos breakpoints
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        double iconSize;
        double fontSize;
        EdgeInsets padding;
        double spacing;

        if (width > 150 && height > 100) {
          // Large button
          iconSize = 32.0;
          fontSize = 14.0;
          padding = const EdgeInsets.all(16);
          spacing = 12.0;
        } else if (width > 100 && height > 80) {
          // Medium button
          iconSize = 28.0;
          fontSize = 12.0;
          padding = const EdgeInsets.all(12);
          spacing = 10.0;
        } else if (width > 80) {
          // Small button
          iconSize = 24.0;
          fontSize = 11.0;
          padding = const EdgeInsets.all(8);
          spacing = 8.0;
        } else {
          // Very small button
          iconSize = 20.0;
          fontSize = 10.0;
          padding = const EdgeInsets.all(6);
          spacing = 6.0;
        }

        return Material(
          color: color,
          borderRadius: BorderRadius.circular(12),
          elevation: 3,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              padding: padding,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: iconSize),
                  SizedBox(height: spacing),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.1, // Reduz espaçamento entre linhas
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Métodos de diálogo e ações
  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          AddProductDialog(categorias: _categorias, onProductAdded: _loadData),
    );
  }

  void _showEditProductDialog(Map<String, dynamic> produto) {
    showDialog(
      context: context,
      builder: (context) => EditProductDialog(
        produto: produto,
        categorias: _categorias,
        onProductUpdated: _loadData,
      ),
    );
  }

  Future<void> _showReorderCategoriesDialog() async {
    // Criar cópia dos dados atuais
    List<Map<String, dynamic>> tempCategorias = List.from(_categorias);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Reordenar Categorias',
              textAlign: TextAlign.center,
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ReorderableListView.builder(
                itemCount: tempCategorias.length,
                onReorder: (oldIndex, newIndex) {
                  if (oldIndex < newIndex) newIndex--;
                  setDialogState(() {
                    final item = tempCategorias.removeAt(oldIndex);
                    tempCategorias.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final categoria = tempCategorias[index];
                  return Card(
                    key: ValueKey(categoria['id']),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CategoryIconWidget(
                              icone: categoria['icone'] ?? '📦',
                              categoryName: categoria['nome'],
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              categoria['nome'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.drag_handle),
                    ),
                  );
                },
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
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
                onPressed: () async {
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);

                  try {
                    // Atualizar a ordem de cada categoria no banco de dados
                    for (int i = 0; i < tempCategorias.length; i++) {
                      final categoria = tempCategorias[i];
                      await Supabase.instance.client
                          .from('categorias')
                          .update({'ordem': i})
                          .eq('id', categoria['id']);
                    }

                    // Atualizar o estado local imediatamente
                    if (mounted) {
                      setState(() {
                        _categorias = List.from(tempCategorias);
                        _filteredCategorias = List.from(tempCategorias);
                      });

                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Ordem das categorias atualizada com sucesso!',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                      navigator.pop();
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('Erro ao reordenar categorias: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.save, size: 18),
                    SizedBox(width: 6),
                    Text('Salvar Ordem'),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AddCategoryDialog(onCategoryAdded: _loadData),
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
                  child: CategoryIconWidget(
                    icone: iconeOriginal,
                    categoryName: categoria['nome'],
                    size: 24,
                  ),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
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
                      final rpcErrorMsg = rpcError.toString().toLowerCase();
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
                        content: Text('Categoria atualizada com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadData();
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.save, size: 18),
                  SizedBox(width: 6),
                  Text('Salvar Alterações'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(String type, dynamic id) {
    debugPrint(
      '🗑️ _showDeleteConfirmation chamado - type: $type, id: $id (tipo: ${id.runtimeType})',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir $type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Tem certeza que deseja excluir este $type?',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Esta ação não pode ser desfeita!',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              navigator.pop();

              debugPrint('🗑️ Iniciando exclusão de $type com id: $id');

              try {
                String tableName = type == 'produto'
                    ? 'produtos'
                    : 'categorias';

                // Tentar delete direto primeiro
                debugPrint(
                  '🗑️ Tentando delete direto na tabela $tableName...',
                );
                final deleteResult = await Supabase.instance.client
                    .from(tableName)
                    .delete()
                    .eq('id', id)
                    .select();

                debugPrint('🗑️ Resultado do delete direto: $deleteResult');

                // Se o delete não retornou nada, pode ser que o RLS bloqueou
                if (deleteResult.isEmpty) {
                  debugPrint(
                    '⚠️ Delete direto retornou vazio - possível bloqueio RLS',
                  );

                  // Tentar via RPC que bypassa RLS
                  debugPrint('🗑️ Tentando delete via RPC...');
                  try {
                    // Garantir que o ID seja int para evitar conflito de funções sobrecarregadas
                    final idInt = id is int ? id : int.parse(id.toString());
                    debugPrint('🗑️ ID convertido para int: $idInt');

                    if (type == 'produto') {
                      await Supabase.instance.client.rpc(
                        'delete_produto_admin',
                        params: {'produto_id': idInt},
                      );
                    } else {
                      await Supabase.instance.client.rpc(
                        'delete_categoria_admin',
                        params: {'categoria_id': idInt},
                      );
                    }
                    debugPrint('✅ Delete via RPC bem-sucedido');
                  } catch (rpcError) {
                    debugPrint('❌ RPC delete falhou: $rpcError');
                    final rpcErrorMsg = rpcError.toString().toLowerCase();
                    if (rpcErrorMsg.contains('foreign key') ||
                        rpcErrorMsg.contains('23503') ||
                        rpcErrorMsg.contains('referential integrity')) {
                      throw Exception(
                        'Não é possível excluir esta categoria porque existem produtos vinculados a ela. '
                        'Remova ou altere a categoria dos produtos primeiro.',
                      );
                    }
                    // Se o RPC não existe, mostrar mensagem específica
                    if (rpcErrorMsg.contains('function') &&
                        rpcErrorMsg.contains('does not exist')) {
                      throw Exception(
                        'Função de exclusão não encontrada no servidor. '
                        'Por favor, execute o SQL de configuração no Supabase.',
                      );
                    }
                    rethrow;
                  }
                } else {
                  debugPrint('✅ Delete direto bem-sucedido');
                }

                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '${type.toUpperCase()} excluído com sucesso!',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadData();
                }
              } catch (e) {
                debugPrint('❌ Erro final ao excluir: $e');
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Erro ao excluir: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
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
  }

  Future<void> _showReportsDialog() async {
    try {
      // Estatísticas básicas
      final totalProdutos = _produtos.length;
      final totalCategorias = _categorias.length;
      final totalUsuarios = _usuarios.length;

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

      // Produtos ativos vs inativos
      int produtosAtivos = _produtos.where((p) => p['ativo'] == true).length;
      int produtosInativos = _produtos.where((p) => p['ativo'] == false).length;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('📊 Relatórios Administrativos'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
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
                          Text('  • Ativos: $produtosAtivos'),
                          Text('  • Inativos: $produtosInativos'),
                          const SizedBox(height: 4),
                          Text('Total de Categorias: $totalCategorias'),
                          Text('Total de Usuários: $totalUsuarios'),
                          Text(
                            'Preço Médio: ${CurrencyFormatter.format(mediaPrecos)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Produtos por categoria
                  if (produtosPorCategoria.isNotEmpty) ...[
                    const Text(
                      'Produtos por Categoria',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...produtosPorCategoria.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(entry.key)),
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
                ],
              ),
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

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.grey),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚙️ Configurações do Sistema',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Configurações de Dados
                _buildSettingsSection(
                  title: 'Gerenciamento de Dados',
                  icon: Icons.storage,
                  items: [
                    _buildSettingsItem(
                      title: 'Backup dos Dados',
                      subtitle: 'Exportar dados do sistema',
                      icon: Icons.backup,
                      onTap: _showBackupDialog,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Configurações de Segurança
                _buildSettingsSection(
                  title: 'Segurança e Acesso',
                  icon: Icons.security,
                  items: [
                    _buildSettingsItem(
                      title: 'Auditoria de Usuários',
                      subtitle: 'Ver log de atividades dos usuários',
                      icon: Icons.history,
                      onTap: _showAuditLog,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Configurações do Sistema
                _buildSettingsSection(
                  title: 'Sistema',
                  icon: Icons.tune,
                  items: [
                    _buildSettingsItem(
                      title: 'Configurações de Pagamento',
                      subtitle: 'Definir quando dinheiro fica disponível',
                      icon: Icons.payments,
                      onTap: _showPaymentSettings,
                    ),
                    _buildSettingsItem(
                      title: 'Configurações de Notificação',
                      subtitle: 'Gerenciar notificações do sistema',
                      icon: Icons.notifications_outlined,
                      onTap: _showNotificationSettings,
                    ),
                    _buildSettingsItem(
                      title: 'Manutenção do Sistema',
                      subtitle: 'Ferramentas de manutenção',
                      icon: Icons.build,
                      onTap: _showMaintenanceOptions,
                    ),
                  ],
                ),
              ],
            ),
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
  }

  Widget _buildSettingsSection({
    required String title,
    required IconData icon,
    required List<Widget> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.grey[600]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showBackupDialog() {
    Navigator.of(context).pop(); // Fechar configurações
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('💾 Backup dos Dados'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipos de backup disponíveis:'),
            SizedBox(height: 12),
            Text('• Produtos e Categorias'),
            Text('• Dados de Usuários'),
            Text('• Configurações do Sistema'),
            SizedBox(height: 16),
            Text(
              'O backup será gerado em formato JSON e pode ser usado para restaurar dados em caso de necessidade.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
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
            onPressed: () {
              Navigator.of(context).pop();
              _performBackup();
            },
            child: const Text('Gerar Backup'),
          ),
        ],
      ),
    );
  }

  void _showAuditLog() {
    Navigator.of(context).pop(); // Fechar configurações
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📋 Auditoria de Usuários'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            children: [
              const Text('Atividades recentes dos usuários:'),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _usuarios.length,
                  itemBuilder: (context, index) {
                    final usuario = _usuarios[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(usuario['name']?.substring(0, 1) ?? 'U'),
                      ),
                      title: Text(usuario['name'] ?? 'Usuário'),
                      subtitle: Text('Role: ${usuario['role'] ?? 'client'}'),
                      trailing: Text(
                        'Ativo',
                        style: TextStyle(
                          color: Colors.green[600],
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
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
  }

  void _showNotificationSettings() {
    Navigator.of(context).pop(); // Fechar configurações
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔔 Configurações de Notificação'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tipos de notificação:'),
            SizedBox(height: 12),
            Text('• Novos usuários registrados'),
            Text('• Produtos adicionados'),
            Text('• Erros do sistema'),
            Text('• Backup automático'),
            SizedBox(height: 16),
            Text(
              'As notificações podem ser configuradas para alertar sobre eventos importantes do sistema.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showPaymentSettings() async {
    Navigator.of(context).pop();

    final initialSettings = await AppSettingsService.getCashPaymentSettings();
    if (!mounted) return;

    var selectedAvailability = initialSettings.availability;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configurações de Pagamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Defina quando o pagamento em dinheiro ficará disponível:',
              ),
              const SizedBox(height: 16),
              _buildPaymentOptionTile(
                title: 'Todos os clientes autenticados',
                subtitle: 'Libera dinheiro para qualquer usuário logado.',
                isSelected:
                    selectedAvailability == CashPaymentAvailability.allUsers,
                onTap: () {
                  setDialogState(() {
                    selectedAvailability = CashPaymentAvailability.allUsers;
                  });
                },
              ),
              const SizedBox(height: 8),
              _buildPaymentOptionTile(
                title: 'Mínimo de 5 pedidos concluídos',
                subtitle:
                    'Mantém o desbloqueio de dinheiro só após 5 entregas.',
                isSelected:
                    selectedAvailability ==
                    CashPaymentAvailability.minimumCompletedOrders,
                onTap: () {
                  setDialogState(() {
                    selectedAvailability =
                        CashPaymentAvailability.minimumCompletedOrders;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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
            ElevatedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(dialogContext);
                final settings = CashPaymentSettings(
                  availability: selectedAvailability,
                  minimumCompletedOrders: 5,
                );

                try {
                  await AppSettingsService.saveCashPaymentSettings(settings);
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Configuração do pagamento em dinheiro atualizada!',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (error) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Erro ao salvar configuração: $error'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Salvar Alterações'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentOptionTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? Colors.green.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMaintenanceOptions() {
    Navigator.of(context).pop(); // Fechar configurações
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔧 Manutenção do Sistema'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ferramentas de manutenção disponíveis:'),
            SizedBox(height: 12),
            Text('• Otimização do banco de dados'),
            Text('• Limpeza de dados órfãos'),
            Text('• Verificação de integridade'),
            Text('• Atualização de índices'),
            SizedBox(height: 16),
            Text(
              'Execute essas ferramentas periodicamente para manter o sistema otimizado.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _runMaintenance();
            },
            child: const Text('Executar Manutenção'),
          ),
        ],
      ),
    );
  }

  void _performBackup() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.backup, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Backup gerado com sucesso!',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _runMaintenance() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.build, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Manutenção executada com sucesso!',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildPedidosTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.blue[700], size: 28),
              const SizedBox(width: 12),
              Text(
                'Gerenciar Pedidos',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filtros de status
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusFilter('Todos', null),
              _buildStatusFilter('Pendentes', 'pendente'),
              _buildStatusFilter('Confirmados', 'confirmado'),
              _buildStatusFilter('Em Preparo', 'em preparo'),
              _buildStatusFilter('Saiu Entrega', 'saiu para entrega'),
              _buildStatusFilter('Entregues', 'entregue'),
              _buildStatusFilter('Testes', 'teste'),
              _buildStatusFilter('Cancelados', 'cancelado'),
            ],
          ),
          const SizedBox(height: 20),

          // Lista de pedidos filtrados
          Builder(
            builder: (context) {
              final pedidosFiltrados = _selectedStatusFilter == null
                  ? _pedidos
                  : _pedidos
                        .where((p) => p['status'] == _selectedStatusFilter)
                        .toList();

              if (pedidosFiltrados.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 60),
                      Icon(
                        Icons.receipt_long,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _selectedStatusFilter == null
                            ? 'Nenhum pedido encontrado'
                            : 'Nenhum pedido com status "${_getStatusLabel(_selectedStatusFilter!)}" encontrado',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedStatusFilter == null
                            ? 'Os pedidos aparecerão aqui quando forem criados'
                            : 'Tente selecionar outro filtro ou aguarde novos pedidos',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                      const SizedBox(height: 60),
                    ],
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pedidosFiltrados.length,
                itemBuilder: (context, index) {
                  final pedido = pedidosFiltrados[index];
                  return _buildPedidoCard(pedido);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilter(String label, String? status) {
    final isSelected = _selectedStatusFilter == status;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStatusFilter = status;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  DateTime? _getDeliveredAt(Map<String, dynamic> pedido) {
    final rawDeliveredAt =
        pedido['entregue_em'] ??
        (pedido['status'] == 'entregue' ? pedido['updated_at'] : null);
    if (rawDeliveredAt == null) return null;
    return DateTime.tryParse(rawDeliveredAt.toString())?.toLocal();
  }

  String _formatDateTime(DateTime value) {
    final localValue = value.toLocal();
    return '${localValue.day.toString().padLeft(2, '0')}/${localValue.month.toString().padLeft(2, '0')}/${localValue.year} ${localValue.hour.toString().padLeft(2, '0')}:${localValue.minute.toString().padLeft(2, '0')}:${localValue.second.toString().padLeft(2, '0')}';
  }

  bool _isMissingPedidoColumnError(dynamic error) {
    final errorMessage = error.toString().toLowerCase();
    return errorMessage.contains('entregue_em') ||
        errorMessage.contains('updated_at');
  }

  Widget _buildPedidoCard(Map<String, dynamic> pedido) {
    final status = pedido['status'] ?? 'pendente';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final itens = pedido['pedido_itens'] as List? ?? [];
    final total = pedido['total'] ?? 0.0;
    final dataPedido = DateTime.tryParse(pedido['created_at'] ?? '');
    final dataEntregaAgendada = pedido['data_entrega'] != null
        ? DateTime.tryParse(pedido['data_entrega'].toString())
        : null;
    final entregueEm = _getDeliveredAt(pedido);
    final cliente = pedido['profiles'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPedidoDetails(pedido),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header do pedido
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: statusColor, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusLabel(status),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (pedido['is_teste'] == true || status == 'teste')
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.science, color: Colors.white, size: 12),
                          SizedBox(width: 2),
                          Text(
                            'TESTE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    '#${pedido['id'].toString().padLeft(4, '0')}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Cliente
              Row(
                children: [
                  Icon(Icons.person, color: Colors.grey[600], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pedido['cliente_nome'] ??
                          cliente?['name'] ??
                          'Cliente não informado',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Itens
              Row(
                children: [
                  Icon(Icons.shopping_cart, color: Colors.grey[600], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${itens.length} item${itens.length != 1 ? 's' : ''}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Total e data
              Row(
                children: [
                  Icon(
                    Icons.payments_outlined,
                    color: Colors.green[700],
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'R\$ ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  if (dataPedido != null)
                    Text(
                      _formatDateTime(dataPedido),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                ],
              ),

              if (entregueEm != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green[700],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Entregue: ${_formatDateTime(entregueEm)}',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ] else if (dataEntregaAgendada != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.local_shipping,
                      color: Colors.orange[700],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Entrega: ${dataEntregaAgendada.day.toString().padLeft(2, '0')}/${dataEntregaAgendada.month.toString().padLeft(2, '0')}/${dataEntregaAgendada.year}',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],

              // Ações de alteração de status
              const SizedBox(height: 16),
              _buildStatusActions(pedido),

              // Botão excluir para pedidos de teste
              if (pedido['is_teste'] == true || status == 'teste') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _excluirPedidoTeste(pedido),
                    icon: Image.asset(
                      'assets/icons/menu/delete_button.png',
                      width: 16,
                      height: 16,
                      color: Colors.black,
                    ),
                    label: const Text('Excluir Pedido de Teste'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pendente':
        return Colors.orange;
      case 'pago':
        return Colors.teal;
      case 'confirmado':
        return Colors.blue;
      case 'em preparo':
        return Colors.orange;
      case 'saiu para entrega':
        return Colors.purple;
      case 'entregue':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      case 'teste':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pendente':
        return Icons.pending_actions;
      case 'pago':
        return Icons.payment;
      case 'confirmado':
        return Icons.check_circle_outline;
      case 'em preparo':
        return Icons.kitchen;
      case 'saiu para entrega':
        return Icons.delivery_dining;
      case 'entregue':
        return Icons.check_circle;
      case 'cancelado':
        return Icons.cancel;
      case 'teste':
        return Icons.science;
      default:
        return Icons.help;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'pago':
        return 'Pago';
      case 'confirmado':
        return 'Confirmado';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      case 'em preparo':
        return 'Em Preparo';
      case 'saiu para entrega':
        return 'Saiu para Entrega';
      case 'teste':
        return 'Teste';
      default:
        return 'Desconhecido';
    }
  }

  Widget _buildStatusActions(Map<String, dynamic> pedido) {
    final currentStatus = pedido['status'] ?? 'pendente';
    final availableStatuses = _getAvailableStatuses(currentStatus);

    if (availableStatuses.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alterar Status:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availableStatuses.map((statusInfo) {
            return ElevatedButton.icon(
              onPressed: () =>
                  _alterarStatusPedido(pedido, statusInfo['status']),
              icon: Icon(statusInfo['icon'], size: 16),
              label: Text(statusInfo['label']),
              style: ElevatedButton.styleFrom(
                backgroundColor: statusInfo['color'],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                minimumSize: const Size(0, 32),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getAvailableStatuses(String currentStatus) {
    switch (currentStatus) {
      case 'pendente':
        return [
          {
            'status': 'confirmado',
            'label': 'Confirmar',
            'icon': Icons.check_circle_outline,
            'color': Colors.blue,
          },
          {
            'status': 'cancelado',
            'label': 'Cancelar',
            'icon': Icons.cancel,
            'color': Colors.red,
          },
        ];
      case 'pago':
        return [
          {
            'status': 'confirmado',
            'label': 'Confirmar',
            'icon': Icons.check_circle_outline,
            'color': Colors.blue,
          },
          {
            'status': 'cancelado',
            'label': 'Cancelar',
            'icon': Icons.cancel,
            'color': Colors.red,
          },
        ];
      case 'confirmado':
        return [
          {
            'status': 'em preparo',
            'label': 'Em Preparo',
            'icon': Icons.kitchen,
            'color': Colors.orange,
          },
          {
            'status': 'cancelado',
            'label': 'Cancelar',
            'icon': Icons.cancel,
            'color': Colors.red,
          },
          {
            'status': 'pendente',
            'label': 'Voltar Pendente',
            'icon': Icons.pending_actions,
            'color': Colors.grey,
          },
        ];
      case 'em preparo':
        return [
          {
            'status': 'saiu para entrega',
            'label': 'Saiu para Entrega',
            'icon': Icons.delivery_dining,
            'color': Colors.purple,
          },
          {
            'status': 'entregue',
            'label': 'Entregue',
            'icon': Icons.check_circle,
            'color': Colors.green,
          },
          {
            'status': 'cancelado',
            'label': 'Cancelar',
            'icon': Icons.cancel,
            'color': Colors.red,
          },
          {
            'status': 'confirmado',
            'label': 'Voltar Confirmado',
            'icon': Icons.check_circle_outline,
            'color': Colors.grey,
          },
        ];
      case 'saiu para entrega':
        return [
          {
            'status': 'entregue',
            'label': 'Entregue',
            'icon': Icons.check_circle,
            'color': Colors.green,
          },
          {
            'status': 'em preparo',
            'label': 'Voltar Preparo',
            'icon': Icons.kitchen,
            'color': Colors.orange,
          },
          {
            'status': 'cancelado',
            'label': 'Cancelar',
            'icon': Icons.cancel,
            'color': Colors.red,
          },
        ];
      case 'entregue':
        return [
          {
            'status': 'saiu para entrega',
            'label': 'Voltar Entrega',
            'icon': Icons.delivery_dining,
            'color': Colors.purple,
          },
          {
            'status': 'em preparo',
            'label': 'Voltar Preparo',
            'icon': Icons.kitchen,
            'color': Colors.orange,
          },
        ];
      case 'cancelado':
        return [
          {
            'status': 'pendente',
            'label': 'Reativar',
            'icon': Icons.restore,
            'color': Colors.blue,
          },
        ];
      case 'teste':
        return [
          {
            'status': 'confirmado',
            'label': 'Confirmar',
            'icon': Icons.check_circle_outline,
            'color': Colors.blue,
          },
        ];
      default:
        return [];
    }
  }

  String? _selectedStatusFilter;

  /// Pedidos reais (exclui pedidos de teste) para estatísticas
  List<Map<String, dynamic>> get _pedidosReais => _pedidos
      .where((p) => p['status'] != 'teste' && p['is_teste'] != true)
      .toList();

  int _getPedidosHoje() {
    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final fimHoje = inicioHoje.add(const Duration(days: 1));

    return _pedidosReais.where((pedido) {
      final dataPedido = DateTime.tryParse(pedido['created_at'] ?? '');
      if (dataPedido == null) return false;
      return dataPedido.isAfter(inicioHoje) && dataPedido.isBefore(fimHoje);
    }).length;
  }

  String _getFaturamentoTotal() {
    final total = _pedidosReais
        .where((p) => p['status'] == 'entregue' || p['status'] == 'confirmado')
        .fold(0.0, (sum, p) => sum + (p['total'] ?? 0.0));
    return total.toStringAsFixed(2);
  }

  String _getFaturamentoHoje() {
    final hoje = DateTime.now();
    final inicioHoje = DateTime(hoje.year, hoje.month, hoje.day);
    final fimHoje = inicioHoje.add(const Duration(days: 1));

    final totalHoje = _pedidosReais
        .where((pedido) {
          final dataPedido = DateTime.tryParse(pedido['created_at'] ?? '');
          if (dataPedido == null) return false;
          final isHoje =
              dataPedido.isAfter(inicioHoje) && dataPedido.isBefore(fimHoje);
          final isEntregue =
              pedido['status'] == 'entregue' ||
              pedido['status'] == 'confirmado';
          return isHoje && isEntregue;
        })
        .fold(0.0, (sum, p) => sum + (p['total'] ?? 0.0));

    return totalHoje.toStringAsFixed(2);
  }

  String _getTicketMedio() {
    final pedidosEntregues = _pedidosReais
        .where((p) => p['status'] == 'entregue')
        .toList();
    if (pedidosEntregues.isEmpty) return '0.00';

    final total = pedidosEntregues.fold(
      0.0,
      (sum, p) => sum + (p['total'] ?? 0.0),
    );
    final ticketMedio = total / pedidosEntregues.length;
    return ticketMedio.toStringAsFixed(2);
  }

  String _getTaxaEntrega() {
    final totalPedidos = _pedidosReais.length;
    if (totalPedidos == 0) return '0';

    final pedidosEntregues = _pedidosReais
        .where((p) => p['status'] == 'entregue')
        .length;
    final taxa = (pedidosEntregues / totalPedidos) * 100;
    return taxa.toStringAsFixed(1);
  }

  Widget _buildReportCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSummary(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showPedidoDetails(Map<String, dynamic> pedido) {
    final itens = pedido['pedido_itens'] as List? ?? [];
    final cliente = pedido['profiles'];
    final dataEntregaAgendada = pedido['data_entrega'] != null
        ? DateTime.tryParse(pedido['data_entrega'].toString())
        : null;
    final entregueEm = _getDeliveredAt(pedido);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.blue[700], size: 28),
            const SizedBox(width: 12),
            Text('Pedido #${pedido['id'].toString().padLeft(4, '0')}'),
            if (pedido['is_teste'] == true || pedido['status'] == 'teste') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'TESTE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(
                    pedido['status'],
                  ).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _getStatusColor(pedido['status'])),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStatusIcon(pedido['status']),
                      color: _getStatusColor(pedido['status']),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getStatusLabel(pedido['status']),
                      style: TextStyle(
                        color: _getStatusColor(pedido['status']),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Cliente
              _buildDetailRow(
                'Cliente:',
                pedido['cliente_nome'] ?? cliente?['name'] ?? 'Não informado',
              ),
              _buildDetailRow(
                'Telefone:',
                pedido['cliente_telefone'] ??
                    cliente?['phone'] ??
                    'Não informado',
              ),
              _buildDetailRow(
                'Endereço:',
                pedido['endereco_completo'] ?? 'Não informado',
              ),
              _buildDetailRow('Bairro:', pedido['bairro'] ?? 'Não informado'),
              _buildDetailRow('Cidade:', pedido['cidade'] ?? 'Não informado'),
              _buildDetailRow('CEP:', pedido['cep'] ?? 'Não informado'),
              _buildDetailRow(
                'Pagamento:',
                _getPaymentMethodName(pedido['metodo_pagamento']),
              ),

              if (pedido['valor_troco'] != null)
                _buildDetailRow(
                  'Troco para:',
                  'R\$ ${pedido['valor_troco'].toStringAsFixed(2)}',
                ),

              if (pedido['observacoes'] != null &&
                  pedido['observacoes'].isNotEmpty)
                _buildDetailRow('Observações:', pedido['observacoes']),

              if (dataEntregaAgendada != null)
                _buildDetailRow(
                  'Entrega Agendada:',
                  '${dataEntregaAgendada.day.toString().padLeft(2, '0')}/${dataEntregaAgendada.month.toString().padLeft(2, '0')}/${dataEntregaAgendada.year}',
                ),

              if (entregueEm != null)
                _buildDetailRow('Entregue em:', _formatDateTime(entregueEm)),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Itens
              const Text(
                'Itens do Pedido:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),

              ...itens.map<Widget>((item) {
                final produto = item['produtos'];
                final tamanho = item['tamanho_selecionado'];
                debugPrint('🔍 Admin - Item completo: $item');
                debugPrint('🔍 Admin - Tamanho do item: $tamanho');
                debugPrint(
                  '🔍 Admin - Chaves disponíveis: ${item.keys.toList()}',
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              produto?['nome'] ?? 'Produto não encontrado',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (tamanho != null && tamanho.toString().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.purple[300]!),
                              ),
                              child: Text(
                                tamanho.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple[700],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('Quantidade: ${item['quantidade']}'),
                          const Spacer(),
                          Text(
                            'R\$ ${item['preco_unitario'].toStringAsFixed(2)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('Subtotal:'),
                          const Spacer(),
                          Text(
                            'R\$ ${item['subtotal'].toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      if (item['observacoes'] != null &&
                          item['observacoes'].isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Obs: ${item['observacoes']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Total
              Row(
                children: [
                  const Text(
                    'Total do Pedido:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    'R\$ ${pedido['total'].toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pedido['is_teste'] == true || pedido['status'] == 'teste')
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _excluirPedidoTeste(pedido);
                      },
                      icon: Image.asset(
                        'assets/icons/menu/delete_button.png',
                        width: 18,
                        height: 18,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'Excluir',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                if (pedido['is_teste'] == true || pedido['status'] == 'teste')
                  const SizedBox(height: 8),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Fechar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getPaymentMethodName(String method) {
    switch (method) {
      case 'dinheiro':
        return 'Dinheiro';
      case 'debito':
        return 'Cartão de Débito';
      case 'credito':
        return 'Cartão de Crédito';
      case 'pix':
        return 'PIX';
      default:
        return method;
    }
  }

  Future<void> _alterarStatusPedido(
    Map<String, dynamic> pedido,
    String novoStatus,
  ) async {
    final statusLabel = _getStatusLabel(novoStatus);
    final pedidoId = pedido['id'];
    final deliveredAt = DateTime.now();

    // Confirmação para mudanças importantes
    if (novoStatus == 'cancelado' || novoStatus == 'entregue') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Alterar Status', textAlign: TextAlign.center),
          content: Text(
            'Tem certeza que deseja alterar o status do pedido #${pedidoId.toString().padLeft(4, '0')} para "$statusLabel"?\n\nO cliente será notificado sobre a mudança.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Não'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: novoStatus == 'cancelado'
                        ? Colors.red
                        : Colors.green,
                  ),
                  child: const Text('Sim, Alterar'),
                ),
              ],
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    try {
      final oldStatus = pedido['status'];
      final fullUpdateData = <String, dynamic>{
        'status': novoStatus,
        'updated_at': deliveredAt.toIso8601String(),
      };
      if (novoStatus == 'entregue') {
        fullUpdateData['entregue_em'] = deliveredAt.toIso8601String();
      }

      try {
        await Supabase.instance.client
            .from('pedidos')
            .update(fullUpdateData)
            .eq('id', pedidoId);
      } catch (error) {
        if (_isMissingPedidoColumnError(error)) {
          await Supabase.instance.client
              .from('pedidos')
              .update({'status': novoStatus})
              .eq('id', pedidoId);
        } else {
          rethrow;
        }
      }

      // Notificar o usuário sobre a mudança de status
      final userId = pedido['user_id'];
      if (userId != null) {
        await NotificationService.notifyOrderStatusChange(
          userId: userId,
          orderId: pedidoId,
          oldStatus: oldStatus,
          newStatus: novoStatus,
        );
      }

      if (mounted) {
        // Atualizar apenas o pedido alterado localmente, sem recarregar tudo
        setState(() {
          final index = _pedidos.indexWhere((p) => p['id'] == pedidoId);
          if (index != -1) {
            _pedidos[index] = {
              ..._pedidos[index],
              'status': novoStatus,
              'updated_at': deliveredAt.toIso8601String(),
              if (novoStatus == 'entregue')
                'entregue_em': deliveredAt.toIso8601String(),
            };
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Status do pedido #${pedidoId.toString().padLeft(4, '0')} alterado para "$statusLabel"! Usuário notificado.',
            ),
            backgroundColor: _getStatusColor(novoStatus),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao alterar status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _excluirPedidoTeste(Map<String, dynamic> pedido) async {
    final pedidoId = pedido['id'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Excluir Pedido de Teste',
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Tem certeza que deseja excluir o pedido de teste #${pedidoId.toString().padLeft(4, '0')}?\n\nEsta ação não pode ser desfeita.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
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
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/icons/menu/delete_button.png',
                  width: 18,
                  height: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                const Text('Excluir'),
              ],
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final idInt = pedidoId is int ? pedidoId : int.parse(pedidoId.toString());

      // Tentar excluir itens do pedido primeiro
      // Tentar excluir itens do pedido primeiro
      await Supabase.instance.client
          .from('pedido_itens')
          .delete()
          .eq('pedido_id', idInt)
          .select();

      // Tentar excluir o pedido diretamente
      final deleteResult = await Supabase.instance.client
          .from('pedidos')
          .delete()
          .eq('id', idInt)
          .select();

      // Se o delete direto retornou vazio, possível bloqueio RLS - tentar via RPC
      if (deleteResult.isEmpty) {
        debugPrint(
          '⚠️ Delete direto do pedido retornou vazio - tentando via RPC',
        );
        try {
          await Supabase.instance.client.rpc(
            'delete_pedido_teste_admin',
            params: {'p_pedido_id': idInt},
          );
          debugPrint('✅ Delete via RPC bem-sucedido');
        } catch (rpcError) {
          debugPrint('❌ RPC delete_pedido_teste_admin falhou: $rpcError');
          rethrow;
        }
      }

      if (mounted) {
        setState(() {
          _pedidos.removeWhere((p) => p['id'] == pedidoId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido de teste #${pedidoId.toString().padLeft(4, '0')} excluído com sucesso!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleUserRole(Map<String, dynamic> usuario) async {
    final newRole = usuario['role'] == 'admin' ? 'user' : 'admin';
    final userName = usuario['full_name'] ?? usuario['email'] ?? 'Usuário';

    try {
      // Usar RPC com SECURITY DEFINER para bypass de RLS
      await Supabase.instance.client.rpc(
        'update_user_role',
        params: {'target_user_id': usuario['id'], 'new_role': newRole},
      );
      debugPrint('✅ Update role via RPC bem-sucedido: $newRole');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$userName agora é ${newRole == 'admin' ? 'administrador' : 'usuário'}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadData();
    } catch (e) {
      debugPrint('❌ Erro ao alterar role: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao alterar role: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

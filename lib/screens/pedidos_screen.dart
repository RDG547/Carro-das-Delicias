import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/base_screen.dart';
import '../providers/admin_status_provider.dart';
import '../widgets/app_menu.dart';
import '../services/cart_service.dart';
import '../widgets/main_navigation_provider.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _isLoading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _pedidosSubscription;

  @override
  void initState() {
    super.initState();
    _loadPedidos();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    _pedidosSubscription?.cancel();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Escutar mudanças em tempo real na tabela de pedidos
    _pedidosSubscription = Supabase.instance.client
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .listen(
          (List<Map<String, dynamic>> data) {
            debugPrint(
              '🔔 Pedidos atualizados em tempo real: ${data.length} pedidos',
            );
            _processarPedidosRealtime(data);
          },
          onError: (error) {
            debugPrint('❌ Erro no stream de pedidos: $error');
          },
        );
  }

  Future<void> _processarPedidosRealtime(
    List<Map<String, dynamic>> pedidosData,
  ) async {
    try {
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

        final itens = (itensResponse as List).map<Map<String, dynamic>>((item) {
          final produto = item['produtos'];
          debugPrint('🔍 Real-time item completo: $item');
          debugPrint('🔍 Real-time tamanho: ${item['tamanho_selecionado']}');
          debugPrint('🔍 Real-time chaves: ${item.keys.toList()}');
          return {
            'nome': produto?['nome'] ?? 'Produto não encontrado',
            'quantidade': item['quantidade'],
            'preco': item['preco_unitario'],
            'subtotal': item['subtotal'],
            'observacoes': item['observacoes'],
            'tamanho': item['tamanho_selecionado'],
          };
        }).toList();

        pedidosProcessados.add({
          'id': pedido['id'],
          'data': pedido['created_at'],
          'status': pedido['status'],
          'total': pedido['total'],
          'cliente_nome': pedido['cliente_nome'],
          'cliente_telefone': pedido['cliente_telefone'],
          'endereco_completo': pedido['endereco_completo'],
          'metodo_pagamento': pedido['metodo_pagamento'],
          'valor_troco': pedido['valor_troco'],
          'observacoes': pedido['observacoes'],
          'itens': itens,
        });
      }

      if (mounted) {
        setState(() {
          _pedidos = pedidosProcessados;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao processar pedidos em tempo real: $e');
    }
  }

  Future<void> _loadPedidos() async {
    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() {
          _pedidos = [];
          _isLoading = false;
        });
        return;
      }

      // Carregar pedidos do usuário atual do banco de dados
      final response = await Supabase.instance.client
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
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      // Processar os dados dos pedidos
      final pedidosProcessados = response.map<Map<String, dynamic>>((pedido) {
        final itens = (pedido['pedido_itens'] as List)
            .map<Map<String, dynamic>>((item) {
              final produto = item['produtos'];
              debugPrint('🔍 Item completo do banco: $item');
              debugPrint(
                '🔍 Tamanho selecionado: ${item['tamanho_selecionado']}',
              );
              debugPrint('🔍 Chaves disponíveis: ${item.keys.toList()}');
              return {
                'nome': produto?['nome'] ?? 'Produto não encontrado',
                'quantidade': item['quantidade'],
                'preco': item['preco_unitario'],
                'subtotal': item['subtotal'],
                'observacoes': item['observacoes'],
                'tamanho': item['tamanho_selecionado'],
              };
            })
            .toList();

        return {
          'id': pedido['id'],
          'data': pedido['created_at'],
          'status': pedido['status'],
          'total': pedido['total'],
          'cliente_nome': pedido['cliente_nome'],
          'cliente_telefone': pedido['cliente_telefone'],
          'endereco_completo': pedido['endereco_completo'],
          'metodo_pagamento': pedido['metodo_pagamento'],
          'valor_troco': pedido['valor_troco'],
          'observacoes': pedido['observacoes'],
          'itens': itens,
        };
      }).toList();

      setState(() {
        _pedidos = pedidosProcessados;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar pedidos: $e'),
            backgroundColor: Colors.red,
          ),
        );

        // Se houver erro, carregar dados de exemplo como fallback
        setState(() {
          _pedidos = [
            {
              'id': 0,
              'data': DateTime.now().toIso8601String(),
              'status': 'Erro ao carregar',
              'total': 0.0,
              'itens': [
                {
                  'nome': 'Erro ao carregar pedidos',
                  'quantidade': 1,
                  'preco': 0.0,
                },
              ],
            },
          ];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatPrice(dynamic price) {
    if (price is num) {
      return 'R\$ ${price.toStringAsFixed(2).replaceAll('.', ',')}';
    }
    return 'R\$ 0,00';
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$day/$month/$year às $hour:$minute';
    } catch (e) {
      return dateStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return Colors.orange;
      case 'confirmado':
        return Colors.blue;
      case 'entregue':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      case 'em preparo':
        return Colors.orange;
      case 'saiu para entrega':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return Icons.pending_actions;
      case 'confirmado':
        return Icons.check_circle_outline;
      case 'entregue':
        return Icons.check_circle;
      case 'cancelado':
        return Icons.cancel;
      case 'em preparo':
        return Icons.kitchen;
      case 'saiu para entrega':
        return Icons.delivery_dining;
      default:
        return Icons.help;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return 'Pendente';
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
      default:
        return status;
    }
  }

  void _goToHome() {
    debugPrint('🔙 Botão de voltar pressionado na tela de pedidos');
    // Pop até a primeira rota OU apenas um pop se já estiver próximo
    Navigator.of(context).pop();
  }

  Future<void> _cancelarPedido(Map<String, dynamic> pedido) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Pedido', textAlign: TextAlign.center),
        content: Text(
          'Tem certeza que deseja cancelar o pedido #${pedido['id'].toString().padLeft(4, '0')}?\n\nEsta ação não pode ser desfeita.',
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Sim, Cancelar'),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client
            .from('pedidos')
            .update({'status': 'cancelado'})
            .eq('id', pedido['id']);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Pedido #${pedido['id'].toString().padLeft(4, '0')} cancelado com sucesso!',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }

        // Recarregar a lista de pedidos
        _loadPedidos();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao cancelar pedido: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _mostrarDetalhes(Map<String, dynamic> pedido) {
    showDialog(
      context: context,
      builder: (context) => _DetalhesDialog(pedido: pedido),
    );
  }

  Future<void> _refazerPedido(Map<String, dynamic> pedido) async {
    try {
      final cartService = CartService();
      final itens = pedido['itens'] as List<dynamic>? ?? [];

      debugPrint('🔄 Refazendo pedido #${pedido['id']}');
      debugPrint('🔄 Total de itens: ${itens.length}');

      if (itens.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Este pedido não possui itens'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      int itensAdicionados = 0;
      List<String> produtosIndisponiveis = [];

      // Adicionar todos os itens do pedido ao carrinho
      for (var item in itens) {
        try {
          final produtoId = item['produto_id'];
          debugPrint('🔄 Processando item: ${item['nome']} (ID: $produtoId)');

          if (produtoId == null) {
            debugPrint('❌ Produto ID é null');
            produtosIndisponiveis.add(item['nome'] ?? 'Produto');
            continue;
          }

          // Buscar produto completo - primeiro verificar se existe
          final produtoResponse = await Supabase.instance.client
              .from('produtos')
              .select('*, categorias!categoria_id(nome, icone)')
              .eq('id', produtoId)
              .maybeSingle();

          debugPrint(
            '🔄 Resposta da busca: ${produtoResponse != null ? 'Produto encontrado' : 'Produto não encontrado'}',
          );

          if (produtoResponse == null) {
            // Produto não existe mais
            debugPrint('❌ Produto não existe mais: ${item['nome']}');
            produtosIndisponiveis.add(item['nome'] ?? 'Produto');
            continue;
          }

          // Verificar se o produto está ativo
          final ativo = produtoResponse['ativo'] ?? false;
          debugPrint('🔄 Produto ativo: $ativo');

          if (!ativo) {
            debugPrint('❌ Produto inativo: ${item['nome']}');
            produtosIndisponiveis.add(item['nome'] ?? 'Produto');
            continue;
          }

          // Processar produto com categorias
          final produto = {
            ...produtoResponse,
            'categoria_nome': produtoResponse['categorias']?['nome'],
            'categoria_icone': produtoResponse['categorias']?['icone'],
          };

          debugPrint('✅ Adicionando ao carrinho: ${produto['nome']}');
          await cartService.addItem(
            produto,
            quantidade: item['quantidade'] ?? 1,
            observacoes: item['observacoes'],
          );

          itensAdicionados++;
          debugPrint('✅ Item adicionado com sucesso!');
        } catch (e) {
          debugPrint('❌ Erro ao adicionar item: $e');
          produtosIndisponiveis.add(item['nome'] ?? 'Produto');
        }
      }

      debugPrint('🔄 Total adicionados: $itensAdicionados');
      debugPrint('🔄 Total indisponíveis: ${produtosIndisponiveis.length}');

      if (mounted) {
        if (itensAdicionados > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$itensAdicionados ${itensAdicionados == 1 ? 'item adicionado' : 'itens adicionados'} ao carrinho!',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Ver Carrinho',
                textColor: Colors.white,
                onPressed: () {
                  // Navega para o carrinho usando o PageView do MainScreen
                  final provider = MainNavigationProvider.of(context);
                  if (provider?.navigateToPageDirect != null) {
                    provider!.navigateToPageDirect!(2); // Índice 2 = Carrinho
                  }
                },
              ),
            ),
          );

          // Avisar sobre produtos indisponíveis se houver
          if (produtosIndisponiveis.isNotEmpty) {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Produtos não disponíveis: ${produtosIndisponiveis.join(', ')}',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Nenhum produto deste pedido está disponível no momento',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Erro ao refazer pedido: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao refazer pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuestMode = user == null;
    final adminProvider = AdminStatusProvider.of(context);
    final isAdmin = adminProvider?.isAdmin ?? false;

    return BaseScreen(
      title: 'Meus Pedidos',
      showBackButton: true,
      onBackPressed: _goToHome,
      actions: [AppMenu(isGuestMode: isGuestMode, isAdmin: isAdmin)],
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pedidos.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum pedido encontrado',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Seus pedidos aparecerão aqui após a compra',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadPedidos,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _pedidos.length,
                itemBuilder: (context, index) {
                  final pedido = _pedidos[index];
                  final statusColor = _getStatusColor(pedido['status']);
                  final statusIcon = _getStatusIcon(pedido['status']);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.all(16),
                      childrenPadding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(statusIcon, color: statusColor, size: 24),
                      ),
                      title: Text(
                        'Pedido #${pedido['id']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(pedido['data']),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _getStatusLabel(pedido['status']),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatPrice(pedido['total']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Itens do Pedido:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...List.generate(pedido['itens'].length, (
                                itemIndex,
                              ) {
                                final item = pedido['itens'][itemIndex];
                                final tamanho = item['tamanho'];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black,
                                            ),
                                            children: [
                                              TextSpan(
                                                text:
                                                    '${item['quantidade']}x ${item['nome']}',
                                              ),
                                              if (tamanho != null &&
                                                  tamanho.toString().isNotEmpty)
                                                TextSpan(
                                                  text: ' ($tamanho)',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.purple[700],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatPrice(item['preco']),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const Divider(height: 16),
                              Row(
                                children: [
                                  const Text(
                                    'Total:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatPrice(pedido['total']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Botões de ação
                        const SizedBox(height: 12),
                        Column(
                          children: [
                            // Primeira linha de botões
                            Row(
                              children: [
                                // Botão ver detalhes
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _mostrarDetalhes(pedido),
                                    icon: const Icon(
                                      Icons.info_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Ver Detalhes'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blue,
                                      side: const BorderSide(
                                        color: Colors.blue,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Botão refazer pedido
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _refazerPedido(pedido),
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Refazer'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Botão de cancelar (apenas para pendentes/confirmados)
                            if (pedido['status'] == 'pendente' ||
                                pedido['status'] == 'confirmado') ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _cancelarPedido(pedido),
                                  icon: const Icon(Icons.cancel, size: 18),
                                  label: const Text('Cancelar Pedido'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// Widget para exibir detalhes completos do pedido com histórico
class _DetalhesDialog extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const _DetalhesDialog({required this.pedido});

  @override
  State<_DetalhesDialog> createState() => _DetalhesDialogState();
}

class _DetalhesDialogState extends State<_DetalhesDialog> {
  List<Map<String, dynamic>> _historico = [];
  bool _isLoadingHistorico = true;
  StreamSubscription<List<Map<String, dynamic>>>? _historicoSubscription;
  late Map<String, dynamic> _pedidoAtual;

  @override
  void initState() {
    super.initState();
    _pedidoAtual = widget.pedido;
    _carregarHistorico();
    _setupHistoricoRealtimeSubscription();
    _setupPedidoRealtimeSubscription();
  }

  @override
  void dispose() {
    _historicoSubscription?.cancel();
    super.dispose();
  }

  void _setupHistoricoRealtimeSubscription() {
    // Escutar mudanças em tempo real no histórico do pedido
    _historicoSubscription = Supabase.instance.client
        .from('pedido_historico')
        .stream(primaryKey: ['id'])
        .eq('pedido_id', widget.pedido['id'])
        .order('created_at', ascending: true)
        .listen(
          (List<Map<String, dynamic>> data) {
            debugPrint(
              '🔔 Histórico atualizado em tempo real: ${data.length} eventos',
            );
            if (mounted) {
              setState(() {
                _historico = data;
                _isLoadingHistorico = false;
              });
            }
          },
          onError: (error) {
            debugPrint('❌ Erro no stream de histórico: $error');
          },
        );
  }

  void _setupPedidoRealtimeSubscription() {
    // Escutar mudanças no pedido atual
    Supabase.instance.client
        .from('pedidos')
        .stream(primaryKey: ['id'])
        .eq('id', widget.pedido['id'])
        .listen(
          (List<Map<String, dynamic>> data) {
            if (data.isNotEmpty && mounted) {
              setState(() {
                _pedidoAtual = {..._pedidoAtual, 'status': data[0]['status']};
              });
            }
          },
          onError: (error) {
            debugPrint('❌ Erro no stream do pedido: $error');
          },
        );
  }

  Future<void> _carregarHistorico() async {
    try {
      final response = await Supabase.instance.client
          .from('pedido_historico')
          .select()
          .eq('pedido_id', widget.pedido['id'])
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _historico = List<Map<String, dynamic>>.from(response);
          _isLoadingHistorico = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico: $e');
      // Se não houver tabela de histórico, criar um histórico básico
      if (mounted) {
        setState(() {
          _historico = [
            {
              'status_novo': widget.pedido['status'],
              'created_at': widget.pedido['data'],
              'observacao': 'Status atual',
            },
          ];
          _isLoadingHistorico = false;
        });
      }
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$day/$month/$year às $hour:$minute';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatPrice(dynamic price) {
    if (price is num) {
      return 'R\$ ${price.toStringAsFixed(2).replaceAll('.', ',')}';
    }
    return 'R\$ 0,00';
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return Colors.orange;
      case 'confirmado':
        return Colors.blue;
      case 'em preparo':
        return Colors.purple;
      case 'saiu para entrega':
        return Colors.indigo;
      case 'entregue':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return Icons.pending_actions;
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
      default:
        return Icons.shopping_bag;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pendente':
        return 'Pendente';
      case 'confirmado':
        return 'Confirmado';
      case 'em preparo':
        return 'Em Preparo';
      case 'saiu para entrega':
        return 'Saiu para Entrega';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getMetodoPagamentoLabel(String metodo) {
    switch (metodo.toLowerCase()) {
      case 'dinheiro':
        return 'Dinheiro';
      case 'pix':
        return 'PIX';
      case 'cartao_credito':
        return 'Cartão de Crédito';
      case 'cartao_debito':
        return 'Cartão de Débito';
      default:
        return metodo;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _getStatusIcon(_pedidoAtual['status']),
            color: _getStatusColor(_pedidoAtual['status']),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pedido #${widget.pedido['id'].toString().padLeft(4, '0')}',
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Data e hora do pedido
              _buildDetailRow(
                Icons.calendar_today,
                'Pedido Realizado',
                _formatDate(widget.pedido['data']),
                Colors.blue,
              ),
              const SizedBox(height: 12),

              // Status atual (atualizado em tempo real)
              _buildDetailRow(
                _getStatusIcon(_pedidoAtual['status']),
                'Status Atual',
                _getStatusLabel(_pedidoAtual['status']),
                _getStatusColor(_pedidoAtual['status']),
              ),
              const SizedBox(height: 12),

              // Cliente
              _buildDetailRow(
                Icons.person,
                'Cliente',
                widget.pedido['cliente_nome'] ?? 'Não informado',
                Colors.purple,
              ),
              const SizedBox(height: 12),

              // Telefone
              _buildDetailRow(
                Icons.phone,
                'Telefone',
                widget.pedido['cliente_telefone'] ?? 'Não informado',
                Colors.green,
              ),
              const SizedBox(height: 12),

              // Endereço
              _buildDetailRow(
                Icons.location_on,
                'Endereço',
                '${widget.pedido['endereco_completo'] ?? ''}\n${widget.pedido['bairro'] ?? ''}, ${widget.pedido['cidade'] ?? ''}${widget.pedido['cep'] != null ? '\nCEP: ${widget.pedido['cep']}' : ''}',
                Colors.orange,
              ),
              const SizedBox(height: 12),

              // Método de pagamento
              _buildDetailRow(
                Icons.payment,
                'Pagamento',
                _getMetodoPagamentoLabel(
                  widget.pedido['metodo_pagamento'] ?? 'dinheiro',
                ),
                Colors.teal,
              ),

              // Troco (se pagamento em dinheiro)
              if (widget.pedido['valor_troco'] != null &&
                  widget.pedido['valor_troco'] > 0) ...[
                const SizedBox(height: 12),
                _buildDetailRow(
                  Icons.money,
                  'Troco para',
                  _formatPrice(widget.pedido['valor_troco']),
                  Colors.green,
                ),
              ],

              // Observações
              if (widget.pedido['observacoes'] != null &&
                  widget.pedido['observacoes'].toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDetailRow(
                  Icons.note,
                  'Observações',
                  widget.pedido['observacoes'],
                  Colors.grey[700]!,
                ),
              ],

              const Divider(height: 24),

              // Total
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatPrice(widget.pedido['total']),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),

              // Histórico de Status
              const Divider(height: 24),

              // Itens do Pedido
              const Text(
                '🛒 Itens do Pedido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              ...(widget.pedido['itens'] as List<dynamic>? ?? []).map((item) {
                final tamanho = item['tamanho'];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item['nome'] ?? 'Produto',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (tamanho != null &&
                                    tamanho.toString().isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[100],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.purple[300]!,
                                      ),
                                    ),
                                    child: Text(
                                      tamanho.toString(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple[700],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Quantidade: ${item['quantidade']} × ${_formatPrice(item['preco'])}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (item['observacoes'] != null &&
                                item['observacoes'].toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Obs: ${item['observacoes']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatPrice(
                          item['subtotal'] ??
                              (item['quantidade'] * item['preco']),
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const Divider(height: 24),

              const Text(
                '📋 Histórico do Pedido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              _isLoadingHistorico
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _historico.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Nenhum histórico disponível',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : Column(
                      children: _historico.map((evento) {
                        final statusNovo = evento['status_novo'] ?? '';
                        final statusAnterior = evento['status_anterior'];
                        final dataHora = evento['created_at'];
                        final observacao = evento['observacao'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              statusNovo,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getStatusColor(
                                statusNovo,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _getStatusIcon(statusNovo),
                                color: _getStatusColor(statusNovo),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getStatusLabel(statusNovo),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: _getStatusColor(statusNovo),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDate(dataHora),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    if (statusAnterior != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'De: ${_getStatusLabel(statusAnterior)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ),
                                    if (observacao != null &&
                                        observacao.toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          observacao,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
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
    );
  }
}

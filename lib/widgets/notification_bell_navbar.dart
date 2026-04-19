import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../services/notification_service.dart';

class NotificationBellNavbar extends StatefulWidget {
  const NotificationBellNavbar({super.key});

  @override
  State<NotificationBellNavbar> createState() => NotificationBellNavbarState();
}

class NotificationBellNavbarState extends State<NotificationBellNavbar>
    with SingleTickerProviderStateMixin {
  int _unreadCount = 0;
  List<Map<String, dynamic>> _notifications = [];
  OverlayEntry? _overlayEntry;
  bool _isMenuOpen = false;
  RealtimeChannel? _updateChannel;
  ScaffoldMessengerState? _scaffoldMessenger;
  late final AnimationController _menuAnimationController;
  bool _isClosingOverlay = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _menuAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _loadNotifications();
    _startListeningToUpdates();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isMenuOpen = false;
    _menuAnimationController.dispose();
    _updateChannel?.unsubscribe();
    super.dispose();
  }

  void _startListeningToUpdates() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint(
        '⚠️ Usuário não logado - não pode escutar atualizações no navbar',
      );
      return;
    }

    // Remover canal antigo se existir
    if (_updateChannel != null) {
      debugPrint('♻️ Removendo canal antigo do navbar');
      _updateChannel?.unsubscribe();
      _updateChannel = null;
    }

    // Criar canal ÚNICO para atualizar a UI quando houver mudanças
    final channelName = 'notification_updates_navbar:${user.id}';
    debugPrint('🔌 Criando canal Realtime para navbar: $channelName');

    _updateChannel = Supabase.instance.client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint('🔄 Atualização de notificação detectada no navbar!');
            debugPrint('   Evento: ${payload.eventType}');
            if (payload.eventType == PostgresChangeEvent.delete) {
              debugPrint('   Registro deletado: ${payload.oldRecord}');
            } else {
              debugPrint('   Dados: ${payload.newRecord}');
            }

            // Recarregar notificações quando houver mudanças (insert, update, delete)
            if (mounted) {
              debugPrint('   ♻️ Recarregando notificações do navbar...');
              _loadNotifications();
            }
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('✅ Canal do navbar CONECTADO com sucesso!');
          } else if (status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('⏱️ Timeout ao conectar canal do navbar');
          } else if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('❌ Erro no canal do navbar: $error');
          }
        });

    debugPrint(
      '👀 Navbar configurado para escutar atualizações de notificações',
    );
  }

  Future<void> _loadNotifications() async {
    if (!mounted) {
      debugPrint(
        '⚠️ Widget não montado - ignorando carregamento de notificações',
      );
      return;
    }

    try {
      debugPrint('📥 Carregando notificações do navbar...');
      final count = await NotificationService.getUnreadCount();
      final notifications = await NotificationService.getUserNotifications(
        limit: 10,
        onlyUnread: false,
      );

      debugPrint(
        '📊 Notificações carregadas: ${notifications.length} total, $count não lidas',
      );

      if (mounted) {
        setState(() {
          _unreadCount = count;
          _notifications = notifications;
        });
        debugPrint('✅ UI do navbar atualizada!');
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar notificações: $e');
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Agora';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}min atrás';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h atrás';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d atrás';
    } else {
      return '${(difference.inDays / 7).floor()}sem atrás';
    }
  }

  IconData _getTypeIcon(String? type) {
    switch (type) {
      case 'order':
        return Icons.shopping_bag;
      case 'success':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning;
      case 'info':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'order':
        return Colors.blue;
      case 'success':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Future<void> _removeOverlay({bool immediate = false}) async {
    if (_overlayEntry == null) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isMenuOpen = false;
        });
      } else {
        _isMenuOpen = false;
      }
      return;
    }

    if (!immediate) {
      if (_isClosingOverlay) return;
      _isClosingOverlay = true;
      try {
        await _menuAnimationController.reverse();
      } catch (_) {
        // Ignora falhas de animação se o widget for desmontado no meio.
      }
    } else {
      _menuAnimationController.stop();
      _menuAnimationController.value = 0;
    }

    _overlayEntry?.remove();
    _overlayEntry = null;
    _isClosingOverlay = false;
    if (mounted && !_isDisposed) {
      setState(() {
        _isMenuOpen = false;
      });
    } else {
      _isMenuOpen = false;
    }
  }

  void _toggleMenu() {
    if (_isMenuOpen) {
      _removeOverlay();
      return;
    }

    _scaffoldMessenger = ScaffoldMessenger.of(context);

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Altura dinâmica mais conservadora: header 90px + 60px por notificação
    final baseHeight = 110.0;
    final itemHeight = 60.0;
    final maxHeight = screenHeight * 0.65; // Reduzido de 70% para 65%

    final dynamicHeight = _notifications.isEmpty
        ? 180.0 // Altura fixa quando vazio
        : (baseHeight + (_notifications.length * itemHeight)).clamp(
            200.0,
            maxHeight,
          );

    final menuWidth = screenWidth * 0.75;
    final menuLeft = (screenWidth - menuWidth) / 2;
    final menuBottom = screenHeight - offset.dy + 20; // Aumentado de 8 para 20

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Background tap to close - leave bottom 80px for snackbar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: 80,
            child: GestureDetector(
              onTap: _removeOverlay,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: menuLeft,
            bottom: menuBottom,
            width: menuWidth,
            child: AnimatedBuilder(
              animation: _menuAnimationController,
              builder: (context, child) {
                final animationValue = Curves.easeOutCubic.transform(
                  _menuAnimationController.value,
                );
                return Transform.scale(
                  scale: 0.92 + (0.08 * animationValue),
                  alignment: Alignment.bottomCenter,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - animationValue)),
                    child: Opacity(opacity: animationValue, child: child),
                  ),
                );
              },
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: BoxConstraints(maxHeight: dynamicHeight),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildMenuContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _menuAnimationController.forward(from: 0);
    if (mounted) {
      setState(() {
        _isMenuOpen = true;
      });
    } else {
      _isMenuOpen = true;
    }
  }

  Widget _buildMenuContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Notificações',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (_unreadCount > 0)
                    TextButton.icon(
                      onPressed: () async {
                        _removeOverlay();
                        await NotificationService.markAllAsRead();
                        _loadNotifications();
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 14),
                      label: const Text(
                        'Marcar lidas',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (_notifications.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        // Fechar o overlay antes de abrir o dialog
                        _removeOverlay();

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text(
                              'Limpar notificações',
                              textAlign: TextAlign.center,
                            ),
                            content: const Text(
                              'Deseja realmente excluir todas as notificações?',
                              textAlign: TextAlign.center,
                            ),
                            actionsAlignment: MainAxisAlignment.center,
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
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
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

                        if (confirm == true && mounted) {
                          debugPrint('🗑️ Deletando todas as notificações...');
                          await NotificationService.deleteAllNotifications();
                          debugPrint(
                            '♻️ Recarregando lista de notificações...',
                          );
                          await _loadNotifications();
                          debugPrint('✅ Notificações limpas com sucesso!');
                        }
                      },
                      icon: Image.asset(
                        'assets/icons/menu/delete_button.png',
                        width: 14,
                        height: 14,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'Limpar tudo',
                        style: TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
            ],
          ),
        ),

        // Lista de notificações
        Flexible(
          child: _notifications.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.notifications_off_outlined,
                        size: 40,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Nenhuma notificação',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final isRead = notification['is_read'] ?? false;
                    final createdAt = DateTime.tryParse(
                      notification['created_at'] ?? '',
                    )?.toLocal();
                    final timeAgo = createdAt != null
                        ? _getTimeAgo(createdAt)
                        : '';

                    return ClipRect(
                      child: Dismissible(
                        key: ValueKey(notification['id']),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) {
                          final notificationId = notification['id'];
                          final notificationIndex = index;
                          final removedNotification = Map<String, dynamic>.from(
                            notification,
                          );
                          final wasUnread = !(notification['is_read'] ?? false);

                          debugPrint(
                            '🗑️ Notificação $notificationId removida por swipe',
                          );

                          setState(() {
                            _notifications.removeAt(notificationIndex);
                            if (wasUnread) {
                              _unreadCount = (_unreadCount - 1)
                                  .clamp(0, double.infinity)
                                  .toInt();
                            }
                          });
                          _overlayEntry?.markNeedsBuild();

                          bool undone = false;
                          final messenger = _scaffoldMessenger;
                          if (messenger == null) return;
                          Timer? closeTimer;
                          late final ScaffoldFeatureController<
                            SnackBar,
                            SnackBarClosedReason
                          >
                          controller;

                          messenger.clearSnackBars();
                          controller = messenger.showSnackBar(
                            SnackBar(
                              duration: const Duration(seconds: 5),
                              content: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 5.0, end: 0.0),
                                duration: const Duration(seconds: 5),
                                builder: (context, value, child) {
                                  return Row(
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            CircularProgressIndicator(
                                              value: value / 5,
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                    Color
                                                  >(Colors.white),
                                              backgroundColor: Colors.white24,
                                            ),
                                            Text(
                                              '${value.ceil()}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Text('Notificação excluída'),
                                    ],
                                  );
                                },
                              ),
                              action: SnackBarAction(
                                label: 'Desfazer',
                                textColor: Colors.yellow,
                                onPressed: () {
                                  undone = true;
                                  closeTimer?.cancel();
                                  controller.close();
                                  if (mounted) {
                                    setState(() {
                                      final insertAt = notificationIndex.clamp(
                                        0,
                                        _notifications.length,
                                      );
                                      _notifications.insert(
                                        insertAt,
                                        removedNotification,
                                      );
                                      if (wasUnread) {
                                        _unreadCount++;
                                      }
                                    });
                                    _overlayEntry?.markNeedsBuild();
                                  }
                                  debugPrint(
                                    '↩️ Notificação $notificationId restaurada',
                                  );
                                },
                              ),
                            ),
                          );

                          closeTimer = Timer(const Duration(seconds: 5), () {
                            controller.close();
                          });

                          controller.closed.then((reason) async {
                            closeTimer?.cancel();
                            if (!undone) {
                              await NotificationService.deleteNotification(
                                notificationId,
                              );
                              debugPrint(
                                '✅ Notificação $notificationId deletada permanentemente',
                              );
                            }
                          });
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: Image.asset(
                            'assets/icons/menu/delete_button.png',
                            width: 28,
                            height: 28,
                            color: Colors.white,
                          ),
                        ),
                        child: InkWell(
                          onTap: () async {
                            if (!isRead) {
                              await NotificationService.markAsRead(
                                notification['id'],
                              );
                              _loadNotifications();
                            }
                            _removeOverlay();
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? null
                                  : Colors.blue.withValues(alpha: 0.05),
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _getTypeColor(
                                      notification['type'],
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    _getTypeIcon(notification['type']),
                                    color: _getTypeColor(notification['type']),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              notification['title'] ?? '',
                                              style: TextStyle(
                                                fontWeight: isRead
                                                    ? FontWeight.normal
                                                    : FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.black,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!isRead)
                                            Container(
                                              width: 7,
                                              height: 7,
                                              margin: const EdgeInsets.only(
                                                left: 4,
                                              ),
                                              decoration: const BoxDecoration(
                                                color: Colors.blue,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        notification['message'] ?? '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[700],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (timeAgo.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          timeAgo,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ), // Dismissible
                    ); // ClipRect
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(_isMenuOpen ? Icons.notifications : Icons.notifications_outlined),
        if (_unreadCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  void toggleMenuFromOutside() {
    _toggleMenu();
  }

  /// Método público para forçar atualização das notificações
  void refreshNotifications() {
    debugPrint('🔄 Atualização manual solicitada');
    _loadNotifications();
  }
}

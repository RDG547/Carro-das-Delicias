import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unreadCount = 0;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _startListeningToUpdates();
  }

  void _startListeningToUpdates() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Escutar mudanças em tempo real
    Supabase.instance.client
        .channel('notification_updates:${user.id}')
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
            // Recarregar notificações quando houver mudanças
            _loadNotifications();
          },
        )
        .subscribe();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;

    try {
      final count = await NotificationService.getUnreadCount();
      final notifications = await NotificationService.getUserNotifications(
        limit: 10,
        onlyUnread: false,
      );

      if (mounted) {
        setState(() {
          _unreadCount = count;
          _notifications = notifications;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar notificações: $e');
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Altura dinâmica: 100px base + 80px por notificação, máximo 70% da tela
    final dynamicHeight = (180 + (_notifications.length * 80.0)).clamp(
      200.0,
      screenHeight * 0.7,
    );

    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      constraints: BoxConstraints(
        minWidth: screenWidth * 0.65,
        maxWidth: screenWidth * 0.75,
        maxHeight: dynamicHeight,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      tooltip: 'Notificações',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined, color: Colors.white),
          if (_unreadCount > 0)
            Positioned(
              right: 0,
              top: 0,
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
      ),
      itemBuilder: (context) => [
        // Header do menu
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            children: [
              const Text(
                'Notificações',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_unreadCount > 0) ...[
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await NotificationService.markAllAsRead();
                        _loadNotifications();
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text(
                        'Marcar lidas',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_notifications.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Limpar notificações'),
                            content: const Text(
                              'Deseja realmente excluir todas as notificações?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Excluir'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && context.mounted) {
                          Navigator.pop(context);
                          await NotificationService.deleteAllNotifications();
                          _loadNotifications();
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text(
                        'Limpar tudo',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                ],
              ),
              const Divider(),
            ],
          ),
        ),

        // Lista de notificações ou mensagem vazia
        if (_notifications.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Nenhuma notificação',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ..._notifications.map((notification) {
            final isRead = notification['is_read'] ?? false;
            final createdAt = DateTime.tryParse(
              notification['created_at'] ?? '',
            );
            final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '';

            return PopupMenuItem<String>(
              padding: EdgeInsets.zero,
              onTap: () async {
                if (!isRead) {
                  await NotificationService.markAsRead(notification['id']);
                  _loadNotifications();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRead ? null : Colors.blue.withValues(alpha: 0.05),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getTypeColor(
                          notification['type'],
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getTypeIcon(notification['type']),
                        color: _getTypeColor(notification['type']),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                    fontSize: 14,
                                    color: Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(left: 4),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notification['message'] ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (timeAgo.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              timeAgo,
                              style: TextStyle(
                                fontSize: 11,
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
            );
          }),
      ],
    );
  }
}

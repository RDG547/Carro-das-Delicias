import 'package:flutter/material.dart';

import '../services/notification_service.dart';

class NotificationMenuEntry extends PopupMenuEntry<String> {
  final int unreadCount;
  final ValueChanged<int> onUnreadCountChanged;

  const NotificationMenuEntry({
    super.key,
    required this.unreadCount,
    required this.onUnreadCountChanged,
  });

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(String? value) => false;

  @override
  State<NotificationMenuEntry> createState() => _NotificationMenuEntryState();
}

class _NotificationMenuEntryState extends State<NotificationMenuEntry> {
  int _unreadCount = 0;
  List<Map<String, dynamic>> _notifications = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _unreadCount = widget.unreadCount;
    _loadNotifications();
  }

  @override
  void didUpdateWidget(covariant NotificationMenuEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unreadCount != widget.unreadCount) {
      _unreadCount = widget.unreadCount;
    }
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final count = await NotificationService.getUnreadCount();
    final notifications = await NotificationService.getUserNotifications(
      limit: 10,
      onlyUnread: false,
    );

    if (!mounted) return;
    setState(() {
      _unreadCount = count;
      _notifications = notifications;
      _isLoading = false;
    });
    widget.onUnreadCountChanged(count);
  }

  Future<void> _markAllAsRead() async {
    await NotificationService.markAllAsRead();
    await _loadNotifications();
  }

  Future<void> _deleteAll() async {
    await NotificationService.deleteAllNotifications();
    await _loadNotifications();
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    if (notification['is_read'] == true) return;
    final id = notification['id'];
    if (id is int) {
      await NotificationService.markAsRead(id);
      await _loadNotifications();
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) return 'Agora';
    if (difference.inMinutes < 60) return '${difference.inMinutes}min atrás';
    if (difference.inHours < 24) return '${difference.inHours}h atrás';
    if (difference.inDays < 7) return '${difference.inDays}d atrás';
    return '${(difference.inDays / 7).floor()}sem atrás';
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
    final width = MediaQuery.sizeOf(context).width.clamp(320.0, 420.0) * 0.82;

    return SizedBox(
      width: width,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: _buildLeadingIcon(),
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  'Notificações',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              if (_notifications.isNotEmpty) _buildActions(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: _notifications.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          return _buildNotificationItem(_notifications[index]);
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.indigo[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.notifications_rounded, color: Colors.indigo[700]),
        ),
        if (_unreadCount > 0)
          Positioned(right: -4, top: -4, child: _Badge(count: _unreadCount)),
      ],
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (_unreadCount > 0)
            Expanded(
              child: TextButton.icon(
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Marcar lidas'),
              ),
            ),
          if (_unreadCount > 0) const SizedBox(width: 6),
          Expanded(
            child: TextButton.icon(
              onPressed: _deleteAll,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Limpar'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 36,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'Nenhuma notificação',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    final isRead = notification['is_read'] ?? false;
    final createdAt = DateTime.tryParse(
      notification['created_at']?.toString() ?? '',
    )?.toLocal();
    final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '';
    final typeColor = _getTypeColor(notification['type']?.toString());

    return InkWell(
      onTap: () => _markAsRead(notification),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isRead ? Colors.grey[50] : Colors.blue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getTypeIcon(notification['type']?.toString()),
                color: typeColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification['title']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isRead
                                ? FontWeight.w500
                                : FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification['message']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  if (timeAgo.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      timeAgo,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}

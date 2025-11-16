import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'permission_service.dart';

class NotificationService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static RealtimeChannel? _notificationChannel;

  /// Inicializar serviço de notificações locais
  static Future<void> initialize() async {
    if (_initialized) return;

    // Solicitar permissões de notificação (obrigatório no Android 13+)
    await PermissionService.requestNotificationPermissions();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );

    // Criar canal de notificação no Android para melhor controle
    const androidChannel = AndroidNotificationChannel(
      'carrodasdelicias_channel',
      'Carro das Delícias',
      description: 'Notificações de pedidos e atualizações',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    _initialized = true;
    debugPrint('✅ NotificationService inicializado');
  }

  /// Iniciar escuta de notificações em tempo real
  static void startListeningToNotifications() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('⚠️ Usuário não logado, não é possível escutar notificações');
      return;
    }

    // Se já está escutando, remover canal antigo primeiro
    if (_notificationChannel != null) {
      debugPrint('♻️ Removendo canal de notificação antigo para recriar');
      _notificationChannel?.unsubscribe();
      _notificationChannel = null;
    }

    // Criar canal único para escutar notificações do usuário
    final channelName = 'notifications:${user.id}';
    debugPrint('🔌 Criando canal Realtime principal: $channelName');

    _notificationChannel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint('📬 Nova notificação recebida via Realtime!');
            debugPrint('   Dados: ${payload.newRecord}');
            final notification = payload.newRecord;

            // Mostrar notificação push local com ID único
            showLocalNotification(
              title: notification['title'] ?? 'Nova Notificação',
              body: notification['message'] ?? '',
              payload: notification['data']?.toString(),
              id: notification['id'] ?? 0, // ID único baseado no banco
            );
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('✅ Canal principal de notificações CONECTADO!');
          } else if (status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('⏱️ Timeout ao conectar canal principal');
          } else if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('❌ Erro no canal principal: $error');
          }
        });

    debugPrint('👂 Configurado listener Realtime para usuário ${user.id}');
  }

  /// Parar de escutar notificações
  static void stopListeningToNotifications() {
    _notificationChannel?.unsubscribe();
    _notificationChannel = null;
    debugPrint('🔇 Parou de escutar notificações');
  }

  /// Callback quando notificação é tocada (funciona em foreground e background)
  @pragma('vm:entry-point')
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notificação tocada: ${response.payload}');
    // Aqui você pode navegar para telas específicas baseado no payload
  }

  /// Verificar e processar notificações pendentes
  /// Deve ser chamado quando o app é aberto ou quando usuário faz login
  static Future<void> checkPendingNotifications() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        debugPrint(
          '⚠️ Usuário não logado, ignorando verificação de notificações pendentes',
        );
        return;
      }

      debugPrint(
        '🔍 Verificando notificações pendentes para usuário ${user.id}...',
      );

      // Buscar notificações não lidas criadas nos últimos 7 dias
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final pendingNotifications = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .eq('is_read', false)
          .gte('created_at', sevenDaysAgo.toIso8601String())
          .order('created_at', ascending: false);

      if (pendingNotifications.isEmpty) {
        debugPrint('✅ Nenhuma notificação pendente encontrada');
        return;
      }

      debugPrint(
        '📬 ${pendingNotifications.length} notificação(ões) pendente(s) encontrada(s)',
      );

      // IMPORTANTE: NÃO mostrar push aqui para evitar duplicação
      // O Realtime listener já está ativo e mostrará notificações novas
      // Este método apenas carrega as notificações perdidas no banco
      debugPrint(
        '✅ Notificações pendentes carregadas (serão exibidas no menu)',
      );
    } catch (e) {
      debugPrint('❌ Erro ao verificar notificações pendentes: $e');
    }
  }

  /// Mostrar notificação push local
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'carrodasdelicias_channel',
      'Carro das Delícias',
      channelDescription: 'Notificações de pedidos e atualizações',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Criar notificação para um usuário
  static Future<void> createNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'info',
    Map<String, dynamic>? data,
    bool showPushNotification = true,
  }) async {
    try {
      // Inserir notificação no banco
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'type': type,
        'data': data,
      });

      debugPrint('✅ Notificação criada para usuário $userId: $title');

      // NOTA: Não mostrar push aqui - o Realtime listener cuidará disso
      // Isso evita duplicação de notificações
    } catch (e) {
      debugPrint('❌ Erro ao criar notificação: $e');
    }
  }

  /// Criar notificação para múltiplos usuários
  static Future<void> createNotificationForUsers({
    required List<String> userIds,
    required String title,
    required String message,
    String type = 'info',
    Map<String, dynamic>? data,
  }) async {
    try {
      final notifications = userIds
          .map(
            (userId) => {
              'user_id': userId,
              'title': title,
              'message': message,
              'type': type,
              'data': data,
            },
          )
          .toList();

      await _supabase.from('notifications').insert(notifications);
    } catch (e) {
      debugPrint('Erro ao criar notificações: $e');
    }
  }

  /// Obter notificações do usuário atual
  static Future<List<Map<String, dynamic>>> getUserNotifications({
    int limit = 50,
    bool onlyUnread = false,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      List<Map<String, dynamic>> notifications;

      if (onlyUnread) {
        notifications = await _supabase
            .from('notifications')
            .select()
            .eq('user_id', user.id)
            .eq('is_read', false)
            .order('created_at', ascending: false)
            .limit(limit);
      } else {
        notifications = await _supabase
            .from('notifications')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      return List<Map<String, dynamic>>.from(notifications);
    } catch (e) {
      debugPrint('Erro ao obter notificações: $e');
      return [];
    }
  }

  /// Marcar notificação como lida
  static Future<void> markAsRead(int notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('Erro ao marcar notificação como lida: $e');
    }
  }

  /// Marcar todas as notificações como lidas
  static Future<void> markAllAsRead() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Erro ao marcar todas as notificações como lidas: $e');
    }
  }

  /// Excluir todas as notificações do usuário
  static Future<void> deleteAllNotifications() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('notifications').delete().eq('user_id', user.id);

      debugPrint('🗑️ Todas as notificações foram excluídas');
    } catch (e) {
      debugPrint('Erro ao excluir todas as notificações: $e');
    }
  }

  /// Deleta uma notificação específica
  static Future<void> deleteNotification(int notificationId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId)
          .eq('user_id', user.id);

      debugPrint('🗑️ Notificação $notificationId excluída');
    } catch (e) {
      debugPrint('Erro ao excluir notificação: $e');
    }
  }

  /// Notificar usuário sobre mudança no status do pedido
  static Future<int> getUnreadCount() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return 0;

      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      return response.length;
    } catch (e) {
      debugPrint('Erro ao obter contador de notificações: $e');
      return 0;
    }
  }

  /// Notificar mudança de status de pedido
  static Future<void> notifyOrderStatusChange({
    required String userId,
    required int orderId,
    required String oldStatus,
    required String newStatus,
  }) async {
    final statusLabels = {
      'pendente': 'Pendente',
      'confirmado': 'Confirmado',
      'em preparo': 'Em Preparo',
      'saiu para entrega': 'Saiu para Entrega',
      'entregue': 'Entregue',
      'cancelado': 'Cancelado',
    };

    final oldLabel = statusLabels[oldStatus] ?? oldStatus;
    final newLabel = statusLabels[newStatus] ?? newStatus;

    String title;
    String message;
    String type;

    switch (newStatus) {
      case 'confirmado':
        title = 'Pedido Confirmado!';
        message =
            'Seu pedido #${orderId.toString().padLeft(4, '0')} foi confirmado e está sendo preparado.';
        type = 'success';
        break;
      case 'em preparo':
        title = 'Pedido em Preparo';
        message =
            'Seu pedido #${orderId.toString().padLeft(4, '0')} está sendo preparado na cozinha.';
        type = 'info';
        break;
      case 'saiu para entrega':
        title = 'Pedido Saiu para Entrega!';
        message =
            'Seu pedido #${orderId.toString().padLeft(4, '0')} saiu para entrega e chegará em breve.';
        type = 'success';
        break;
      case 'entregue':
        title = 'Pedido Entregue!';
        message =
            'Seu pedido #${orderId.toString().padLeft(4, '0')} foi entregue com sucesso. Obrigado pela preferência!';
        type = 'success';
        break;
      case 'cancelado':
        title = 'Pedido Cancelado';
        message =
            'Seu pedido #${orderId.toString().padLeft(4, '0')} foi cancelado. Entre em contato conosco se precisar de ajuda.';
        type = 'warning';
        break;
      default:
        title = 'Status do Pedido Atualizado';
        message =
            'O status do seu pedido #${orderId.toString().padLeft(4, '0')} mudou de "$oldLabel" para "$newLabel".';
        type = 'info';
    }

    await createNotification(
      userId: userId,
      title: title,
      message: message,
      type: type,
      showPushNotification: true,
      data: {
        'order_id': orderId,
        'old_status': oldStatus,
        'new_status': newStatus,
      },
    );
  }

  /// Notificar admins sobre novo pedido
  static Future<void> notifyAdminsNewOrder({
    required int orderId,
    required String customerName,
    required double total,
  }) async {
    try {
      // Buscar todos os admins usando o campo 'role'
      final admins = await _supabase
          .from('profiles')
          .select('id, name, role')
          .eq('role', 'admin');

      if (admins.isEmpty) {
        debugPrint('⚠️ Nenhum admin encontrado para notificar');
        return;
      }

      debugPrint('📢 Encontrados ${admins.length} admin(s) para notificar');

      final title = '🔔 Novo Pedido!';
      final message =
          'Pedido #${orderId.toString().padLeft(4, '0')} de $customerName - R\$ ${total.toStringAsFixed(2)}';

      // Criar notificação para cada admin
      for (final admin in admins) {
        await createNotification(
          userId: admin['id'],
          title: title,
          message: message,
          type: 'order',
          showPushNotification: true,
          data: {
            'order_id': orderId,
            'customer_name': customerName,
            'total': total,
          },
        );
      }

      debugPrint(
        '✅ ${admins.length} admin(s) notificado(s) sobre pedido #$orderId',
      );
    } catch (e) {
      debugPrint('❌ Erro ao notificar admins: $e');
    }
  }
}

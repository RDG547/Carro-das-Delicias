import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Serviço para gerenciar permissões do aplicativo
class PermissionService {
  /// Obtém a versão do Android do dispositivo
  static Future<int> getAndroidVersion() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      return androidInfo.version.sdkInt;
    }
    return 0;
  }

  /// Solicita permissões necessárias para upload de imagens
  static Future<bool> requestImagePermissions() async {
    try {
      final androidVersion = await getAndroidVersion();
      List<Permission> permissions = [];

      // Câmera sempre é necessária
      permissions.add(Permission.camera);

      // Para Android 13+ (API 33+), usar photos ao invés de storage
      if (androidVersion >= 33) {
        permissions.add(Permission.photos);
      } else {
        // Para versões antigas, usar storage
        permissions.add(Permission.storage);
      }

      // Solicitar permissões
      final statuses = await permissions.request();

      // Verificar se todas as permissões foram concedidas
      bool allGranted = true;
      for (final status in statuses.values) {
        if (status != PermissionStatus.granted &&
            status != PermissionStatus.limited) {
          allGranted = false;
          debugPrint('Permissão negada: $status');
          break;
        }
      }

      return allGranted;
    } catch (e) {
      debugPrint('Erro ao solicitar permissões: $e');
      return false;
    }
  }

  /// Solicita permissão para notificações (Android 13+ requer isso)
  static Future<bool> requestNotificationPermissions() async {
    try {
      final androidVersion = await getAndroidVersion();

      // Para Android 13+ (API 33+), permissão de notificação é necessária
      if (androidVersion >= 33) {
        final status = await Permission.notification.request();

        if (status.isGranted) {
          debugPrint('✅ Permissão de notificação concedida');
          return true;
        } else if (status.isDenied) {
          debugPrint('⚠️ Permissão de notificação negada');
          return false;
        } else if (status.isPermanentlyDenied) {
          debugPrint('❌ Permissão de notificação permanentemente negada');
          return false;
        }
      }

      // Para versões antigas do Android, notificações são permitidas por padrão
      return true;
    } catch (e) {
      debugPrint('Erro ao solicitar permissão de notificação: $e');
      return false;
    }
  }

  /// Verifica se a permissão de notificações foi concedida
  static Future<bool> hasNotificationPermission() async {
    try {
      final androidVersion = await getAndroidVersion();

      // Para Android 13+ (API 33+), verificar permissão de notificação
      if (androidVersion >= 33) {
        final status = await Permission.notification.status;
        return status.isGranted;
      }

      // Para versões antigas do Android, notificações são permitidas por padrão
      return true;
    } catch (e) {
      debugPrint('Erro ao verificar permissão de notificação: $e');
      return false;
    }
  }

  /// Verifica se as permissões necessárias já foram concedidas
  static Future<bool> hasImagePermissions() async {
    try {
      final androidVersion = await getAndroidVersion();
      List<Permission> permissions = [];

      // Câmera sempre é necessária
      permissions.add(Permission.camera);

      // Para Android 13+ (API 33+), usar photos ao invés de storage
      if (androidVersion >= 33) {
        permissions.add(Permission.photos);
      } else {
        // Para versões antigas, usar storage
        permissions.add(Permission.storage);
      }

      for (final permission in permissions) {
        final status = await permission.status;
        // Aceitar granted ou limited (iOS pode retornar limited)
        if (status != PermissionStatus.granted &&
            status != PermissionStatus.limited) {
          debugPrint(
            'Permissão ${permission.toString()} não concedida: $status',
          );
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao verificar permissões: $e');
      return false;
    }
  }

  /// Mostra um diálogo explicativo sobre as permissões
  static Future<void> showPermissionDialog(BuildContext context) async {
    if (!context.mounted) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.security, color: Colors.blue[700]),
              const SizedBox(width: 12),
              const Text('Permissões Necessárias'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este aplicativo precisa das seguintes permissões:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.camera_alt, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Câmera - Para tirar fotos dos produtos'),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.photo_library, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('Galeria - Para selecionar imagens')),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.storage, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('Armazenamento - Para salvar imagens')),
                ],
              ),
              SizedBox(height: 16),
              Text(
                'Essas permissões são necessárias apenas para o upload de imagens dos produtos e fotos de perfil.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Configurações'),
            ),
          ],
        );
      },
    );
  }

  /// Solicita permissões com feedback visual
  static Future<bool> requestPermissionsWithDialog(BuildContext context) async {
    // Verificar se já tem as permissões
    if (await hasImagePermissions()) {
      return true;
    }

    // Solicitar permissões diretamente
    final granted = await requestImagePermissions();

    if (!granted) {
      // Mostrar mensagem se as permissões não foram concedidas
      if (context.mounted) {
        showPermissionDeniedMessage(context);
      }
    }

    return granted;
  }

  /// Mostra mensagem de erro quando permissões não são concedidas
  static void showPermissionDeniedMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Permissões necessárias não foram concedidas. '
          'Você pode ativá-las nas configurações do aplicativo.',
        ),
        backgroundColor: Colors.orange,
        action: SnackBarAction(
          label: 'Configurações',
          textColor: Colors.white,
          onPressed: () => openAppSettings(),
        ),
      ),
    );
  }
}

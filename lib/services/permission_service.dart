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

  /// Solicita permissão de câmera para tirar fotos.
  ///
  /// A seleção de imagens da galeria usa o seletor de fotos do sistema
  /// (Photo Picker) e NÃO requer nenhuma permissão de mídia
  /// (READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE), conforme exigido pela
  /// política do Google Play.
  static Future<bool> requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();

      if (status == PermissionStatus.granted ||
          status == PermissionStatus.limited) {
        return true;
      }

      debugPrint('Permissão de câmera negada: $status');
      return false;
    } catch (e) {
      debugPrint('Erro ao solicitar permissão de câmera: $e');
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

  /// Verifica se a permissão de câmera já foi concedida
  static Future<bool> hasCameraPermission() async {
    try {
      final status = await Permission.camera.status;
      return status == PermissionStatus.granted ||
          status == PermissionStatus.limited;
    } catch (e) {
      debugPrint('Erro ao verificar permissão de câmera: $e');
      return false;
    }
  }

  /// Mostra um diálogo explicativo sobre a permissão de câmera
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
              const Text('Permissão Necessária'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Este aplicativo precisa da seguinte permissão:',
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
              SizedBox(height: 16),
              Text(
                'A seleção de imagens da galeria usa o seletor de fotos do '
                'sistema e não requer nenhuma permissão.',
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

  /// Solicita permissão de câmera com feedback visual
  static Future<bool> requestCameraPermissionWithDialog(
    BuildContext context,
  ) async {
    // Verificar se já tem a permissão
    if (await hasCameraPermission()) {
      return true;
    }

    // Solicitar permissão diretamente
    final granted = await requestCameraPermission();

    if (!granted) {
      // Mostrar mensagem se a permissão não foi concedida
      if (context.mounted) {
        showPermissionDeniedMessage(context);
      }
    }

    return granted;
  }

  /// Mostra mensagem de erro quando a permissão de câmera não é concedida
  static void showPermissionDeniedMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Permissão de câmera não foi concedida. '
          'Você pode ativá-la nas configurações do aplicativo.',
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

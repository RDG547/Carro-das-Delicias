import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;
import 'permission_service.dart';

class ImageService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ImagePicker _picker = ImagePicker();

  /// Fazer upload de imagem para Supabase Storage
  static Future<String?> uploadImage({
    required File imageFile,
    required String bucketName,
    required String fileName,
    Function(double)? onProgress,
  }) async {
    try {
      // Verificar autenticação
      final user = _supabase.auth.currentUser;
      debugPrint('📤 Iniciando upload...');
      debugPrint('📤 Usuário autenticado: ${user?.email ?? "NÃO AUTENTICADO"}');
      debugPrint('📤 Bucket: $bucketName');
      debugPrint('📤 Nome do arquivo: $fileName');
      debugPrint('📤 Caminho do arquivo: ${imageFile.path}');

      if (user == null) {
        debugPrint('❌ ERRO: Usuário não está autenticado!');
        return null;
      }

      final fileBytes = await imageFile.readAsBytes();
      debugPrint('📤 Tamanho do arquivo: ${fileBytes.length} bytes');

      final response = await _supabase.storage
          .from(bucketName)
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );

      debugPrint('📤 Resposta do upload: $response');

      if (response.isNotEmpty) {
        final imageUrl = _supabase.storage
            .from(bucketName)
            .getPublicUrl(fileName);

        debugPrint('✅ Upload bem-sucedido! URL: $imageUrl');
        return imageUrl;
      }

      debugPrint('❌ Upload retornou vazio');
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao fazer upload da imagem: $e');
      debugPrint('❌ Tipo do erro: ${e.runtimeType}');
      return null;
    }
  }

  /// Deletar imagem do Supabase Storage
  static Future<bool> deleteImage({
    required String bucketName,
    required String fileName,
  }) async {
    try {
      await _supabase.storage.from(bucketName).remove([fileName]);
      return true;
    } catch (e) {
      debugPrint('Erro ao deletar imagem: $e');
      return false;
    }
  }

  /// Extrair nome do arquivo da URL
  static String? extractFileNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return path.basename(uri.path);
    } catch (e) {
      debugPrint('Erro ao extrair nome do arquivo: $e');
      return null;
    }
  }

  /// Selecionar imagem da galeria
  static Future<File?> pickImageFromGallery() async {
    try {
      debugPrint('📸 Abrindo galeria...');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        debugPrint('📸 Imagem selecionada da galeria: ${image.path}');
        return File(image.path);
      }

      debugPrint('📸 Nenhuma imagem foi selecionada da galeria');
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao selecionar imagem: $e');
      return null;
    }
  }

  /// Tirar foto com a câmera
  static Future<File?> pickImageFromCamera() async {
    try {
      debugPrint('📷 Abrindo câmera...');
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        debugPrint('📷 Foto tirada: ${image.path}');
        return File(image.path);
      }

      debugPrint('📷 Nenhuma foto foi tirada');
      return null;
    } catch (e) {
      debugPrint('❌ Erro ao tirar foto: $e');
      return null;
    }
  }

  /// Mostrar diálogo para seleção de imagem
  static Future<File?> showImagePickerDialog(BuildContext context) async {
    // Verificar permissões antes de mostrar o diálogo
    final hasPermissions = await PermissionService.requestPermissionsWithDialog(
      context,
    );

    if (!hasPermissions) {
      if (context.mounted) {
        PermissionService.showPermissionDeniedMessage(context);
      }
      return null;
    }

    // Usar um novo context para o diálogo
    if (!context.mounted) return null;

    return showDialog<File?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Selecionar Imagem', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeria'),
              onTap: () async {
                // Pega a imagem primeiro
                final image = await pickImageFromGallery();
                // Depois fecha o diálogo retornando a imagem
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(image);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Câmera'),
              onTap: () async {
                // Pega a imagem primeiro
                final image = await pickImageFromCamera();
                // Depois fecha o diálogo retornando a imagem
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(image);
                }
              },
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  /// Upload de imagem de produto com deleção da anterior
  static Future<String?> uploadProductImage({
    required File imageFile,
    required int productId,
    String? oldImageUrl,
    Function(double)? onProgress,
  }) async {
    // Deletar imagem anterior se existir
    if (oldImageUrl != null && oldImageUrl.isNotEmpty) {
      await deleteProductImage(oldImageUrl);
    }

    final fileName =
        'product_${productId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await uploadImage(
      imageFile: imageFile,
      bucketName: 'produtos',
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  /// Upload de imagem de perfil com deleção da anterior
  static Future<String?> uploadProfileImage({
    required File imageFile,
    required String userId,
    String? oldImageUrl,
    Function(double)? onProgress,
  }) async {
    // Deletar imagem anterior se existir
    if (oldImageUrl != null && oldImageUrl.isNotEmpty) {
      await deleteProfileImage(oldImageUrl);
    }

    final fileName =
        'profile_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await uploadImage(
      imageFile: imageFile,
      bucketName: 'profiles',
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  /// Deletar imagem de produto
  static Future<bool> deleteProductImage(String imageUrl) async {
    final fileName = extractFileNameFromUrl(imageUrl);
    if (fileName != null) {
      return await deleteImage(bucketName: 'produtos', fileName: fileName);
    }
    return false;
  }

  /// Deletar imagem de perfil
  static Future<bool> deleteProfileImage(String imageUrl) async {
    final fileName = extractFileNameFromUrl(imageUrl);
    if (fileName != null) {
      return await deleteImage(bucketName: 'profiles', fileName: fileName);
    }
    return false;
  }
}

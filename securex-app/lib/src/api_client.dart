import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'models.dart';

class ApiClient {
  ApiClient();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  Future<Map<String, dynamic>> register({
    required String baseUrl,
    required String username,
    required String email,
    required String password,
    required String kdfAlgorithm,
    required String masterKeySalt,
    required int masterKeyIterations,
    required String wrappedVaultKey,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/register',
        data: {
          'username': username,
          'email': email,
          'password': password,
          'kdfAlgorithm': kdfAlgorithm,
          'masterKeySalt': masterKeySalt,
          'masterKeyIterations': masterKeyIterations,
          'wrappedVaultKey': wrappedVaultKey,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> login({
    required String baseUrl,
    required String identifier,
    required String password,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/login',
        data: {'identifier': identifier, 'password': password},
      ),
    );
  }

  Future<UserProfile> me({
    required String baseUrl,
    required String token,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/me',
        options: _authorized(token),
      ),
    );

    return UserProfile.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> changePassword({
    required String baseUrl,
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/auth/password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      options: _authorized(token),
    );
  }

  Future<UserProfile> changeUnlockPassword({
    required String baseUrl,
    required String token,
    required String kdfAlgorithm,
    required String masterKeySalt,
    required int masterKeyIterations,
    required String wrappedVaultKey,
  }) async {
    final data = _unwrapMap(
      await _dio.put<Map<String, dynamic>>(
        '$baseUrl/api/v1/auth/unlock-password',
        data: {
          'kdfAlgorithm': kdfAlgorithm,
          'masterKeySalt': masterKeySalt,
          'masterKeyIterations': masterKeyIterations,
          'wrappedVaultKey': wrappedVaultKey,
        },
        options: _authorized(token),
      ),
    );

    return UserProfile.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> exportVault({
    required String baseUrl,
    required String token,
  }) async {
    return _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/sync/export',
        options: _authorized(token),
      ),
    );
  }

  Future<void> createFolder({
    required String baseUrl,
    required String token,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/folders',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> updateFolder({
    required String baseUrl,
    required String token,
    required String folderId,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/folders/$folderId',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> deleteFolder({
    required String baseUrl,
    required String token,
    required String folderId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/folders/$folderId',
      options: _authorized(token),
    );
  }

  Future<void> createFileFolder({
    required String baseUrl,
    required String token,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-folders',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> updateFileFolder({
    required String baseUrl,
    required String token,
    required String folderId,
    required String payload,
    required int version,
    String? parentFolderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-folders/$folderId',
      data: {
        'parentFolderId': parentFolderId,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> deleteFileFolder({
    required String baseUrl,
    required String token,
    required String folderId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-folders/$folderId',
      options: _authorized(token),
    );
  }

  Future<void> createItem({
    required String baseUrl,
    required String token,
    required String kind,
    required String payload,
    required int version,
    String? folderId,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/items',
      data: {
        'folderId': folderId,
        'kind': kind,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> updateItem({
    required String baseUrl,
    required String token,
    required String itemId,
    required String kind,
    required String payload,
    required int version,
    String? folderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/items/$itemId',
      data: {
        'folderId': folderId,
        'kind': kind,
        'payload': payload,
        'version': version,
      },
      options: _authorized(token),
    );
  }

  Future<void> deleteItem({
    required String baseUrl,
    required String token,
    required String itemId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/items/$itemId',
      options: _authorized(token),
    );
  }

  Future<void> uploadEncryptedFile({
    required String baseUrl,
    required String token,
    required String payload,
    required Uint8List cipherBytes,
    required int version,
    String? folderId,
  }) async {
    final formData = FormData.fromMap({
      'metadata': jsonEncode({
        'folderId': folderId,
        'payload': payload,
        'version': version,
      }),
      'cipher_file': MultipartFile.fromBytes(
        cipherBytes,
        filename: 'cipher.bin',
      ),
    });

    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/files',
      data: formData,
      options: _authorized(token),
    );
  }

  Future<Map<String, dynamic>> startChunkedFileUpload({
    required String baseUrl,
    required String token,
    required int totalChunks,
    required int version,
    String? folderId,
  }) async {
    return _unwrapMap(
      await _dio.post<Map<String, dynamic>>(
        '$baseUrl/api/v1/file-uploads',
        data: {
          'folderId': folderId,
          'version': version,
          'totalChunks': totalChunks,
        },
        options: _authorized(token),
      ),
    );
  }

  Future<void> uploadFileChunk({
    required String baseUrl,
    required String token,
    required String uploadId,
    required int index,
    required Uint8List cipherBytes,
    ProgressCallback? onSendProgress,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-uploads/$uploadId/chunks/$index',
      data: Stream.fromIterable([cipherBytes]),
      options: _authorized(token).copyWith(
        contentType: 'application/octet-stream',
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Length': cipherBytes.length,
        },
      ),
      onSendProgress: onSendProgress,
    );
  }

  Future<void> completeChunkedFileUpload({
    required String baseUrl,
    required String token,
    required String uploadId,
    required String payload,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/v1/file-uploads/$uploadId/complete',
      data: {'payload': payload},
      options: _authorized(token),
    );
  }

  Future<void> updateFileMetadata({
    required String baseUrl,
    required String token,
    required String fileId,
    required String payload,
    required int version,
    String? folderId,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '$baseUrl/api/v1/files/$fileId',
      data: {'folderId': folderId, 'payload': payload, 'version': version},
      options: _authorized(token),
    );
  }

  Future<void> deleteFile({
    required String baseUrl,
    required String token,
    required String fileId,
  }) async {
    await _dio.delete<Map<String, dynamic>>(
      '$baseUrl/api/v1/files/$fileId',
      options: _authorized(token),
    );
  }

  Future<Uint8List> downloadEncryptedFile({
    required String baseUrl,
    required String token,
    required String fileId,
  }) async {
    final data = _unwrapMap(
      await _dio.get<Map<String, dynamic>>(
        '$baseUrl/api/v1/files/$fileId/download',
        options: _authorized(token),
      ),
    );

    return Uint8List.fromList(base64Decode(data['cipherTextBase64'] as String));
  }

  Map<String, dynamic> _unwrapMap(Response<Map<String, dynamic>> response) {
    final envelope = response.data ?? <String, dynamic>{};
    final data = envelope['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }

  Options _authorized(String token, {ResponseType? responseType}) {
    return Options(
      responseType: responseType,
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}

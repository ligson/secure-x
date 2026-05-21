class UserProfile {
  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.kdfAlgorithm,
    required this.masterKeySalt,
    required this.masterKeyIterations,
    required this.wrappedVaultKey,
  });

  final String id;
  final String username;
  final String email;
  final String kdfAlgorithm;
  final String masterKeySalt;
  final int masterKeyIterations;
  final String wrappedVaultKey;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      kdfAlgorithm: json['kdfAlgorithm'] as String,
      masterKeySalt: json['masterKeySalt'] as String,
      masterKeyIterations: (json['masterKeyIterations'] as num).toInt(),
      wrappedVaultKey: json['wrappedVaultKey'] as String,
    );
  }
}

class FolderRecord {
  FolderRecord({
    required this.id,
    required this.payload,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String payload;
  final int version;
  final String? parentFolderId;

  factory FolderRecord.fromJson(Map<String, dynamic> json) {
    return FolderRecord(
      id: json['id'] as String,
      payload: json['payload'] as String,
      version: (json['version'] as num).toInt(),
      parentFolderId: json['parentFolderId'] as String?,
    );
  }
}

class FileFolderRecord {
  FileFolderRecord({
    required this.id,
    required this.payload,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String payload;
  final int version;
  final String? parentFolderId;

  factory FileFolderRecord.fromJson(Map<String, dynamic> json) {
    return FileFolderRecord(
      id: json['id'] as String,
      payload: json['payload'] as String,
      version: (json['version'] as num).toInt(),
      parentFolderId: json['parentFolderId'] as String?,
    );
  }
}

class VaultItemRecord {
  VaultItemRecord({
    required this.id,
    required this.kind,
    required this.payload,
    required this.version,
    this.folderId,
  });

  final String id;
  final String kind;
  final String payload;
  final int version;
  final String? folderId;

  factory VaultItemRecord.fromJson(Map<String, dynamic> json) {
    return VaultItemRecord(
      id: json['id'] as String,
      kind: json['kind'] as String,
      payload: json['payload'] as String,
      version: (json['version'] as num).toInt(),
      folderId: json['folderId'] as String?,
    );
  }
}

class StoredFileRecord {
  StoredFileRecord({
    required this.id,
    required this.payload,
    required this.cipherSize,
    required this.version,
    this.folderId,
  });

  final String id;
  final String payload;
  final int cipherSize;
  final int version;
  final String? folderId;

  factory StoredFileRecord.fromJson(Map<String, dynamic> json) {
    return StoredFileRecord(
      id: json['id'] as String,
      payload: json['payload'] as String,
      cipherSize: (json['cipherSize'] as num).toInt(),
      version: (json['version'] as num).toInt(),
      folderId: json['folderId'] as String?,
    );
  }
}

class DecryptedFolder {
  DecryptedFolder({
    required this.id,
    required this.name,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String name;
  final int version;
  final String? parentFolderId;
}

class DecryptedFileFolder {
  DecryptedFileFolder({
    required this.id,
    required this.name,
    required this.version,
    this.parentFolderId,
  });

  final String id;
  final String name;
  final int version;
  final String? parentFolderId;
}

class DecryptedLoginItem {
  DecryptedLoginItem({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.note,
    required this.version,
    this.folderId,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String note;
  final int version;
  final String? folderId;
}

class DecryptedFileRecord {
  DecryptedFileRecord({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.originalSize,
    required this.fileKey,
    required this.cipherSize,
    required this.version,
    this.chunkCipherSizes = const [],
    this.folderId,
  });

  final String id;
  final String name;
  final String mimeType;
  final int originalSize;
  final String fileKey;
  final int cipherSize;
  final int version;
  final List<int> chunkCipherSizes;
  final String? folderId;

  bool get chunked => chunkCipherSizes.isNotEmpty;
}

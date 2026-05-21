// ignore_for_file: invalid_use_of_protected_member

part of '../../../main.dart';

class _FolderDraft {
  _FolderDraft({required this.name, required this.parentFolderId});

  final String name;
  final String parentFolderId;
}

class _LoginItemDraft {
  _LoginItemDraft({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.note,
    required this.folderId,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String note;
  final String folderId;
}

class _FileDraft {
  _FileDraft({required this.name, required this.folderId});

  final String name;
  final String folderId;
}

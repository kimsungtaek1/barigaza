import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

// Storage 서비스 클래스
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "gs://barigaza-796a1.firebasestorage.app");

  // 싱글톤 패턴 구현
  static final StorageService _instance = StorageService._internal();

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();

  // 파일 업로드 메소드
  Future<StorageResult<String>> uploadFile({
    required String path,
    required Uint8List data,
    String? contentType,
    Map<String, String>? customMetadata,
    Function(double)? onProgress,
  }) async {
    try {
      final ref = _storage.ref().child(path);

      final metadata = SettableMetadata(
        contentType: contentType ?? 'application/octet-stream',
        customMetadata: {
          'uploaded': 'true',
          'timestamp': DateTime.now().toString(),
          ...?customMetadata,
        },
      );

      final uploadTask = ref.putData(data, metadata);

      // 업로드 진행률 모니터링
      uploadTask.snapshotEvents.listen(
            (TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress?.call(progress);
          if (kDebugMode) {
            print('Upload progress: ${(progress * 100).toStringAsFixed(2)}%');
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('Upload error: $error');
          }
        },
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return StorageResult.success(downloadUrl);
    } catch (e) {
      return StorageResult.failure('파일 업로드 실패: $e');
    }
  }

  // 파일 삭제 메소드
  Future<StorageResult<bool>> deleteFile(String path) async {
    try {
      final ref = _storage.ref().child(path);
      await ref.delete();
      return StorageResult.success(true);
    } catch (e) {
      return StorageResult.failure('파일 삭제 실패: $e');
    }
  }

  // 여러 파일 삭제 메소드
  Future<StorageResult<List<String>>> deleteFiles(List<String> paths) async {
    List<String> deletedPaths = [];
    List<String> failedPaths = [];

    for (String path in paths) {
      try {
        await _storage.ref().child(path).delete();
        deletedPaths.add(path);
      } catch (e) {
        failedPaths.add(path);
        if (kDebugMode) {
          print('Failed to delete $path: $e');
        }
      }
    }

    if (failedPaths.isEmpty) {
      return StorageResult.success(deletedPaths);
    } else {
      return StorageResult.failure(
        '일부 파일 삭제 실패. 성공: ${deletedPaths.length}, 실패: ${failedPaths.length}',
        data: deletedPaths,
      );
    }
  }

  // 다운로드 URL 획득 메소드
  Future<StorageResult<String>> getDownloadURL(String path) async {
    try {
      final ref = _storage.ref().child(path);
      final url = await ref.getDownloadURL();
      return StorageResult.success(url);
    } catch (e) {
      return StorageResult.failure('다운로드 URL 획득 실패: $e');
    }
  }

  // 모든 파일 리스트 조회 (재귀적)
  Future<StorageResult<List<FileItem>>> listAllFiles([String path = '']) async {
    try {
      List<FileItem> fileList = [];
      final ListResult result = await _storage.ref(path).listAll();

      // 하위 폴더 처리
      for (var prefix in result.prefixes) {
        final subResult = await listAllFiles(prefix.fullPath);
        if (subResult.isSuccess) {
          fileList.addAll(subResult.data ?? []);
        }
      }

      // 현재 경로 파일 처리
      for (var item in result.items) {
        try {
          final metadata = await item.getMetadata();
          final downloadUrl = await item.getDownloadURL();

          fileList.add(FileItem(
            name: item.name,
            path: item.fullPath,
            size: metadata.size ?? 0,
            contentType: metadata.contentType ?? 'unknown',
            downloadUrl: downloadUrl,
            createdTime: metadata.timeCreated ?? DateTime.now(),
            updatedTime: metadata.updated ?? DateTime.now(),
            customMetadata: metadata.customMetadata ?? {},
          ));
        } catch (e) {
          if (kDebugMode) {
            print('Failed to process file ${item.fullPath}: $e');
          }
        }
      }

      return StorageResult.success(fileList);
    } catch (e) {
      return StorageResult.failure('파일 리스트 조회 실패: $e');
    }
  }

  // 특정 경로의 파일만 조회
  Future<StorageResult<List<FileItem>>> listFiles(String path) async {
    try {
      List<FileItem> fileList = [];
      final ListResult result = await _storage.ref(path).list();

      for (var item in result.items) {
        try {
          final metadata = await item.getMetadata();
          final downloadUrl = await item.getDownloadURL();

          fileList.add(FileItem(
            name: item.name,
            path: item.fullPath,
            size: metadata.size ?? 0,
            contentType: metadata.contentType ?? 'unknown',
            downloadUrl: downloadUrl,
            createdTime: metadata.timeCreated ?? DateTime.now(),
            updatedTime: metadata.updated ?? DateTime.now(),
            customMetadata: metadata.customMetadata ?? {},
          ));
        } catch (e) {
          if (kDebugMode) {
            print('Failed to process file ${item.fullPath}: $e');
          }
        }
      }

      return StorageResult.success(fileList);
    } catch (e) {
      return StorageResult.failure('파일 리스트 조회 실패: $e');
    }
  }

  // 파일 메타데이터 업데이트
  Future<StorageResult<bool>> updateMetadata({
    required String path,
    String? contentType,
    Map<String, String>? customMetadata,
  }) async {
    try {
      final ref = _storage.ref().child(path);
      final metadata = SettableMetadata(
        contentType: contentType,
        customMetadata: customMetadata,
      );
      await ref.updateMetadata(metadata);
      return StorageResult.success(true);
    } catch (e) {
      return StorageResult.failure('메타데이터 업데이트 실패: $e');
    }
  }

  // 파일 복사
  Future<StorageResult<String>> copyFile({
    required String sourcePath,
    required String destinationPath,
  }) async {
    try {
      final sourceRef = _storage.ref().child(sourcePath);
      final destinationRef = _storage.ref().child(destinationPath);

      final data = await sourceRef.getData();
      if (data == null) {
        return StorageResult.failure('소스 파일 데이터 획득 실패');
      }

      final sourceMetadata = await sourceRef.getMetadata();

      // FullMetadata를 SettableMetadata로 변환
      final metadata = SettableMetadata(
        contentType: sourceMetadata.contentType,
        customMetadata: sourceMetadata.customMetadata,
        contentEncoding: sourceMetadata.contentEncoding,
        contentLanguage: sourceMetadata.contentLanguage,
        contentDisposition: sourceMetadata.contentDisposition,
        cacheControl: sourceMetadata.cacheControl,
      );

      final uploadTask = destinationRef.putData(data, metadata);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return StorageResult.success(downloadUrl);
    } catch (e) {
      return StorageResult.failure('파일 복사 실패: $e');
    }
  }
}

// 파일 정보 모델
class FileItem {
  final String name;
  final String path;
  final int size;
  final String contentType;
  final String downloadUrl;
  final DateTime createdTime;
  final DateTime updatedTime;
  final Map<String, String> customMetadata;

  FileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.contentType,
    required this.downloadUrl,
    required this.createdTime,
    required this.updatedTime,
    required this.customMetadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'size': size,
      'contentType': contentType,
      'downloadUrl': downloadUrl,
      'createdTime': createdTime.toIso8601String(),
      'updatedTime': updatedTime.toIso8601String(),
      'customMetadata': customMetadata,
    };
  }

  factory FileItem.fromMap(Map<String, dynamic> map) {
    return FileItem(
      name: map['name'] as String,
      path: map['path'] as String,
      size: map['size'] as int,
      contentType: map['contentType'] as String,
      downloadUrl: map['downloadUrl'] as String,
      createdTime: DateTime.parse(map['createdTime'] as String),
      updatedTime: DateTime.parse(map['updatedTime'] as String),
      customMetadata: Map<String, String>.from(map['customMetadata'] as Map),
    );
  }
}

// 결과 래퍼 클래스
class StorageResult<T> {
  final bool isSuccess;
  final String? error;
  final T? data;

  StorageResult({
    required this.isSuccess,
    this.error,
    this.data,
  });

  factory StorageResult.success(T data) {
    return StorageResult(
      isSuccess: true,
      data: data,
    );
  }

  factory StorageResult.failure(String error, {T? data}) {
    return StorageResult(
      isSuccess: false,
      error: error,
      data: data,
    );
  }
}
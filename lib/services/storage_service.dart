import 'dart:typed_data';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

// Storage 서비스 클래스
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "gs://barigaza-796a1.firebasestorage.app");

  // 싱글톤 패턴 구현
  static final StorageService _instance = StorageService._internal();

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();
  
  // 이미지 압축 메소드 (프로필 이미지용 - 최대 200KB)
  Future<Uint8List> compressProfileImage(Uint8List data, String fileName) async {
    // 임시 파일 경로 설정
    final dir = await path_provider.getTemporaryDirectory();
    final targetPath = '${dir.path}/$fileName';
    final sourceFile = File('${dir.path}/temp_$fileName');
    await sourceFile.writeAsBytes(data);

    try {
      // 이미지 압축 (목표 200KB = 204800 bytes)
      final result = await FlutterImageCompress.compressWithFile(
        sourceFile.path,
        minHeight: 300,
        minWidth: 300,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      
      if (result == null) {
        throw Exception('이미지 압축 실패');
      }
      
      // 압축된 파일이 200KB를 초과하면, 결과 데이터를 파일로 다시 저장하고 더 낮은 품질로 재압축
      if (result.length > 204800) {
        final tempFile = File('${dir.path}/temp2_$fileName');
        await tempFile.writeAsBytes(result);
        final secondResult = await FlutterImageCompress.compressWithFile(
          tempFile.path,
          minHeight: 300,
          minWidth: 300,
          quality: 70,
          format: CompressFormat.jpeg,
        );
        
        await tempFile.delete();
        if (secondResult == null) {
          throw Exception('이미지 재압축 실패');
        }
        return secondResult;
      }

      return result;
    } finally {
      // 임시 파일 정리
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }
  }

  // 일반 이미지 압축 메소드 (최대 1MB)
  Future<Uint8List> compressImage(Uint8List data, String fileName) async {
    // 임시 파일 경로 설정
    final dir = await path_provider.getTemporaryDirectory();
    final sourceFile = File('${dir.path}/temp_$fileName');
    await sourceFile.writeAsBytes(data);

    try {
      // 이미지 압축 (목표 1MB = 1048576 bytes)
      final result = await FlutterImageCompress.compressWithFile(
        sourceFile.path,
        minHeight: 1024,
        minWidth: 1024,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      
      if (result == null) {
        throw Exception('이미지 압축 실패');
      }
      
      // 압축된 파일이 1MB를 초과하면 품질을 더 낮춰 다시 압축
      if (result.length > 1048576) {
        final tempFile = File('${dir.path}/temp2_$fileName');
        await tempFile.writeAsBytes(result);
        final secondResult = await FlutterImageCompress.compressWithFile(
          tempFile.path,
          minHeight: 1024, 
          minWidth: 1024,
          quality: 75,
          format: CompressFormat.jpeg,
        );
        
        await tempFile.delete();
        if (secondResult == null) {
          throw Exception('이미지 재압축 실패');
        }
        return secondResult;
      }

      return result;
    } finally {
      // 임시 파일 정리
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }
  }
  
  // WebP 변환 메소드
  Future<Uint8List> convertToWebP(Uint8List data, String fileName, bool isProfile) async {
    final dir = await path_provider.getTemporaryDirectory();
    final sourceFile = File('${dir.path}/temp_$fileName');
    final targetPath = '${dir.path}/${fileName.split('.').first}.webp';
    await sourceFile.writeAsBytes(data);
    
    try {
      final quality = isProfile ? 85 : 90;
      final maxWidth = isProfile ? 300 : 1024;
      final maxHeight = isProfile ? 300 : 1024;
      
      final result = await FlutterImageCompress.compressWithFile(
        sourceFile.path,
        format: CompressFormat.webp,
        quality: quality,
        minWidth: maxWidth,
        minHeight: maxHeight,
      );
      
      if (result == null) {
        throw Exception('WebP 변환 실패');
      }
      
      // 파일 크기 제한 확인 (프로필: 200KB, 일반: 1MB)
      final maxSize = isProfile ? 204800 : 1048576;
      if (result.length > maxSize) {
        // 더 낮은 품질로 다시 압축
        final lowerQuality = isProfile ? 70 : 80;
        final tempFile = File('${dir.path}/temp2_$fileName');
        await tempFile.writeAsBytes(result);
        
        final secondResult = await FlutterImageCompress.compressWithFile(
          tempFile.path,
          format: CompressFormat.webp,
          quality: lowerQuality,
          minWidth: maxWidth,
          minHeight: maxHeight,
        );
        
        await tempFile.delete();
        if (secondResult == null) {
          throw Exception('WebP 재변환 실패');
        }
        return secondResult;
      }
      
      return result;
    } finally {
      // 임시 파일 정리
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }
  }

  // 파일 업로드 메소드
  Future<StorageResult<String>> uploadFile({
    required String path,
    required Uint8List data,
    String? contentType,
    Map<String, String>? customMetadata,
    Function(double)? onProgress,
    bool isProfileImage = false,
    bool optimizeImage = true,
    bool convertToWebpFormat = false,
  }) async {
    try {
      var ref = _storage.ref().child(path);
      Uint8List fileData = data;
      String finalContentType = contentType ?? 'application/octet-stream';
      
      // 이미지 최적화 처리
      if (optimizeImage && finalContentType.startsWith('image/')) {
        final fileName = path.split('/').last;
        
        // WebP 변환이 요청되었으면 변환
        if (convertToWebpFormat) {
          fileData = await convertToWebP(data, fileName, isProfileImage);
          finalContentType = 'image/webp';
          
          // 경로에 확장자가 있으면 webp로 변경
          if (path.contains('.')) {
            final basePath = path.substring(0, path.lastIndexOf('.'));
            final newPath = '$basePath.webp';
            path = newPath;
            ref = _storage.ref().child(newPath);
          }
        } 
        // 그렇지 않으면 일반 압축만 진행
        else {
          if (isProfileImage) {
            fileData = await compressProfileImage(data, fileName);
          } else {
            fileData = await compressImage(data, fileName);
          }
        }
      }
      
      final metadata = SettableMetadata(
        contentType: finalContentType,
        customMetadata: {
          'uploaded': 'true',
          'timestamp': DateTime.now().toString(),
          'optimized': optimizeImage.toString(),
          ...?customMetadata,
        },
      );

      final uploadTask = ref.putData(fileData, metadata);

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
      
      if (kDebugMode) {
        final fileSize = fileData.length / 1024; // KB 단위
        print('Uploaded file size: ${fileSize.toStringAsFixed(2)} KB');
      }

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
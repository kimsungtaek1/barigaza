import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/car_model.dart';

class CarModelService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 제조사 관련 메서드
  Future<List<CarManufacturer>> getManufacturers() async {
    try {
      final snapshot = await _firestore
          .collection('car_manufacturers')
          .orderBy('name')
          .get();
      
      return snapshot.docs
          .map((doc) => CarManufacturer.fromMap({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting manufacturers: $e');
      return [];
    }
  }
  
  Stream<List<CarManufacturer>> streamManufacturers() {
    return _firestore
        .collection('car_manufacturers')
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CarManufacturer.fromMap({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList());
  }
  
  Future<bool> addManufacturer(String name) async {
    try {
      final String id = name.toLowerCase().replaceAll(' ', '_');
      
      // 이미 존재하는지 확인
      final existingDoc = await _firestore
          .collection('car_manufacturers')
          .where('id', isEqualTo: id)
          .get();
      
      if (existingDoc.docs.isNotEmpty) {
        return false; // 이미 존재함
      }
      
      await _firestore.collection('car_manufacturers').doc(id).set({
        'id': id,
        'name': name,
      });
      
      return true;
    } catch (e) {
      print('Error adding manufacturer: $e');
      return false;
    }
  }
  
  Future<bool> updateManufacturer(String id, String name) async {
    try {
      await _firestore.collection('car_manufacturers').doc(id).update({
        'name': name,
      });
      
      return true;
    } catch (e) {
      print('Error updating manufacturer: $e');
      return false;
    }
  }
  
  Future<bool> deleteManufacturer(String id) async {
    try {
      // 먼저 관련된 모든 모델 문서 ID 찾기
      final modelsSnapshot = await _firestore
          .collection('car_models')
          .where('manufacturerId', isEqualTo: id)
          .get();
          
      // 트랜잭션으로 제조사와 관련된 모든 모델을 함께 삭제
      await _firestore.runTransaction((transaction) async {
        // 모든 모델 삭제
        for (final doc in modelsSnapshot.docs) {
          transaction.delete(doc.reference);
        }
        
        // 제조사 삭제
        transaction.delete(_firestore.collection('car_manufacturers').doc(id));
      });
      
      return true;
    } catch (e) {
      print('Error deleting manufacturer: $e');
      return false;
    }
  }
  
  // 차량 모델 관련 메서드
  Future<List<CarModel>> getModels(String manufacturerId) async {
    try {
      final snapshot = await _firestore
          .collection('car_models')
          .where('manufacturerId', isEqualTo: manufacturerId)
          .orderBy('model')
          .get();
      
      return snapshot.docs
          .map((doc) => CarModel.fromMap({
                'id': doc.id,
                ...doc.data(),
              }))
          .toList();
    } catch (e) {
      print('Error getting models: $e');
      return [];
    }
  }
  
  Stream<List<CarModel>> streamModels(String manufacturerId) {
    return _firestore
        .collection('car_models')
        .where('manufacturerId', isEqualTo: manufacturerId)
        .orderBy('model')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CarModel.fromMap({
                  'id': doc.id,
                  ...doc.data(),
                }))
            .toList());
  }
  
  Future<bool> addModel(String manufacturerId, String model) async {
    try {
      final String id = model.toLowerCase().replaceAll(' ', '_');
      
      // 이미 존재하는지 확인
      final existingDoc = await _firestore
          .collection('car_models')
          .where('manufacturerId', isEqualTo: manufacturerId)
          .where('id', isEqualTo: id)
          .get();
      
      if (existingDoc.docs.isNotEmpty) {
        return false; // 이미 존재함
      }
      
      final modelData = {
        'id': id,
        'model': model,
        'manufacturerId': manufacturerId,
      };
      
      await _firestore.collection('car_models').doc('${manufacturerId}_$id').set(modelData);
      
      return true;
    } catch (e) {
      print('Error adding model: $e');
      return false;
    }
  }
  
  Future<bool> updateModel(String docId, String model) async {
    try {
      await _firestore.collection('car_models').doc(docId).update({
        'model': model,
      });
      
      return true;
    } catch (e) {
      print('Error updating model: $e');
      return false;
    }
  }
  
  Future<bool> deleteModel(String docId) async {
    try {
      await _firestore.collection('car_models').doc(docId).delete();
      
      return true;
    } catch (e) {
      print('Error deleting model: $e');
      return false;
    }
  }
  
  // JSON 데이터 마이그레이션 메서드
  Future<bool> migrateFromJson(Map<String, List<Map<String, dynamic>>> data) async {
    try {
      // 트랜잭션으로 모든 마이그레이션 처리
      await _firestore.runTransaction((transaction) async {
        // 제조사 마이그레이션
        for (final manufacturer in data.keys) {
          final manufacturerId = manufacturer.toLowerCase().replaceAll(' ', '_');
          
          // 제조사 추가
          final manufacturerRef = _firestore.collection('car_manufacturers').doc(manufacturerId);
          transaction.set(manufacturerRef, {
            'id': manufacturerId,
            'name': manufacturer,
          });
          
          // 모델 추가
          final models = data[manufacturer] ?? [];
          for (final model in models) {
            final modelId = model['id'] ?? '';
            final modelName = model['model'] ?? '';
            
            if (modelId.isNotEmpty && modelName.isNotEmpty) {
              final modelRef = _firestore.collection('car_models').doc('${manufacturerId}_$modelId');
              transaction.set(modelRef, {
                'id': modelId,
                'model': modelName,
                'manufacturerId': manufacturerId,
              });
            }
          }
        }
      });
      
      return true;
    } catch (e) {
      print('Error migrating data: $e');
      return false;
    }
  }
}
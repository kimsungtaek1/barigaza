class CarManufacturer {
  final String id;
  final String name;
  
  CarManufacturer({
    required this.id,
    required this.name,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
  
  factory CarManufacturer.fromMap(Map<String, dynamic> map) {
    return CarManufacturer(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
    );
  }
}

class CarModel {
  final String id;
  final String model;
  final String manufacturerId;
  
  CarModel({
    required this.id,
    required this.model,
    required this.manufacturerId,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'model': model,
      'manufacturerId': manufacturerId,
    };
  }
  
  factory CarModel.fromMap(Map<String, dynamic> map) {
    return CarModel(
      id: map['id'] ?? '',
      model: map['model'] ?? '',
      manufacturerId: map['manufacturerId'] ?? '',
    );
  }
}
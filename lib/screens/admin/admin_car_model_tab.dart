import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/car_model.dart';
import '../../services/car_model_service.dart';

class AdminCarModelTab extends StatefulWidget {
  final Function(bool) onSelectionModeChanged;
  final Function(List<String>) onSelectionChanged;
  final bool selectionMode;
  
  const AdminCarModelTab({
    Key? key,
    required this.onSelectionModeChanged,
    required this.onSelectionChanged,
    required this.selectionMode,
  }) : super(key: key);
  
  @override
  _AdminCarModelTabState createState() => _AdminCarModelTabState();
}

class _AdminCarModelTabState extends State<AdminCarModelTab> {
  final CarModelService _carModelService = CarModelService();
  String? _selectedManufacturerId;
  List<String> _selectedItems = [];
  bool _isAddingManufacturer = false;
  bool _isAddingModelInline = false;
  final TextEditingController _manufacturerController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  String? _editingId;
  
  @override
  void didUpdateWidget(AdminCarModelTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.selectionMode && oldWidget.selectionMode) {
      setState(() {
        _selectedItems = [];
      });
    }
  }
  
  @override
  void dispose() {
    _manufacturerController.dispose();
    _modelController.dispose();
    super.dispose();
  }
  
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedItems.contains(id)) {
        _selectedItems.remove(id);
      } else {
        _selectedItems.add(id);
      }
      widget.onSelectionChanged(_selectedItems);
    });
  }
  
  void _showAddManufacturerDialog() {
    setState(() {
      _isAddingManufacturer = true;
      _manufacturerController.clear();
      _editingId = null;
    });
  }
  
  void _showEditManufacturerDialog(CarManufacturer manufacturer) {
    setState(() {
      _isAddingManufacturer = true;
      _manufacturerController.text = manufacturer.name;
      _editingId = manufacturer.id;
    });
  }
  
  void _showAddModelInline() {
    if (_selectedManufacturerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('먼저 제조사를 선택해주세요.')),
      );
      return;
    }
    
    setState(() {
      _isAddingModelInline = true;
      _modelController.clear();
      _editingId = null;
    });
  }
  
  void _showEditModelDialog(CarModel model) {
    setState(() {
      _isAddingModelInline = true;
      _modelController.text = model.model;
      _editingId = model.id;
    });
  }
  
  Future<void> _saveManufacturer() async {
    if (_manufacturerController.text.trim().isEmpty) return;
    
    bool success;
    if (_editingId != null) {
      success = await _carModelService.updateManufacturer(
        _editingId!,
        _manufacturerController.text.trim(),
      );
    } else {
      success = await _carModelService.addManufacturer(
        _manufacturerController.text.trim(),
      );
    }
    
    if (success) {
      setState(() {
        _isAddingManufacturer = false;
        _editingId = null;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류가 발생했습니다. 다시 시도해주세요.')),
      );
    }
  }
  
  Future<void> _saveModel() async {
    if (_modelController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('모델 이름을 입력해주세요.')),
      );
      return;
    }

    if (_selectedManufacturerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('제조사가 선택되지 않았습니다. 다시 시도해주세요.')),
      );
      setState(() {
        _isAddingModelInline = false;
      });
      return;
    }
    
    setState(() {
      // 저장 중임을 표시하는 상태 추가 가능 (로딩 인디케이터 등)
    });
    
    bool success;
    if (_editingId != null) {
      final docId = '${_selectedManufacturerId}_$_editingId';
      success = await _carModelService.updateModel(
        docId,
        _modelController.text.trim(),
      );
    } else {
      success = await _carModelService.addModel(
        _selectedManufacturerId!,
        _modelController.text.trim(),
      );
    }
    
    if (success) {
      setState(() {
        _isAddingModelInline = false;
        _editingId = null;
        _modelController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_editingId == null ? '모델이 추가되었습니다.' : '모델이 수정되었습니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류가 발생했습니다. 다시 시도해주세요.')),
      );
    }
  }
  
  Future<void> _deleteManufacturer(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('제조사 삭제'),
        content: Text('이 제조사를 삭제하면 모든 모델도 함께 삭제됩니다. 계속하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await _carModelService.deleteManufacturer(id);
      if (success) {
        if (_selectedManufacturerId == id) {
          setState(() {
            _selectedManufacturerId = null;
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 중 오류가 발생했습니다.')),
        );
      }
    }
  }
  
  Future<void> _deleteModel(String manufacturerId, String modelId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('모델 삭제'),
        content: Text('이 모델을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final docId = '${manufacturerId}_$modelId';
      final success = await _carModelService.deleteModel(docId);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 중 오류가 발생했습니다.')),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // Manufacturer List
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '차량 제조사',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  // 제조사 추가 버튼 제거
                ],
              ),
            ),
            Container(
              height: 120,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: StreamBuilder<List<CarManufacturer>>(
                stream: _carModelService.streamManufacturers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Text('등록된 차량 제조사가 없습니다.'),
                    );
                  }
                  
                  final manufacturers = snapshot.data!;
                  
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: manufacturers.length,
                    separatorBuilder: (context, index) => SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final manufacturer = manufacturers[index];
                      final isSelected = _selectedManufacturerId == manufacturer.id;
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedManufacturerId = isSelected ? null : manufacturer.id;
                          });
                        },
                        child: Container(
                          width: 100,
                          decoration: BoxDecoration(
                            color: isSelected ? Color(0xFF746B5D) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Color(0xFF746B5D) : Colors.grey[300]!,
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Text(
                                    manufacturer.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : Colors.black,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              // 제조사 편집/삭제 버튼 제거
                              if (widget.selectionMode)
                                Checkbox(
                                  value: _selectedItems.contains(manufacturer.id),
                                  onChanged: (value) {
                                    _toggleSelection(manufacturer.id);
                                  },
                                  activeColor: Colors.blue,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            
            // Models List
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey[100],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '차량 모델',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (_selectedManufacturerId != null)
                    IconButton(
                      icon: Icon(Icons.add_circle_outline),
                      onPressed: _showAddModelInline,
                    ),
                ],
              ),
            ),
            Expanded(
              child: _selectedManufacturerId == null
                ? Center(
                    child: Text('제조사를 선택하세요.'),
                  )
                : Column(
                    children: [
                      // 인라인 모델 추가 폼
                      if (_isAddingModelInline)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: Colors.grey[200],
                          child: Row(
                            children: [
                              StreamBuilder<List<CarManufacturer>>(
                                stream: _carModelService.streamManufacturers(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) {
                                    return SizedBox();
                                  }
                                  
                                  final manufacturers = snapshot.data!;
                                  final selectedManufacturer = manufacturers
                                      .firstWhere(
                                        (m) => m.id == _selectedManufacturerId,
                                        orElse: () => CarManufacturer(id: '', name: ''),
                                      );
                                  
                                  return Text(
                                    '${selectedManufacturer.name} > ',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  );
                                },
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _modelController,
                                  decoration: InputDecoration(
                                    hintText: '모델명을 입력하세요',
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  autofocus: true,
                                ),
                              ),
                              ElevatedButton(
                                onPressed: _saveModel,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF746B5D),
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  minimumSize: Size(60, 36),
                                ),
                                child: Text('저장'),
                              ),
                              SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.close),
                                onPressed: () {
                                  setState(() {
                                    _isAddingModelInline = false;
                                    _editingId = null;
                                    _modelController.clear();
                                  });
                                },
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                                iconSize: 20,
                              ),
                            ],
                          ),
                        ),
                      
                      // 모델 목록
                      Expanded(
                        child: StreamBuilder<List<CarModel>>(
                          stream: _carModelService.streamModels(_selectedManufacturerId!),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Center(child: CircularProgressIndicator());
                            }
                            
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return Center(
                                child: Text('등록된 차량 모델이 없습니다.'),
                              );
                            }
                            
                            final models = snapshot.data!;
                            
                            return ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: models.length,
                              separatorBuilder: (context, index) => Divider(height: 1),
                              itemBuilder: (context, index) {
                                final model = models[index];
                                final docId = '${model.manufacturerId}_${model.id}';
                                
                                return ListTile(
                                  title: Text(model.model),
                                  trailing: widget.selectionMode
                                      ? Checkbox(
                                          value: _selectedItems.contains(docId),
                                          onChanged: (value) {
                                            _toggleSelection(docId);
                                          },
                                          activeColor: Colors.blue,
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: ImageIcon(AssetImage('assets/images/pencil_selected.png')),
                                              onPressed: () => _showEditModelDialog(model),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.delete),
                                              onPressed: () => _deleteModel(
                                                model.manufacturerId,
                                                model.id,
                                              ),
                                            ),
                                          ],
                                        ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
            ),
          ],
        ),
        
        // 모달 대화상자 제거 - 인라인 폼으로 대체
      ],
    );
  }
}
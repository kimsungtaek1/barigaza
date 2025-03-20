import 'package:flutter/material.dart';
import '../../services/content_filter_service.dart';

class AdminContentFilterScreen extends StatefulWidget {
  const AdminContentFilterScreen({Key? key}) : super(key: key);

  @override
  _AdminContentFilterScreenState createState() => _AdminContentFilterScreenState();
}

class _AdminContentFilterScreenState extends State<AdminContentFilterScreen> {
  final ContentFilterService _filterService = ContentFilterService();
  final TextEditingController _newWordController = TextEditingController();
  List<String> _bannedWords = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadBannedWords();
  }

  @override
  void dispose() {
    _newWordController.dispose();
    super.dispose();
  }

  Future<void> _loadBannedWords() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // ContentFilterService를 통해 금칙어 목록 로드
      await _filterService.initialize();
      _bannedWords = _filterService.getBannedWords();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '금칙어 목록을 불러오는 중 오류가 발생했습니다: $e';
      });
    }
  }

  Future<void> _saveBannedWords() async {
    setState(() {
      _isSaving = true;
      _errorMessage = '';
    });

    try {
      await _filterService.updateBannedWords(_bannedWords);
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('금칙어 목록이 저장되었습니다.')),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = '금칙어 목록을 저장하는 중 오류가 발생했습니다: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 중 오류가 발생했습니다: $e')),
      );
    }
  }

  void _addBannedWord() {
    final word = _newWordController.text.trim();
    if (word.isEmpty) return;

    if (!_bannedWords.contains(word)) {
      setState(() {
        _bannedWords.add(word);
        _newWordController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 존재하는 금칙어입니다.')),
      );
    }
  }

  void _removeBannedWord(String word) {
    setState(() {
      _bannedWords.remove(word);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 새로고침 및 저장 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '새로고침',
                onPressed: _loadBannedWords,
              ),
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: '저장',
                onPressed: _isSaving ? null : _saveBannedWords,
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                tooltip: '금칙어 추가',
                onPressed: () {
                  _newWordController.clear();
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('금칙어 추가'),
                      content: TextField(
                        controller: _newWordController,
                        decoration: const InputDecoration(
                          labelText: '추가할 금칙어',
                          hintText: '금칙어를 입력하세요',
                        ),
                        autofocus: true,
                        onSubmitted: (_) {
                          _addBannedWord();
                          Navigator.pop(context);
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('취소'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            _addBannedWord();
                            Navigator.pop(context);
                          },
                          child: const Text('추가'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                _errorMessage,
                style: TextStyle(color: Colors.red),
              ),
            ),
          
          // 로딩 상태 또는 금칙어 목록 표시
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _bannedWords.isEmpty
                ? const Center(child: Text('등록된 금칙어가 없습니다.'))
                : ListView.builder(
                    itemCount: _bannedWords.length,
                    itemBuilder: (context, index) {
                      final word = _bannedWords[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        child: ListTile(
                          title: Text(word),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeBannedWord(word),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String otherUserName;
  final bool isGroupChat;

  const ChatScreen({
    Key? key,
    required this.chatRoomId,
    required this.otherUserName,
    this.isGroupChat = false,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _currentUser = FirebaseAuth.instance.currentUser!;
  bool _isShowingParticipants = false;
  bool _isLoading = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _saveImage(String imageUrl) async {
    setState(() => _isLoading = true);

    try {
      // 1. 저장소 권한 확인
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('저장소 접근 권한이 필요합니다');
      }

      // 2. 이미지 다운로드
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('이미지 다운로드 실패');
      }

      // 3. 저장 경로 설정
      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${appDir.path}/downloads');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // 4. 파일 이름 생성 및 저장
      final fileName =
          'chat_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${downloadsDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      // 5. Android 전용: 다운로드 폴더에도 저장
      if (Platform.isAndroid) {
        final downloadsPath = '/storage/emulated/0/Download';
        final downloadFile = File('$downloadsPath/$fileName');
        await downloadFile.writeAsBytes(response.bodyBytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지가 저장되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      setState(() => _isLoading = true);

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );

      if (image != null) {
        await _chatService.sendImageMessage(
            widget.chatRoomId, File(image.path));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 전송에 실패했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showImageOptions() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('갤러리에서 선택'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: Icon(Icons.camera_alt),
              title: Text('사진 촬영'),
              onTap: () async {
                Navigator.pop(context);
                setState(() => _isLoading = true);
                try {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 70,
                  );
                  if (image != null) {
                    await _chatService.sendImageMessage(
                        widget.chatRoomId, File(image.path));
                    _scrollToBottom();
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorWidget: (context, url, error) => Icon(Icons.error),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.download),
                  label: Text('저장'),
                  onPressed: () {
                    Navigator.pop(context);
                    _saveImage(imageUrl);
                  },
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.share),
                  label: Text('공유'),
                  onPressed: () {
                    // 공유 기능 구현
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.isGroupChat ? '단체 채팅방' : widget.otherUserName),
          if (widget.isGroupChat)
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.getParticipants(widget.chatRoomId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return SizedBox();
                return Text(
                  '참여자 ${snapshot.data!.length}명',
                  style: TextStyle(fontSize: 12),
                );
              },
            ),
        ],
      ),
      actions: [
        if (widget.isGroupChat)
          IconButton(
            icon: Icon(Icons.group),
            onPressed: () {
              setState(() => _isShowingParticipants = !_isShowingParticipants);
            },
          ),
        PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'leave',
              child: Text('채팅방 나가기'),
            ),
          ],
          onSelected: (value) async {
            if (value == 'leave') {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('채팅방 나가기'),
                  content: Text('정말 채팅방을 나가시겠습니까?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('취소'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('나가기'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await _chatService.leaveChatRoom(widget.chatRoomId);
                if (mounted) {
                  Navigator.pop(context);
                }
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Column(
          children: [
            if (_isShowingParticipants) _buildParticipantsList(),
            Expanded(
              child: _buildMessageList(),
            ),
            _buildInputArea(),
          ],
        ),
        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _buildParticipantsList() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatService.getParticipants(widget.chatRoomId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final participants = snapshot.data!;

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: participants.length,
            itemBuilder: (context, index) {
              final user = participants[index];
              return Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: user['profileImage'] != null
                          ? NetworkImage(user['profileImage'])
                          : null,
                      child: user['profileImage'] == null
                          ? Text(
                              user['nickname'][0],
                              style: TextStyle(fontSize: 20),
                            )
                          : null,
                    ),
                    SizedBox(height: 4),
                    Text(
                      user['nickname'],
                      style: TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getMessages(widget.chatRoomId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data!.docs;

        return ListView.builder(
          reverse: true,
          controller: _scrollController,
          padding: EdgeInsets.only(bottom: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index].data() as Map<String, dynamic>;
            final isMe = message['senderId'] == _currentUser.uid;

            return Padding(
              padding: EdgeInsets.only(
                top: 8,
                bottom: 8,
                left: isMe ? 64 : 16,
                right: isMe ? 16 : 64,
              ),
              child: message['type'] == 'image'
                  ? _buildImageMessage(message, isMe)
                  : _buildTextMessage(message, isMe),
            );
          },
        );
      },
    );
  }

  Widget _buildTextMessage(Map<String, dynamic> message, bool isMe) {
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (widget.isGroupChat && !isMe)
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 4),
            child: Text(
              message['senderName'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: isMe ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.circular(20),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            message['message'],
            style: TextStyle(
              color: isMe ? Colors.white : Colors.black,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 4, left: 8, right: 8),
          child: Text(
            _formatTimestamp(message['timestamp']),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageMessage(Map<String, dynamic> message, bool isMe) {
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (widget.isGroupChat && !isMe)
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 4),
            child: Text(
              message['senderName'],
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        GestureDetector(
          onTap: () => _showImageDialog(message['imageUrl']),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
              maxHeight: 200,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[300],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: message['imageUrl'],
                placeholder: (context, url) => Container(
                  width: 50,
                  height: 50,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Icon(Icons.error),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 4, left: 8, right: 8),
          child: Text(
            _formatTimestamp(message['timestamp']),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.add_photo_alternate),
              onPressed: _showImageOptions,
              color: Colors.grey[600],
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                maxLines: null,
                onChanged: (text) {
                  setState(() => _isTyping = text.trim().isNotEmpty);
                },
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (_isTyping) _sendMessage();
                },
              ),
            ),
            IconButton(
              icon: Icon(Icons.send),
              onPressed: _isTyping ? _sendMessage : null,
              color: _isTyping ? Colors.blue : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    if (!_isTyping) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();
    setState(() => _isTyping = false);

    _chatService.sendMessage(widget.chatRoomId, messageText).then((_) {
      _scrollToBottom();
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메시지 전송에 실패했습니다: $e')),
        );
      }
    });
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final messageTime = timestamp.toDate();
    final difference = now.difference(messageTime);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${messageTime.year}.${messageTime.month}.${messageTime.day}';
    }
  }
}

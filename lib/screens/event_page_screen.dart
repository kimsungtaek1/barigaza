import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';

class EventsListScreen extends StatefulWidget {
  const EventsListScreen({Key? key}) : super(key: key);

  @override
  _EventsListScreenState createState() => _EventsListScreenState();
}

class _EventsListScreenState extends State<EventsListScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '이벤트',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey[200],
            height: 1.0,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 활성화된 이벤트만 가져오기
        stream: FirebaseFirestore.instance
            .collection('events')
            .where('isActive', isEqualTo: true) // isActive가 true인 문서만 필터링
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final events = snapshot.data?.docs ?? [];

          if (events.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '현재 진행중인 이벤트가 없습니다',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = Event.fromFirestore(events[index]);
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EventDetailScreen(event: event),
                    ),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (event.imageUrl.isNotEmpty)
                        Image.network(
                          event.imageUrl,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: double.infinity,
                              height: 200,
                              color: Colors.grey[300],
                              child: const Icon(Icons.error_outline),
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status indicator moved above the title
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: DateTime.now().isBefore(event.endDate)
                                      ? Colors.green[100]
                                      : Colors.pink[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  DateTime.now().isBefore(event.endDate)
                                      ? '진행중'
                                      : '마감',
                                  style: TextStyle(
                                    color: DateTime.now().isBefore(event.endDate)
                                        ? Colors.green[800]
                                        : Colors.red[800],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8), // Add space between status and title
                              Text(
                                event.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Location Row (Icon + Text)
                              Row(
                                children: [
                                  Image.asset('assets/images/marker.png', width: 14, height: 14, color: Colors.grey[600]), // Adjusted size
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      event.location ?? '주소 정보 없음',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 12, // Adjusted font size
                                      ),
                                      overflow: TextOverflow.ellipsis, // Prevent overflow
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4), // Reduced space
                              // Date Row (Icon + Text)
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]), // Adjusted size
                                  const SizedBox(width: 4),
                                  Text(
                                    '${DateFormat('yyyy.MM.dd').format(event.startDate)} ~ ${DateFormat('yyyy.MM.dd').format(event.endDate)}',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12, // Adjusted font size
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EventDetailScreen extends StatelessWidget {
  final Event event;

  const EventDetailScreen({
    Key? key,
    required this.event,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // final Color lightGrey = Colors.grey[100]!; // Define light grey color - No longer needed directly here

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '이벤트', // Change AppBar title
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey[200],
            height: 1.0,
          ),
        ),
      ),
      body: Container( // Add container for background color
        color: const Color(0xFFF9FAFB), // Changed background color
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.imageUrl.isNotEmpty) ...[ // Use spread operator
                // Removed the image label Padding widget
                Image.network(
                  event.imageUrl,
                  width: double.infinity,
                  height: MediaQuery.of(context).size.height * 0.3, // Change height to 30%
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: double.infinity,
                      height: MediaQuery.of(context).size.height * 0.3, // Change error height to 30%
                      color: Colors.grey[300],
                      child: const Icon(Icons.error_outline),
                    );
                  },
                ),
              ], // Close spread operator
              Card( // Wrap details in a Card
                margin: const EdgeInsets.all(16.0), // Restored original margin
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row( // Row for title and status
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container( // Status indicator
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: DateTime.now().isBefore(event.endDate)
                                  ? Colors.green[100]
                                  : Colors.pink[100],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              DateTime.now().isBefore(event.endDate)
                                  ? '진행중'
                                  : '마감',
                              style: TextStyle(
                                color: DateTime.now().isBefore(event.endDate)
                                    ? Colors.green[800]
                                    : Colors.red[800],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Removed subtitle display
                      const SizedBox(height: 16),
                      Row( // Row for address
                        children: [
                          Image.asset('assets/images/marker.png', width: 16, height: 16, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              event.location ?? '주소 정보 없음',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row( // Row for date
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text(
                            '${DateFormat('yyyy.MM.dd').format(event.startDate)} ~ ${DateFormat('yyyy.MM.dd').format(event.endDate)}',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Outer Card for "이벤트 정보"
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16.0), // Reduced top/bottom margin
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '이벤트 정보',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8), // Reduced space before the first inner card
                      // Inner Card for "이벤트 제목" (ExpansionTile)
                      Card(
                        elevation: 0, // Remove shadow for inner card
                        margin: EdgeInsets.zero, // Remove margin for inner card
                        shape: RoundedRectangleBorder( // Optional: Add border
                          side: BorderSide(color: Colors.grey[200]!),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            dividerColor: Colors.transparent, // Remove divider
                          ),
                          child: ExpansionTile(
                            title: Row( // Row for icon and title
                              children: [
                                Icon(Icons.star, color: Color(0xFF5C9EEE), size: 20), // Star icon
                                SizedBox(width: 8),
                                const Text('이벤트 설명', style: TextStyle(fontWeight: FontWeight.bold)), // Changed title
                              ],
                            ),
                            initiallyExpanded: true,
                            iconColor: Colors.grey[400], // Set icon color to grey 400
                            collapsedIconColor: Colors.grey[400], // Set collapsed icon color to grey 400
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0), // Removed vertical padding
                            visualDensity: VisualDensity.compact, // Added compact density
                            childrenPadding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0), // Restored bottom padding
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  event.content,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16), // Space between inner cards
                      // Inner Card for "링크" (ExpansionTile)
                      Card(
                        elevation: 0, // Remove shadow for inner card
                        margin: EdgeInsets.zero, // Remove margin for inner card
                         shape: RoundedRectangleBorder( // Optional: Add border
                          side: BorderSide(color: Colors.grey[200]!),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            dividerColor: Colors.transparent, // Remove divider
                          ),
                          child: ExpansionTile(
                            title: Row( // Row for icon and title
                              children: [
                                Icon(Icons.link, color: Colors.grey[400], size: 20), // Link icon
                                SizedBox(width: 8),
                                const Text('링크', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            initiallyExpanded: true,
                            iconColor: Colors.grey[400], // Set icon color to grey 400
                            collapsedIconColor: Colors.grey[400], // Set collapsed icon color to grey 400
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0), // Removed vertical padding
                            visualDensity: VisualDensity.compact, // Added compact density
                            childrenPadding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0), // Restored bottom padding
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  event.link ?? '링크 정보 없음',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: Colors.black87
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16), // Add some bottom padding
            ], // End of main Column children
          ),
        ),
      ),
    );
  }
}

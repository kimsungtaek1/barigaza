import 'package:cloud_firestore/cloud_firestore.dart';

class Event {
  final String id;
  final String title;
  // final String subtitle; // Removed subtitle
  final String content;
  final String imageUrl;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;
  final String? location; // Add location field
  final String? link;     // Add link field

  Event({
    required this.id,
    required this.title,
    // required this.subtitle, // Removed subtitle
    required this.content,
    required this.imageUrl,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
    this.location, // Add to constructor
    this.link,     // Add to constructor
  });

  factory Event.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Event(
      id: doc.id,
      title: data['title'] ?? '',
      // subtitle: data['subtitle'] ?? '', // Removed subtitle
      content: data['content'] ?? '',
      imageUrl: data['imageUrl'] ?? '',
      startDate: data['startDate'] != null
          ? (data['startDate'] as Timestamp).toDate()
          : DateTime.now(),
      endDate: data['endDate'] != null
          ? (data['endDate'] as Timestamp).toDate()
          : DateTime.now(),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      isActive: data['isActive'] ?? true,
      location: data['location'] as String?, // Read location from Firestore
      link: data['link'] as String?,         // Read link from Firestore
    );
  }

  Map<String, dynamic> toFirestore() {
    final data = {
      'title': title,
      // 'subtitle': subtitle, // Removed subtitle
      'content': content,
      'imageUrl': imageUrl,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'location': location, // Add location to Firestore map (optional, if writing)
      'link': link,         // Add link to Firestore map (optional, if writing)
    };

    if (updatedAt != null) {
      data['updatedAt'] = Timestamp.fromDate(updatedAt!);
    }

    // Remove null values before sending to Firestore (optional, good practice)
    data.removeWhere((key, value) => value == null);

    return data;
  }
}

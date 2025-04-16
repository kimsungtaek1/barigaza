import 'package:cloud_firestore/cloud_firestore.dart';

class MeetingPoint {
  final String id;
  final String hostId;
  final String hostName;
  final String departureAddress;
  final String departureDetailAddress;
  final String destinationAddress;
  final String destinationDetailAddress;
  final DateTime meetingTime;
  final GeoPoint location;
  final List<String> participants;
  final String title;
  final DateTime createdAt;
  final String status; // 상태 필드 추가: 'active', 'completed', 'deleted' 등

  MeetingPoint({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.departureAddress,
    required this.departureDetailAddress,
    required this.destinationAddress,
    required this.destinationDetailAddress,
    required this.meetingTime,
    required this.location,
    required this.participants,
    required this.title,
    required this.createdAt,
    this.status = 'active', // 기본값은 'active'
  });

  factory MeetingPoint.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MeetingPoint(
      id: doc.id,
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? '알 수 없음',
      departureAddress: data['departureAddress'] ?? '',
      departureDetailAddress: data['departureDetailAddress'] ?? '',
      destinationAddress: data['destinationAddress'] ?? '',
      destinationDetailAddress: data['destinationDetailAddress'] ?? '',
      meetingTime: data['meetingTime'] != null
          ? (data['meetingTime'] as Timestamp).toDate()
          : DateTime.now(),
      location: data['location'] ?? GeoPoint(0, 0),
      participants: List<String>.from(data['participants'] ?? []),
      title: data['title'] ?? '제목 없음',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      status: data['status'] ?? 'active', // 상태 필드 추가
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hostId': hostId,
      'hostName': hostName,
      'departureAddress': departureAddress,
      'departureDetailAddress': departureDetailAddress,
      'destinationAddress': destinationAddress,
      'destinationDetailAddress': destinationDetailAddress,
      'meetingTime': Timestamp.fromDate(meetingTime),
      'location': location,
      'participants': participants,
      'title': title,
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status, // 상태 필드 추가
    };
  }
}
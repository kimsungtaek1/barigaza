import 'package:cloud_firestore/cloud_firestore.dart';

class MeetingPoint {
  final String id;
  final String hostName;
  final String hostId;
  final String departureAddress;
  final String departureDetailAddress;
  final String destinationAddress;
  final String destinationDetailAddress;
  final DateTime meetingTime;
  final GeoPoint location;
  final List<String> participants;
  final DateTime? createdAt;

  MeetingPoint({
    required this.id,
    required this.hostName,
    required this.hostId,
    required this.departureAddress,
    required this.departureDetailAddress,
    required this.destinationAddress,
    required this.destinationDetailAddress,
    required this.meetingTime,
    required this.location,
    required this.participants,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'hostName': hostName,
      'hostId': hostId,
      'departureAddress': departureAddress,
      'departureDetailAddress': departureDetailAddress,
      'destinationAddress': destinationAddress,
      'destinationDetailAddress': destinationDetailAddress,
      'meetingTime': Timestamp.fromDate(meetingTime),
      'location': location,
      'participants': participants,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory MeetingPoint.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MeetingPoint(
      id: doc.id,
      hostName: data['hostName'] ?? '',
      hostId: data['hostId'] ?? '',
      departureAddress: data['departureAddress'] ?? '',
      departureDetailAddress: data['departureDetailAddress'] ?? '',
      destinationAddress: data['destinationAddress'] ?? '',
      destinationDetailAddress: data['destinationDetailAddress'] ?? '',
      meetingTime: (data['meetingTime'] as Timestamp).toDate(),
      location: data['location'] as GeoPoint,
      participants: List<String>.from(data['participants'] ?? []),
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }
}

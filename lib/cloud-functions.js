const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// 3시간마다 실행되는 스케줄링된 함수
exports.checkExpiredMeetings = functions.pubsub
  .schedule('every 3 hours')
  .onRun(async (context) => {
    const firestore = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    
    try {
      // 활성화된 모임만 가져오기
      const meetingsSnapshot = await firestore
        .collection('meetings')
        .where('status', '==', 'active')
        .get();
      
      if (meetingsSnapshot.empty) {
        console.log('No active meetings to check');
        return null;
      }
      
      const batch = firestore.batch();
      let updatedCount = 0;
      
      meetingsSnapshot.docs.forEach((doc) => {
        const data = doc.data();
        if (data.meetingTime) {
          // 모임 시간 + 3시간 계산
          const meetingTime = data.meetingTime.toDate();
          const expiryTime = new Date(meetingTime.getTime() + (3 * 60 * 60 * 1000)); // 3시간 추가
          
          // 만료 시간이 현재보다 이전이면 상태 업데이트
          if (expiryTime <= now.toDate()) {
            batch.update(doc.ref, {
              status: 'completed',
              completedAt: now,
              updatedAt: now
            });
            
            // 채팅방에 모임 종료 공지 메시지 보내기
            const chatRoomId = data.chatRoomId || `meeting_${doc.id}`;
            const chatMessageRef = firestore
              .collection('chatRooms')
              .doc(chatRoomId)
              .collection('messages')
              .doc();
              
            batch.set(chatMessageRef, {
              senderId: 'system',
              senderName: '시스템',
              message: '[공지] 이 번개모임은 종료되었습니다.',
              type: 'text',
              timestamp: now
            });
            
            // 채팅방 마지막 메시지 업데이트
            const chatRoomRef = firestore
              .collection('chatRooms')
              .doc(chatRoomId);
              
            batch.update(chatRoomRef, {
              lastMessage: '[공지] 이 번개모임은 종료되었습니다.',
              lastMessageTime: now
            });
            
            updatedCount++;
          }
        }
      });
      
      if (updatedCount > 0) {
        await batch.commit();
        console.log(`Updated ${updatedCount} expired meetings to completed status`);
      } else {
        console.log('No meetings to update');
      }
      
      return null;
    } catch (error) {
      console.error('Error checking expired meetings:', error);
      return null;
    }
  });

// 새 모임이 생성될 때 3시간 후에 만료되도록 스케줄링하는 함수
exports.scheduleMeetingExpiry = functions.firestore
  .document('meetings/{meetingId}')
  .onCreate(async (snapshot, context) => {
    const meetingData = snapshot.data();
    const meetingId = context.params.meetingId;
    
    if (!meetingData.meetingTime) {
      console.log('Meeting has no meeting time, skipping expiry scheduling');
      return null;
    }
    
    try {
      // 모임 시간 + 3시간 계산
      const meetingTime = meetingData.meetingTime.toDate();
      const expiryTime = new Date(meetingTime.getTime() + (3 * 60 * 60 * 1000));
      
      // 현재 시간이 이미 만료 시간을 지났는지 확인
      const now = new Date();
      if (expiryTime <= now) {
        // 이미 만료되었다면 바로 상태 업데이트
        await admin.firestore().collection('meetings').doc(meetingId).update({
          status: 'completed',
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        
        console.log(`Meeting ${meetingId} already expired, updated immediately`);
      } else {
        // 아직 만료되지 않았다면 기록만 남김 (실제 업데이트는 스케줄링된 함수에서 수행)
        console.log(`Scheduled meeting ${meetingId} to expire at ${expiryTime}`);
      }
      
      return null;
    } catch (error) {
      console.error('Error scheduling meeting expiry:', error);
      return null;
    }
  });
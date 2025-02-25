import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// 기본 Firebase 설정 옵션
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDHoilz_NxTcOu8ZoTe5V8SNOMCdaoE71Q',
    appId: '1:334968888840:android:9ea29bcde23448040c3bbd',
    messagingSenderId: '334968888840',
    projectId: 'barigaza-796a1',
    storageBucket: 'barigaza-796a1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBxogXsJfVehMPgi19yyPyVPwnp9dH2N8I',
    appId: '1:725637285597:ios:faa5a7aaccc67dcccefd34',
    messagingSenderId: '334968888840',
    projectId: 'barigaza-796a1',
    storageBucket: 'barigaza-796a1.firebasestorage.app',
    androidClientId: '725637285597-np20kfr2v0bjd5ud658uqmoskmce0n0s.apps.googleusercontent.com',
    iosClientId: '725637285597-010vmecc3bs2f5418lr74sjdf6vldld5.apps.googleusercontent.com',
    iosBundleId: 'com.barigaza.barigaza',
  );

}
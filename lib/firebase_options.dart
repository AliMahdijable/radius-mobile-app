// File generated manually from the Firebase project "myservices-radius".
// Mirrors what `flutterfire configure` produces — kept in source instead of
// auto-loading GoogleService-Info.plist / google-services.json so the iOS
// build doesn't depend on the plist being registered in the Xcode project
// (the most common cause of a white-screen TestFlight build).

// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web — '
        'reconfigure this file to provide web options if needed.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macOS.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAL2cvEU82mbie61bhIcQHG1hiYil0tj5M',
    appId: '1:712556570451:android:ff4e8b7e792a5715c363a6',
    messagingSenderId: '712556570451',
    projectId: 'myservices-radius',
    storageBucket: 'myservices-radius.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCSUszltOcFv9rs5IcP_rGBvRx5JMvFSVs',
    appId: '1:712556570451:ios:9933b736680adf90c363a6',
    messagingSenderId: '712556570451',
    projectId: 'myservices-radius',
    storageBucket: 'myservices-radius.firebasestorage.app',
    iosBundleId: 'com.mysvcs.radMysvcs',
  );
}

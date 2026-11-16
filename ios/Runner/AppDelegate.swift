import Flutter
import UIKit
import GoogleMaps
#if DEBUG && BTS_FIREBASE_DEMO
import FirebaseCore
import FirebaseAnalytics
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // TODO: Replace YOUR_API_KEY_HERE with your actual Google Maps API key
    GMSServices.provideAPIKey("YOUR_API_KEY_HERE")

    #if DEBUG && BTS_FIREBASE_DEMO
    // Match the Dart demo configuration before FlutterFire can discover the
    // production GoogleService-Info.plist bundled with the native app.
    let demo = FirebaseOptions(
      googleAppID: "1:1234567890:ios:1234567890abcdef",
      gcmSenderID: "1234567890"
    )
    demo.apiKey = "AIza00000000000000000000000000000000000"
    demo.projectID = "demo-bts-delivery"
    demo.storageBucket = "demo-bts-delivery.appspot.com"
    Analytics.setAnalyticsCollectionEnabled(false)
    FirebaseApp.configure(options: demo)
    FirebaseApp.app()?.isDataCollectionDefaultEnabled = false
    #endif

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

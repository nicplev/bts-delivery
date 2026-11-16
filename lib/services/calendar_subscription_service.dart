import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/staff.dart';
import '../repositories/staff_repository.dart';
import 'result.dart';

/// Service for managing calendar subscriptions via webcal:// URLs
class CalendarSubscriptionService {
  final StaffRepository _staffRepository;

  // Firebase Cloud Functions URL for calendar feed
  static const String _baseCalendarUrl = 'https://us-central1-bts-delivery-app.cloudfunctions.net/calendar';

  CalendarSubscriptionService(this._staffRepository);

  /// Generate webcal:// URL for a staff member's calendar
  /// This URL can be subscribed to in iOS Calendar, Google Calendar, etc.
  Future<Result<String>> getSubscriptionUrl(Staff staff) async {
    try {
      // Ensure staff has a calendar token
      String token;
      if (staff.hasCalendarToken) {
        token = staff.calendarToken!;
      } else {
        // Generate a new token
        final result = await _staffRepository.generateCalendarToken(staff.id);
        if (result.isFailure) {
          return Result.failure(result.errorOrNull ?? 'Failed to generate token');
        }
        token = result.dataOrNull!;
      }

      // Build the webcals:// URL (secure HTTPS protocol for calendar subscriptions)
      // Note: webcals:// ensures HTTPS is used, required for Firebase Cloud Functions
      final httpsUrl = '$_baseCalendarUrl/$token.ics';
      final webcalUrl = httpsUrl.replaceFirst('https://', 'webcals://');

      return Result.success(webcalUrl);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting subscription URL: $e');
      }
      return Result.failure('Failed to generate subscription URL: $e');
    }
  }

  /// Get the HTTPS version of the calendar URL (for manual subscription)
  Future<Result<String>> getHttpsUrl(Staff staff) async {
    final result = await getSubscriptionUrl(staff);
    if (result.isFailure) {
      return result;
    }

    final webcalUrl = result.dataOrNull!;
    final httpsUrl = webcalUrl.replaceFirst('webcals://', 'https://');
    return Result.success(httpsUrl);
  }

  /// Open the calendar subscription URL in the device's default calendar app
  /// On iOS, this will prompt the user to subscribe to the calendar
  Future<Result<void>> openSubscriptionInCalendar(Staff staff) async {
    try {
      // Use webcals:// URL - iOS natively recognizes this for secure calendar subscriptions
      // webcals:// ensures HTTPS is used, required for Firebase Cloud Functions
      debugPrint('[CalendarService] Staff ID: ${staff.id}');
      debugPrint('[CalendarService] Staff hasToken: ${staff.hasCalendarToken}');
      debugPrint('[CalendarService] Staff token: ${staff.calendarToken ?? "null"}');

      final urlResult = await getSubscriptionUrl(staff);
      if (urlResult.isFailure) {
        return Result.failure(urlResult.errorOrNull ?? 'Failed to get URL');
      }

      final url = urlResult.dataOrNull!;
      final uri = Uri.parse(url);

      debugPrint('[CalendarService] Generated URL: $url');
      debugPrint('[CalendarService] URI scheme: ${uri.scheme}');

      // IMPORTANT: iOS Calendar can handle HTTPS URLs to .ics files directly
      // webcals:// doesn't work in iOS simulator, so we use HTTPS
      // iOS will automatically recognize the .ics extension and open Calendar
      final httpsUrl = url.replaceFirst('webcals://', 'https://');
      final httpsUri = Uri.parse(httpsUrl);

      debugPrint('[CalendarService] Using HTTPS URL for iOS: $httpsUrl');
      debugPrint('[CalendarService] Launching URL...');

      try {
        final launched = await launchUrl(
          httpsUri,
          mode: LaunchMode.externalApplication,
        );

        debugPrint('[CalendarService] launchUrl result: $launched');

        if (launched) {
          return const Result.success(null);
        } else {
          return const Result.failure('Failed to open calendar app. Please ensure iOS Calendar app is installed.');
        }
      } catch (e) {
        debugPrint('[CalendarService] launchUrl exception: $e');
        return Result.failure('Could not open calendar app: $e');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CalendarService] EXCEPTION: $e');
      }
      return Result.failure('Failed to open calendar: $e');
    }
  }

  /// Regenerate calendar token (revokes old subscription URL)
  /// Useful if user wants to revoke access or URL has been compromised
  Future<Result<String>> regenerateToken(Staff staff) async {
    try {
      final result = await _staffRepository.regenerateCalendarToken(staff.id);
      if (result.isFailure) {
        return Result.failure(result.errorOrNull ?? 'Failed to regenerate token');
      }

      final token = result.dataOrNull!;

      // Build new webcals URL (secure HTTPS protocol for calendar subscriptions)
      final httpsUrl = '$_baseCalendarUrl/$token.ics';
      final webcalUrl = httpsUrl.replaceFirst('https://', 'webcals://');

      return Result.success(webcalUrl);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error regenerating token: $e');
      }
      return Result.failure('Failed to regenerate token: $e');
    }
  }

  /// Check if calendar subscription is configured
  /// Returns true if the base URL has been set (not the default placeholder)
  bool isConfigured() {
    return !_baseCalendarUrl.contains('YOUR_FIREBASE_FUNCTIONS_URL');
  }

  /// Get instructions for subscribing to calendar on iOS
  String getIosInstructions() {
    return '''
To subscribe to your BTS Deliveries calendar on iOS:

1. Tap "Subscribe to Calendar" below
2. iOS Calendar app will open
3. Tap "Subscribe" in the top right
4. Your calendar will update automatically

The calendar will be named "BTS Deliveries" and will appear in your calendar list.
''';
  }

  /// Get instructions for subscribing to calendar on macOS
  String getMacOsInstructions(String url) {
    return '''
To subscribe on macOS:

1. Open Calendar app
2. Go to File > New Calendar Subscription
3. Paste this URL:
   $url
4. Click Subscribe
5. Choose refresh frequency (recommended: Every hour)
''';
  }

  /// Get instructions for subscribing to calendar on other platforms
  String getOtherPlatformInstructions(String httpsUrl) {
    return '''
To subscribe on other platforms:

Use this URL in your calendar app's subscription feature:
$httpsUrl

Most calendar apps support iCal/ICS subscriptions, including:
- Google Calendar (on web)
- Outlook
- Thunderbird
- Most other calendar applications
''';
  }
}

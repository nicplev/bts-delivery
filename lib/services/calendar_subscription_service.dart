import 'package:url_launcher/url_launcher.dart';
import '../models/staff.dart';
import '../repositories/staff_repository.dart';
import 'result.dart';

/// Service for managing calendar subscriptions via webcal:// URLs
class CalendarSubscriptionService {
  final StaffRepository _staffRepository;

  CalendarSubscriptionService(this._staffRepository);

  /// Generate webcal:// URL for a staff member's calendar
  /// This URL can be subscribed to in iOS Calendar, Google Calendar, etc.
  Future<Result<String>> getSubscriptionUrl(Staff staff) =>
      _staffRepository.getCalendarSubscriptionUrl(staff.id);

  Future<Result<void>> openSubscriptionInCalendar(Staff staff) async {
    final result = await getSubscriptionUrl(staff);
    final url = result.dataOrNull;
    if (url == null) {
      return Result.failure(result.errorOrNull ?? 'Could not get a calendar link.');
    }
    try {
      final uri = Uri.parse(url);
      final httpsUri = uri.scheme == 'webcals' ? uri.replace(scheme: 'https') : uri;
      final opened = await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
      return opened
          ? const Result.success(null)
          : const Result.failure('Could not open the calendar app.');
    } catch (_) {
      return const Result.failure('Could not open the calendar app.');
    }
  }

  Future<Result<String>> regenerateToken(Staff staff) async {
    return (await _staffRepository.regenerateCalendarToken(staff.id)).when(
      success: (token) => Result.success(calendarUrl(token, scheme: 'webcals')),
      failure: (message, error) => Result.failure(message, error),
    );
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

> **Legacy documentation:** This describes the earlier calendar subscription implementation. For the refresh branch, use the protected token flow and coordinated rollout in [REFRESH_PLAN.md](REFRESH_PLAN.md). Do not run the legacy token migration or copy these old access-rule examples into the refreshed deployment. Users must generate replacement subscriptions after the reviewed access migration.

# Calendar Subscription Setup Guide

This guide walks you through setting up the automatic calendar subscription feature for the BTS Delivery App.

## Overview

The calendar subscription feature allows staff members to subscribe to their delivery schedules via a webcal:// URL. The calendar automatically updates when deliveries are added or changed, without requiring manual syncing.

### How It Works

1. **Backend**: Firebase Cloud Functions generate dynamic .ics calendar feeds
2. **Per-User URLs**: Each staff member gets a unique subscription URL with a secure token
3. **Auto-Updates**: iOS Calendar (and other apps) check the URL periodically for updates
4. **Role-Based Filtering**: Each user sees only the deliveries they should see based on their role and assigned schools

### User Experience

- **Admins**: See all deliveries across all schools
- **Managers**: See all deliveries (or optionally only assigned schools)
- **Staff**: See only deliveries for schools they're assigned to

## Prerequisites

- Firebase project set up and configured
- Firebase CLI installed: `npm install -g firebase-tools`
- Node.js 18 (recommended for Cloud Functions)
- Admin access to Firebase project

## Step-by-Step Setup

### 1. Deploy Firestore Rules

The Firestore security rules have already been updated. Deploy them:

```bash
firebase deploy --only firestore:rules
```

This adds rules for:
- `calendar_metadata` collection (tracks calendar access)
- `system_metadata` collection (tracks last calendar update)

### 2. Install Cloud Functions Dependencies

```bash
cd functions
npm install
```

Required packages:
- `firebase-admin` - Firebase Admin SDK
- `firebase-functions` - Cloud Functions SDK
- `ical-generator` - Generate .ics calendar files
- `cors` - Handle CORS requests
- `express` - HTTP routing

### 3. Deploy Cloud Functions

```bash
# From functions directory
npm run deploy

# Or from project root
firebase deploy --only functions
```

This deploys two functions:
1. **calendar** - HTTP endpoint that generates calendar feeds
2. **onDeliveryChanged** - Firestore trigger that tracks delivery changes

After deployment, note the URL for the calendar function. It will be something like:
```
https://us-central1-bts-delivery-app.cloudfunctions.net/calendar
```

### 4. Update Calendar Service with Function URL

Open `lib/services/calendar_subscription_service.dart` and update line 11:

```dart
// Replace this:
static const String _baseCalendarUrl = 'YOUR_FIREBASE_FUNCTIONS_URL/calendar';

// With your actual URL:
static const String _baseCalendarUrl = 'https://us-central1-bts-delivery-app.cloudfunctions.net/calendar';
```

### 5. Run Migration Script

Add calendar tokens to all existing staff members:

```bash
# From project root
dart run scripts/migrate_calendar_tokens.dart
```

This will:
- Find all staff without calendar tokens
- Generate a unique UUID for each
- Update the staff documents in Firestore

### 6. Rebuild and Deploy Flutter App

```bash
# Rebuild the app with the new calendar service URL
flutter clean
flutter pub get
flutter build ios  # or flutter build apk for Android

# Deploy via your usual deployment process
```

### 7. Test the Feature

1. Launch the app and sign in as a staff member
2. Go to the Deliveries screen
3. Tap the calendar icon → "Subscribe to Calendar"
4. Tap "Subscribe Now"
5. iOS Calendar app should open with subscription prompt
6. Tap "Subscribe" to confirm

**Verify it works:**
- Check that the calendar appears in your Calendar app
- Add a new delivery in the app
- Wait ~15-60 minutes (or force calendar refresh in iOS Settings)
- Verify the new delivery appears in the calendar

## Configuration Options

### Change Calendar Refresh Interval

In `functions/src/calendar-feed.ts`, line 104:

```typescript
ttl: 3600, // Refresh every hour (in seconds)
```

Options:
- `3600` = Every hour (recommended)
- `1800` = Every 30 minutes (more frequent updates, more load)
- `7200` = Every 2 hours (less load, slower updates)

### Change Timezone

In `functions/src/calendar-feed.ts`, line 102:

```typescript
timezone: "America/Toronto", // Adjust to your timezone
```

Use standard timezone names like:
- `America/New_York`
- `America/Los_Angeles`
- `Europe/London`
- `Australia/Sydney`

### Customize Event Duration

In `functions/src/calendar-feed.ts`, line 175:

```typescript
end = new Date(start.getTime() + 60 * 60 * 1000); // 1 hour duration
```

Change `60 * 60 * 1000` (1 hour in milliseconds) to your preferred duration.

## Security Considerations

### Calendar Token Security

- Each staff member gets a unique UUID token
- Tokens are unguessable (128-bit random UUIDs)
- Tokens can be regenerated to revoke old URLs
- Only the assigned staff member's deliveries are visible via that token

### Regenerating Tokens

If a calendar URL is compromised:

1. User taps "Advanced options" in subscription dialog
2. Taps "Regenerate link"
3. Old URL is immediately revoked
4. New URL must be re-subscribed in Calendar app

Admins can also regenerate tokens via:
```dart
final repository = FirebaseStaffRepository();
await repository.regenerateCalendarToken(staffId);
```

### Firestore Rules

Cloud Functions authenticate with Firebase Admin SDK (service account), which bypasses Firestore rules. The rules protect client access:

- `calendar_metadata`: Read by authenticated users, write by Cloud Functions only
- `system_metadata`: Read by authenticated users, write by Cloud Functions only

## Monitoring and Maintenance

### View Calendar Access Logs

Check Firebase Console → Functions → Logs for:
- Calendar feed requests
- Staff member accessing calendar
- Any errors or issues

### Monitor Calendar Metadata

In Firestore, check `calendar_metadata` collection:
```
{
  staffId: "abc123",
  token: "...",
  lastAccessed: Timestamp,
  accessCount: 42,
  createdAt: Timestamp
}
```

This tracks:
- When each staff member last accessed their calendar
- How many times the calendar has been accessed
- Helps identify usage patterns and issues

### System Metadata

The `system_metadata/calendar_last_updated` document tracks:
```
{
  lastUpdated: Timestamp,
  deliveryId: "xyz789",
  changeType: "created" | "updated" | "deleted"
}
```

## Troubleshooting

### "Calendar subscription is not yet configured"

**Problem**: The base calendar URL hasn't been updated.

**Solution**: Update `lib/services/calendar_subscription_service.dart` with your actual Cloud Functions URL.

### Calendar not updating

**Problem**: iOS Calendar may cache aggressively.

**Solutions**:
1. Wait longer (iOS typically checks every 15-60 minutes)
2. Force refresh: Settings → Passwords & Accounts → Subscribed Calendars → Tap calendar → Remove & re-subscribe
3. Check that deliveries are actually changing in Firestore
4. Verify Cloud Function logs show recent requests

### "404 Not Found" when accessing calendar URL

**Problem**: Cloud Function not deployed or URL incorrect.

**Solutions**:
1. Verify function is deployed: `firebase functions:list`
2. Check function URL in Firebase Console
3. Test URL directly in browser (should download a .ics file)
4. Verify token exists in staff document

### Staff member sees wrong deliveries

**Problem**: Filtering logic may be incorrect.

**Solutions**:
1. Check staff member's `role` field (admin/manager/staff)
2. Check staff member's `assignedSchoolIds` array
3. Verify deliveries have correct `schoolId` field
4. Check Cloud Function logs for filtering details

### "Permission denied" errors

**Problem**: Firestore rules may be blocking access.

**Solutions**:
1. Verify rules are deployed: `firebase deploy --only firestore:rules`
2. Check that user is authenticated
3. Verify Cloud Functions have admin access (they should by default)

## Testing with Emulators

For local development and testing:

```bash
# Start Firebase emulators
cd functions
npm run serve

# In another terminal, run Flutter app
flutter run
```

Update `calendar_subscription_service.dart` for local testing:
```dart
static const String _baseCalendarUrl = 'http://localhost:5001/bts-delivery-app/us-central1/calendar';
```

**Note**: Emulator URLs use HTTP, not HTTPS. iOS Calendar may not work with HTTP URLs, so you'll need to test the HTTPS URL manually or use a different calendar app for testing.

## Cost Considerations

### Cloud Functions Pricing

- **Free tier**: 2 million invocations/month, 400,000 GB-seconds/month
- **Calendar feed**: ~10-50ms per request, minimal memory usage
- **Estimated cost**: For 100 users checking calendar hourly = ~72,000 requests/month = **FREE**

### Firestore Pricing

- **Reads**: Each calendar request reads 1 staff doc + N delivery docs
- **Writes**: Only on delivery changes (minimal)
- **Estimated cost**: Negligible for most use cases

### Storage

- Calendar tokens: ~36 bytes per staff member
- Calendar metadata: ~200 bytes per staff member
- **Estimated cost**: Negligible (storage is very cheap)

## Maintenance Schedule

### Regular Tasks

- **Weekly**: Check Firebase Console → Functions → Logs for errors
- **Monthly**: Review `calendar_metadata` for unusual access patterns
- **Quarterly**: Verify all active staff members have calendar tokens

### Updates

When updating the calendar feature:

1. Update Cloud Functions code
2. Test with emulators
3. Deploy to production: `firebase deploy --only functions`
4. Update Flutter app if needed
5. Rebuild and redeploy app

**Important**: Users don't need to re-subscribe when you update Cloud Functions. Their existing subscription URLs continue to work.

## Support and Documentation

### User Documentation

Users can find instructions in the app:
- Tap calendar icon → "Subscribe to Calendar"
- Instructions are provided in the dialog

### Admin Documentation

For admins managing staff and calendars:
- Staff members need to be linked to their account first (via PIN)
- Calendar tokens are generated automatically when needed
- Tokens can be regenerated if compromised
- All calendar operations are logged in Firebase

## Future Enhancements

Potential improvements:

1. **Push notifications**: Notify users when calendar updates (requires additional setup)
2. **Custom refresh intervals**: Allow users to choose update frequency
3. **Calendar preferences**: Filter by delivery status, date range, etc.
4. **Analytics**: Track calendar usage and engagement
5. **Multiple calendars**: Separate calendars for different schools or roles

---

**Questions or Issues?**

Check the logs:
```bash
firebase functions:log --only calendar
```

Or contact the development team for assistance.

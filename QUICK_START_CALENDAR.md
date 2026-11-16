# Quick Start: Calendar Subscription Feature

## What Was Built

✅ **Dynamic Calendar Subscription System** that allows staff to subscribe to their delivery schedules via webcal:// URLs with automatic updates.

### Key Features:
- **Auto-updating calendars** - No manual syncing required
- **Role-based filtering** - Admin/Manager/Staff see appropriate deliveries
- **Secure tokens** - Each user gets a unique, unguessable URL
- **Token regeneration** - Revoke compromised URLs
- **Legacy support** - Old manual sync still available

## Next Steps to Deploy

### 1. Deploy Cloud Functions (5 minutes)

```bash
# Deploy functions to Firebase
firebase deploy --only functions

# Note the URL that's displayed, something like:
# https://us-central1-bts-delivery-app.cloudfunctions.net/calendar
```

### 2. Update Calendar Service URL (1 minute)

Open `lib/services/calendar_subscription_service.dart` and replace line 11:

```dart
static const String _baseCalendarUrl = 'https://YOUR-ACTUAL-URL/calendar';
```

With your Cloud Functions URL from step 1.

### 3. Deploy Firestore Rules (1 minute)

```bash
firebase deploy --only firestore:rules
```

### 4. Migrate Existing Staff (2 minutes)

```bash
dart run scripts/migrate_calendar_tokens.dart
```

This adds calendar tokens to all existing staff members.

### 5. Rebuild App (5 minutes)

```bash
flutter clean
flutter pub get
flutter run  # or build for production
```

### 6. Test (2 minutes)

1. Open app → Deliveries screen
2. Tap calendar icon → "Subscribe to Calendar"
3. Tap "Subscribe Now"
4. Confirm subscription in iOS Calendar

## How Users Subscribe

1. Open BTS Delivery App
2. Go to Deliveries screen
3. Tap calendar icon (top right)
4. Select "Subscribe to Calendar"
5. Tap "Subscribe Now"
6. iOS Calendar opens → Tap "Subscribe"
7. Done! Calendar auto-updates

## File Changes Summary

### New Files Created:
- `functions/` - Cloud Functions directory (entire folder)
  - `package.json` - Node dependencies
  - `src/index.ts` - Functions entry point
  - `src/calendar-feed.ts` - Calendar generation logic
  - `src/delivery-trigger.ts` - Firestore trigger
  - `src/types.ts` - TypeScript type definitions
- `lib/services/calendar_subscription_service.dart` - Calendar subscription service
- `lib/repositories/staff_repository.dart` - Staff management repository
- `lib/providers/staff_providers.dart` - Riverpod providers for staff
- `lib/widgets/calendar_subscription_dialog.dart` - Subscription UI
- `scripts/migrate_calendar_tokens.dart` - Migration script
- `CALENDAR_SUBSCRIPTION_SETUP.md` - Detailed setup guide
- `scripts/README.md` - Scripts documentation

### Modified Files:
- `lib/models/staff.dart` - Added `calendarToken` field
- `lib/screens/main/deliveries_screen.dart` - Added subscription menu
- `lib/providers/calendar_sync_providers.dart` - Added subscription provider
- `firestore.rules` - Added rules for calendar metadata
- Generated files (via build_runner):
  - `lib/models/staff.freezed.dart`
  - `lib/models/staff.g.dart`

### Configuration Files:
- `firebase.json` - Already configured for functions
- `.gitignore` - Functions build artifacts ignored

## Architecture Overview

```
┌─────────────────┐
│  Staff Member   │
│  (iPhone/iPad)  │
└────────┬────────┘
         │ Subscribes via webcal://
         │
         ▼
┌─────────────────────────────────────┐
│  Firebase Cloud Function            │
│  GET /calendar/:token.ics           │
│                                     │
│  1. Validate token                  │
│  2. Get staff record                │
│  3. Query deliveries (role-based)   │
│  4. Generate .ics file              │
│  5. Return calendar feed            │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│  Firestore                          │
│                                     │
│  ├─ staff/                          │
│  │  └─ calendarToken (UUID)         │
│  ├─ deliveries/                     │
│  │  └─ [filtered by role/schools]   │
│  └─ calendar_metadata/              │
│     └─ [access tracking]            │
└─────────────────────────────────────┘
```

### Data Flow:

1. **User subscribes** → App generates/retrieves token from Firestore
2. **App opens webcal:// URL** → iOS Calendar subscribes
3. **iOS checks URL periodically** → Calls Cloud Function
4. **Cloud Function** → Validates token, queries deliveries, returns .ics
5. **Admin changes delivery** → Firestore trigger tracks update
6. **Next iOS check** → Gets updated calendar

## Role-Based Filtering

| Role | Sees Deliveries For |
|------|---------------------|
| **Admin** | All schools, all deliveries |
| **Manager** | All schools, all deliveries |
| **Staff** | Only assigned schools (via `assignedSchoolIds`) |

Filtering happens in Cloud Function, not in app or security rules.

## Security Model

- **Unique tokens**: Each staff member has UUID (128-bit random)
- **No authentication required**: Token is the authentication
- **Token regeneration**: Revokes old URL immediately
- **Backend filtering**: Cloud Function enforces role-based access
- **Firestore rules**: Protect metadata from client writes

## Cost Estimate (100 users)

- Calendar checks: ~72,000/month (hourly checks) → **FREE**
- Firestore reads: ~150,000/month → **FREE** (50k free, then minimal cost)
- Cloud Functions compute: ~7 seconds/month → **FREE**
- **Total monthly cost: $0** (well within free tier)

## Monitoring

### Check Function Logs:
```bash
firebase functions:log --only calendar
```

### View in Firebase Console:
- Functions → calendar → Logs
- Firestore → calendar_metadata (access tracking)
- Firestore → system_metadata (last update time)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Not configured" error | Update `calendar_subscription_service.dart` with function URL |
| Calendar not updating | Wait 15-60 mins, or check function logs |
| Wrong deliveries shown | Check staff's `role` and `assignedSchoolIds` |
| 404 on calendar URL | Verify functions deployed, check URL |

## Support

- **Detailed guide**: See `CALENDAR_SUBSCRIPTION_SETUP.md`
- **Function code**: See `functions/src/`
- **Logs**: `firebase functions:log`
- **Issues**: Check Firestore rules, function logs, staff tokens

---

## Quick Commands Reference

```bash
# Deploy everything
firebase deploy

# Deploy only functions
firebase deploy --only functions

# Deploy only rules
firebase deploy --only firestore:rules

# Test locally
cd functions && npm run serve

# View logs
firebase functions:log --only calendar

# Rebuild app
flutter clean && flutter pub get && flutter run
```

## What's Different from Manual Sync

| Feature | Manual Sync | Subscription |
|---------|-------------|--------------|
| **Updates** | Manual button press | Automatic (hourly) |
| **Permissions** | Requires calendar permission | No permissions needed |
| **Setup** | Every device | Once per user |
| **Cross-platform** | iOS only | iOS, macOS, Android |
| **Backend** | None | Cloud Functions |
| **Security** | Device local | Secure tokens |

---

🎉 **Ready to deploy!** Follow the 6 steps above to get started.

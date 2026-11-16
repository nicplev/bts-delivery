# BTS Delivery App Scripts

This directory contains utility scripts for managing the BTS Delivery App.

## Migration Scripts

### migrate_calendar_tokens.dart

Adds calendar subscription tokens to all existing staff members who don't have one.

**Usage:**
```bash
# From project root directory
dart run scripts/migrate_calendar_tokens.dart
```

**What it does:**
1. Connects to your Firebase/Firestore instance
2. Finds all staff members without a `calendarToken` field
3. Generates a unique UUID for each staff member
4. Updates the staff documents in Firestore

**Prerequisites:**
- Firebase must be properly configured in your project
- You must have admin access to the Firestore database
- The `uuid` package must be in your `pubspec.yaml` dependencies

**When to run:**
- After implementing the calendar subscription feature
- Before users start subscribing to calendars
- Anytime you add new staff members (though they should get tokens automatically)

## Cloud Functions

The `/functions` directory contains Firebase Cloud Functions that power the calendar subscription feature.

### Deploying Functions

```bash
# Install dependencies
cd functions
npm install

# Deploy all functions
npm run deploy

# Deploy specific function
firebase deploy --only functions:calendar
firebase deploy --only functions:onDeliveryChanged
```

### Testing Functions Locally

```bash
# Start Firebase emulators
cd functions
npm run serve

# In another terminal, run the Flutter app against emulators
flutter run
```

### Function URLs

After deployment, note the URLs for your functions:
- Calendar feed: `https://[region]-[project-id].cloudfunctions.net/calendar/:token.ics`

Update these URLs in:
- `lib/services/calendar_subscription_service.dart` (line 11)

## Troubleshooting

### Migration script fails to connect to Firebase

Make sure your Firebase configuration is correct. The script uses the default Firebase configuration from your Flutter app.

### "Permission denied" errors

Ensure you're running the script with appropriate Firestore permissions. You may need to:
1. Use Firebase emulators for testing
2. Ensure your service account has the right permissions
3. Check your Firestore security rules

### Cloud Functions deployment fails

1. Ensure you have the Firebase CLI installed: `npm install -g firebase-tools`
2. Login to Firebase: `firebase login`
3. Select your project: `firebase use [project-id]`
4. Check that Node.js version matches (use Node 18)

# Offline Mode Enhancement Guide

## Overview

The BTS Delivery App now features comprehensive offline mode support, allowing delivery drivers to complete their work even without internet connectivity. All data is automatically queued and synced when connection is restored.

## Features

### 1. **Full Offline Delivery Completion**
- Complete deliveries without internet connection
- Capture signatures offline
- Take photos offline
- Add notes and completion details
- All data stored securely on device

### 2. **Intelligent Sync Queue**
- Automatic background synchronization
- Manual sync trigger available
- Retry logic for failed uploads
- WiFi-only sync option (configurable)
- Priority-based queue processing

### 3. **Visual Status Indicators**
- **Offline Mode Banner**: Shows when device is offline with pending item count
- **Syncing Banner**: Displays progress during active sync
- **Sync Complete**: Silent success (no banner)
- **Partial Sync**: Warning for items that failed
- **Waiting for WiFi**: Shown when WiFi-only mode is enabled

### 4. **Detailed Sync Status**
- Tap the offline/sync banner to view details
- See pending delivery completions
- View storage usage
- Monitor sync progress
- Manual sync trigger

## How It Works

### For Delivery Drivers

#### Completing a Delivery Offline

1. **Navigate to delivery** (works offline with cached data)
2. **Capture signature** - Saved locally to device storage
3. **Take photos** - Compressed and stored on device
4. **Add notes** - Stored with delivery completion
5. **Submit** - Queued for upload when online

#### Monitoring Sync Status

- **Blue banner**: "Offline Mode • X pending" - You have pending items
- **Tap banner**: View detailed sync status
- **Green checkmark**: Item successfully synced
- **Yellow warning**: Some items need retry
- **Red error**: Sync failed (will retry automatically)

#### Manual Sync

1. Tap the offline mode banner
2. View pending items in detail sheet
3. Tap "Sync Now" button
4. Monitor progress in real-time

### Data Storage

#### Local Storage Structure

```
/pending_uploads/
  ├── signature_[deliveryId]_[timestamp].png
  ├── photo_[deliveryId]_0_[timestamp].jpg
  ├── photo_[deliveryId]_1_[timestamp].jpg
  └── ...
```

#### Hive Boxes

- `pending_delivery_completions`: Delivery completion metadata
- `local_photos`: Photo upload queue
- `sync_queue`: General sync operations
- `app_settings`: User preferences

### Sync Process

1. **Queue Creation**
   - User completes action offline
   - Data saved to Hive database
   - Files saved to local storage
   - Queued for sync

2. **Connectivity Detection**
   - App monitors connectivity status
   - Detects when device comes online
   - Checks WiFi-only preference

3. **Auto Sync**
   - Triggers automatically when online
   - Processes queue in priority order
   - Uploads signatures first
   - Then photos (compressed)
   - Finally metadata

4. **Error Handling**
   - Failed items marked for retry
   - Max 3 retry attempts
   - Exponential backoff
   - User notified of persistent failures

## Configuration

### App Settings (Configurable in Profile)

```dart
AppSettings {
  autoSync: true,              // Auto-sync when online
  wifiOnlySync: true,          // Only sync on WiFi
  syncInterval: 15,            // Minutes between sync attempts
  compressImages: true,        // Compress photos before upload
  imageQuality: 80,            // JPEG quality (0-100)
  offlineModeEnabled: true,    // Allow offline usage
  maxRetries: 3,               // Max sync retry attempts
}
```

### Customization

To change sync behavior, update `AppSettings` in Hive:

```dart
final settings = await offlineStorage.getAppSettings();
final updated = settings.copyWith(
  wifiOnlySync: false,  // Sync on any connection
  syncInterval: 5,      // Sync every 5 minutes
);
await offlineStorage.updateAppSettings(updated);
```

## API Reference

### OfflineDeliveryService

```dart
// Save delivery completion offline
final completionId = await offlineDeliveryService.saveDeliveryCompletion(
  deliveryId: 'delivery_123',
  schoolId: 'school_456',
  completedBy: 'user_789',
  signatureFile: signatureFile,
  photoFiles: [photo1, photo2],
  notes: 'Delivery completed successfully',
  signedBy: 'John Smith',
);

// Get pending completions
final pending = await offlineDeliveryService.getPendingCompletions();

// Check if delivery has pending completion
final hasPending = await offlineDeliveryService.hasPendingCompletion('delivery_123');

// Get storage size
final bytes = await offlineDeliveryService.getPendingStorageSize();
final formatted = offlineDeliveryService.formatStorageSize(bytes);

// Mark as uploaded (called by sync manager)
await offlineDeliveryService.markAsUploaded(completionId);

// Clear uploaded completions (cleanup)
await offlineDeliveryService.clearUploadedCompletions();
```

### Providers

```dart
// Watch offline delivery service
final service = ref.watch(offlineDeliveryServiceProvider);

// Watch pending completions (stream)
final completionsAsync = ref.watch(pendingDeliveryCompletionsProvider);

// Watch pending count
final countAsync = ref.watch(pendingDeliveryCountProvider);

// Watch storage size
final sizeAsync = ref.watch(pendingStorageSizeProvider);

// Check specific delivery
final hasPendingAsync = ref.watch(
  hasPendingCompletionProvider('delivery_123')
);
```

## UI Components

### ConnectivityIndicator

Shows at top of screens to indicate offline/sync status.

```dart
Column(
  children: [
    const ConnectivityIndicator(),
    Expanded(child: YourContent()),
  ],
)
```

### SyncStatusDetailSheet

Modal bottom sheet with detailed sync information.

```dart
// Show programmatically
SyncStatusDetailSheet.show(context);

// Or tap the ConnectivityIndicator banner
```

## Testing Offline Mode

### Enable Airplane Mode

1. Turn on Airplane Mode on your test device
2. Complete a delivery with signature and photos
3. Verify data saved locally
4. Turn off Airplane Mode
5. Observe automatic sync

### Simulate Poor Connection

1. Use network throttling tools
2. Complete deliveries
3. Verify retry logic works
4. Check error handling

### Test WiFi-Only Mode

1. Enable WiFi-only sync in settings
2. Complete delivery on cellular
3. Verify "Waiting for WiFi" banner
4. Connect to WiFi
5. Verify automatic sync

## Performance Optimization

### Image Compression

- Photos compressed before storage
- JPEG quality: 80 (configurable)
- Max dimensions: 1600x1600
- Typical size: 100-300KB per photo

### Storage Management

- Auto-cleanup of uploaded files
- Periodic storage size monitoring
- User alerts if storage exceeds threshold
- Manual cleanup option available

### Battery Optimization

- Sync only when device charging (optional)
- Reduced sync frequency on low battery
- Background sync suspension configurable

## Troubleshooting

### Items Not Syncing

1. **Check connectivity**: Verify device is online
2. **Check WiFi setting**: Disable WiFi-only if on cellular
3. **View sync status**: Tap banner to see errors
4. **Manual sync**: Try triggering sync manually
5. **Check storage**: Ensure device has available space

### Photos Not Uploading

1. **Verify file exists**: Check local storage path
2. **Check permissions**: Ensure storage permissions granted
3. **Check file size**: Very large photos may timeout
4. **Retry**: Failed uploads retry automatically

### Sync Stuck

1. **Kill and restart app**: Force close and reopen
2. **Clear sync queue**: Use settings to clear failed items
3. **Check Firebase**: Verify Firebase connection
4. **Contact support**: Persistent issues may need investigation

## Best Practices

### For Developers

1. **Always queue offline operations** - Never assume connectivity
2. **Provide visual feedback** - Show pending status clearly
3. **Handle errors gracefully** - Don't lose user data
4. **Test offline scenarios** - Simulate various network conditions
5. **Monitor storage usage** - Alert users before running out

### For Users

1. **Sync regularly** - Trigger manual sync when on WiFi
2. **Monitor pending items** - Check sync status periodically
3. **Free up storage** - Clear uploaded items when safe
4. **Report issues** - Contact support if sync fails repeatedly

## Future Enhancements

- [ ] Offline delivery route optimization
- [ ] Offline map caching
- [ ] Voice notes support
- [ ] Delivery completion templates
- [ ] Batch photo upload
- [ ] Offline analytics dashboard
- [ ] Push notification for sync completion
- [ ] Conflict resolution for concurrent edits

## Support

For issues or questions:
- Email: support@btsdelivery.com
- GitHub: [Issue Tracker](https://github.com/your-repo/issues)
- Docs: [Full Documentation](https://docs.btsdelivery.com)

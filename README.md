# BTS Delivery App

A comprehensive Flutter mobile application for Back-to-School (BTS) delivery operations, enabling delivery staff and managers to record proof of delivery, organize photos by classroom/year level/school, capture school-wide consumables, and obtain digital school sign-offs.

## Features

### Core Functionality
- **Offline-First Architecture**: Works offline with Firebase sync when connected
- **Multi-user Support**: Concurrent staff access with role-based permissions
- **Proof of Delivery**: Photo capture and classroom organization
- **Digital Sign-offs**: Typed name + drawn signature capture
- **Consumables Tracking**: School-wide supplies and materials

### User Roles
- **Staff Members**: Can view and manage assigned deliveries
- **Managers**: Full access to all deliveries and staff management

### Key Screens
- **Authentication**: Email/password login with staff profile linking
- **Deliveries**: Today/Upcoming/Past delivery views with filtering
- **School Hub**: Segmented control with Records/Sign-Off/Info tabs
- **Records Management**: Year levels, classrooms, photos, and pack totals
- **Sign-off Workflow**: Overview breakdown + signature capture

## Tech Stack

### Flutter & Dart
- **Flutter**: Cross-platform mobile development (iOS/Android)
- **Dart**: Null-safety enabled language
- **Material Design 3**: Modern UI components and theming

### State Management & Navigation
- **Riverpod**: Reactive state management with providers
- **go_router**: Declarative routing with deep linking support

### Backend & Database
- **Firebase Auth**: Authentication with email/password
- **Cloud Firestore**: NoSQL database with offline persistence
- **Firebase Storage**: File storage for photos and signatures
- **Firebase Emulator Suite**: Local development environment

### Data Modeling
- **freezed**: Immutable data classes with code generation
- **json_serializable**: JSON serialization support
- **Timestamp Conversion**: Firebase Timestamp to DateTime mapping

### Image Handling
- **image_picker**: Multi-image selection from gallery/camera
- **flutter_image_compress**: Size optimization (max 1600px, 85% JPEG)
- **signature**: Digital signature capture to PNG
- **permission_handler**: Camera and storage permissions

### Utilities
- **intl**: Date/time formatting with timezone support
- **flutter_dotenv**: Environment variable management

## Project Structure

```
lib/
├── app/                    # App root configuration
│   ├── router/            # go_router setup
│   ├── shell/             # Bottom navigation shell
│   └── theme/             # Material theme configuration
├── core/                  # Core utilities and configuration
│   ├── config/            # Firebase configuration
│   ├── env/               # Environment variables
│   ├── providers/         # Riverpod providers
│   ├── services/          # Image compression service
│   └── utils/             # Date utilities and result types
├── data/                  # Data layer
│   ├── models/            # Freezed data models
│   └── repositories/      # Repository interfaces and implementations
├── features/              # Feature modules
│   ├── auth/              # Authentication screens
│   ├── deliveries/        # Delivery management
│   ├── schools/           # School listing
│   └── school_hub/        # School detail tabs (Records/Sign-off/Info)
└── widgets/               # Reusable UI components
```

## Data Models

### Core Entities
- **Staff**: User profiles with manager access flags
- **School**: Basic school information and address
- **Delivery**: School assignments with date/time and staff
- **YearLevel**: Organizational structure (Prep, Year 1, etc.)
- **Classroom**: Individual learning spaces within year levels
- **Photo**: Proof of delivery images with storage paths
- **PackTotal**: Classroom delivery quantities
- **Consumable**: School-wide supplies (tissues, paper, etc.)
- **SignOff**: Digital signatures with typed names
- **Contact**: School personnel information
- **MapAsset**: Floor plans and location documents
- **Note**: General school-specific notes

## Firebase Configuration

### Firestore Collections Structure
```
/staff/{staffId}                                    # Staff profiles
/schools/{schoolId}                                 # School information
/schools/{schoolId}/yearLevels/{yearLevelId}        # Year levels
/schools/{schoolId}/yearLevels/{yearLevelId}/classrooms/{classroomId}  # Classrooms
/schools/{schoolId}/consumables/{consumableId}      # School supplies
/schools/{schoolId}/meta/signoff                    # Single sign-off doc
/deliveries/{deliveryId}                           # Delivery assignments
```

### Security Rules
- **Authentication Required**: All operations require valid Firebase Auth
- **Role-Based Access**: Managers can view all data, staff see assigned deliveries
- **School Assignment**: Staff can only modify schools with current deliveries
- **Sign-off Permissions**: Only assigned staff or managers can sign off

### Indexes
- Deliveries by date (ascending/descending)
- Deliveries by staff assignment + date
- Photos by upload timestamp
- Pack totals by creation date

## Getting Started

### Prerequisites
- Flutter SDK (>=3.10.0)
- Dart SDK (>=3.0.0)
- Firebase CLI
- iOS Simulator / Android Emulator
- Xcode (for iOS development)
- Android Studio (for Android development)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/nicplev/bts-delivery.git
   cd bts-delivery
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate code**
   ```bash
   flutter packages pub run build_runner build
   ```

4. **Set up Firebase**
   ```bash
   # Create a local environment file and fill in your Firebase project details
   cp .env.example .env
   # Generate options for the platforms you are developing for
   flutterfire configure --out=lib/firebase_options.dart
   ```

   For iOS, place the Firebase configuration for your iOS app at
   `ios/Runner/GoogleService-Info.plist` if FlutterFire did not create it there.
   Keep these generated Firebase files and `.env` local.

5. **Start Firebase Emulators (Development)**
   ```bash
   firebase emulators:start
   ```

6. **Run the app**
   ```bash
   flutter run
   ```

### Environment Configuration

Create a `.env` file with your Firebase configuration:

```env
FIREBASE_API_KEY=your_api_key_here
FIREBASE_APP_ID=your_app_id_here
FIREBASE_MESSAGING_SENDER_ID=your_sender_id_here
FIREBASE_PROJECT_ID=your_project_id_here
FIREBASE_STORAGE_BUCKET=your_storage_bucket_here

# Emulator settings (for local development)
USE_FIREBASE_EMULATOR=true
FIRESTORE_EMULATOR_HOST=localhost:8080
FIREBASE_AUTH_EMULATOR_HOST=localhost:9099
FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199
```

## Development Workflow

### Code Generation
Run this command when modifying data models:
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### Firebase Emulators
For local development with offline capabilities:
```bash
# Start all emulators
firebase emulators:start

# Access Emulator UI
open http://localhost:4000
```

### Testing
```bash
# Run unit tests
flutter test

# Run integration tests
flutter drive --target=test_driver/app.dart
```

## Key Implementation Details

### Offline-First Design
- Firestore persistence enabled with unlimited cache
- Local data mutations sync when connection restored
- UI remains responsive during network outages

### Image Optimization
- Automatic compression to max 1600px, 85% quality
- EXIF metadata removal for privacy
- Efficient storage with Firebase Storage

### Role-Based Security
- Firebase Security Rules enforce manager vs. staff permissions
- Client-side filtering with server-side validation
- Staff profile linking prevents unauthorized access

### State Management
- Riverpod providers for reactive UI updates
- Stream providers for real-time Firestore sync
- AsyncValue handling for loading/error states

### Navigation Architecture
- go_router with type-safe route definitions
- Shell routing for persistent bottom navigation
- Deep linking support for direct school/delivery access

## Production Deployment

### iOS App Store
1. Update `ios/Runner/Info.plist` with app metadata
2. Configure Firebase for production environment
3. Build and archive with Xcode
4. Submit through App Store Connect

### Google Play Store
1. Update `android/app/src/main/AndroidManifest.xml`
2. Configure Firebase for production environment
3. Build signed APK/AAB
4. Upload through Google Play Console

### Firebase Production Setup
1. Create production Firebase project
2. Deploy Firestore rules and indexes
3. Configure Firebase Storage rules
4. Update `.env` with production configuration

## Support & Maintenance

### Monitoring
- Firebase Analytics for app usage tracking
- Firebase Crashlytics for error reporting
- Performance monitoring enabled

### Updates
- Semantic versioning in `pubspec.yaml`
- Database migration strategy for schema changes
- Backward compatibility considerations

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Follow the existing code style and patterns
4. Add tests for new functionality
5. Submit a pull request with detailed description

For major changes, please open an issue first to discuss the proposed changes.

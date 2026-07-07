# App Library Ledger

A simple, offline-first Flutter app for cataloging all your apps by purpose and spotting duplicate categories.

## Features

✅ **App Management**
- Add apps with name, App Store link, and custom notes
- Delete apps from your library
- Search apps instantly

✅ **Smart Categorization**
- 10 pre-built categories (Productivity, Notes, Finance, Health, Media, Utilities, Social, Education, Shopping, Travel)
- Create custom categories anytime
- See at-a-glance count of apps per category
- Spot duplicate categories easily

✅ **Privacy First**
- 100% offline — no accounts, no syncing to servers
- All data stored locally on your device
- No ads, no tracking

✅ **iOS + Android**
- Universal Flutter app
- Works on iPhone and iPad with adaptive UI

## Getting Started

### Prerequisites
- Flutter SDK 3.9.2+
- iOS 11.0+ or Android 5.0+

### Installation

1. Clone the repo:
```bash
git clone <repo-url>
cd app_library_ledger
```

2. Get dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
# iOS
flutter run

# Android
flutter run -d android

# Windows (for testing)
flutter run -d windows
```

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── models/
│   ├── app_model.dart          # AppEntry data model
│   └── category_model.dart     # Category data model
├── screens/
│   ├── library_screen.dart     # Main app list + filtering
│   ├── add_app_screen.dart     # Add/edit app form
│   └── categories_screen.dart  # Manage categories
└── services/
    └── storage_service.dart    # Local storage (SharedPreferences)
```

## Key Dependencies

- **shared_preferences** — Local data persistence
- **uuid** — Unique IDs for apps
- **provider** — State management (optional, included for Phase 2)
- **url_launcher** — Open App Store links (Phase 2)

## MVP Features (Completed)

✅ Add apps with name, link, category, notes  
✅ List all apps with search  
✅ Filter by category  
✅ Duplicate counter per category  
✅ Offline storage  
✅ Delete apps with confirmation  
✅ Custom categories  
✅ No account required  

## Phase 2 (Planned)

- iCloud Sync (sync app list across your devices)
- Open App Store links directly
- App icons fetching
- Subscription cost tracking
- Monthly summary reports

## Building for Release

### iOS (TestFlight)

```bash
# Archive
flutter build ios --release

# Upload to TestFlight via Xcode
open ios/Runner.xcworkspace
```

### Android (Play Store)

```bash
# Build signed APK
flutter build apk --release --split-per-abi

# Or build AAB
flutter build appbundle --release
```

## Privacy

App Library Ledger stores all data locally on your device using `shared_preferences`. No data is sent to servers, no analytics, no ads.

## License

MIT

## Author

Built as a brainstorming and prototyping project.


- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

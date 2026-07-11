# Contributing

## Requirements

- Flutter 3.38.4 or later
- Dart 3.12.2 or later

## Local checks

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Do not commit API keys, `android/key.properties`, JKS files, or user backups.
Changes to stored data must remain compatible with existing versions. Keep each
pull request focused on one purpose.

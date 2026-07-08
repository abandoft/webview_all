# platform_example

Comprehensive example app for the local `webview_all` workspace packages.

## Run

```sh
flutter pub get
flutter run -d macos
flutter run -d linux
flutter run -d windows
flutter run -d chrome
```

The app depends on the local platform packages through `dependency_overrides`
in `pubspec.yaml`, so it exercises the code in this repository instead of the
published packages.

## Linux

Install the WebKitGTK 4.1 development/runtime package for your distribution
before running the Linux target.

The Linux runner wraps `FlView` in a `GtkOverlay`. Keep that structure if you
copy this example into another app; the Linux implementation positions the
native WebKitGTK view as an overlay above Flutter.

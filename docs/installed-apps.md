# Installed apps

This plugin supports “installed apps” differently per platform:

- **Android**: you can enumerate installed packages and metadata.
- **iOS**: Apple does not allow enumerating installed apps; the user must select apps via the native picker, which returns opaque tokens.

## Android: enumerate installed apps

```dart
final installed = InstalledAppsManager();

final apps = await installed.getAndroidInstalledApps(
  includeSystemApps: false,
  includeIcons: true,
);
```

Each entry is an `AndroidAppInfo`:
- `packageId` (wrap with `AppIdentifier.android(packageId)` for restrictions)
- `name`
- `icon` (PNG bytes, optional)
- `category` (optional)
- `isSystemApp`

### Get info for a specific package

```dart
final installed = InstalledAppsManager();
final app = await installed.getAndroidAppInfo(
  AppIdentifier.android('com.whatsapp'),
);
```

## iOS: show the Family Activity Picker

### Why tokens exist

iOS returns an opaque `ApplicationToken` representing the selected app. You cannot decode it, and you cannot get the app name/icon in Dart.

Persist the token string yourself if you need to:
- re-open the picker with a previous selection
- re-apply restrictions on later app launches

When applying restrictions, wrap token strings with `AppIdentifier.ios(token)`.

### Show picker

```dart
final installed = InstalledAppsManager();
final picked = await installed.selectIOSApps();
```

### Re-open picker with a previous selection

```dart
final installed = InstalledAppsManager();

final previouslyPicked = <IOSAppInfo>[
  const IOSAppInfo(
    applicationToken: AppIdentifier.ios('...'),
  ),
];

final picked = await installed.selectIOSApps(preSelectedApps: previouslyPicked);
```

## Next

- [Docs index](README.md)
- [Restrict / block apps](restrict-apps.md)
- [iOS setup](ios-setup.md)
- [Troubleshooting](troubleshooting.md)

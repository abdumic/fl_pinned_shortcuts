## 0.1.4

- Prefer disk-cached network images before attempting a network download.
- Make shortcut image resolution work better when creating shortcuts offline.
- Add `isImageCached()` for cache-only checks.
- Add `cacheNetworkImage()` for proactively preparing network images for offline use.

## 0.1.3

- Gracefully no-op on unsupported platforms such as Web, Windows, macOS, and Linux.
- Prevent `MissingPluginException` from crashing application startup.
- Shortcut click stream is empty on unsupported platforms.
- Shortcut creation, update, pin checks, enable/disable, removal, and disposal return safe defaults when Android is unavailable.

## 0.1.2

- Fix shortcut icons appearing too small on Android launchers by generating adaptive bitmap icons.
- Add optional adaptive foreground and background layers.
- Add color or image adaptive backgrounds.
- Add configurable `adaptiveIconForegroundScale`.
- Keep network icon layers on `DefaultCacheManager`.

## 0.1.1

- Migrate Android Gradle configuration for modern Flutter/AGP 9 builds.
- Use Flutter's built-in Kotlin compatibility.
- Improve ActivityAware lifecycle handling.

## 0.1.0

- Initial Android pinned-shortcut implementation.

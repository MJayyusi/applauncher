# App Launcher

An Android launcher app that allows users to select and auto-launch a specific app on startup. Designed for Android devices including TVs with full remote control support.

## Features

- **App Listing**: Lists all installed apps on the device
- **App Selection**: Allows users to select one app from the installed apps
- **Auto-Launch**: Automatically launches the selected app when the launcher starts
- **TV Support**: Full support for Android TV remote controls
- **Persistent Selection**: Remembers the user's choice between sessions

## How to Use

1. **First Launch**: When you first open the app, you'll see a list of all installed apps
2. **Select an App**: Use the arrow keys (or remote control) to navigate and press Enter/Select to choose an app
3. **Auto-Launch**: The next time you open the launcher, it will automatically launch your selected app
4. **Change Selection**: If you want to change your selection, press Escape to go back to the app selection screen

## TV Remote Controls

- **Arrow Keys**: Navigate up/down through the app list
- **Enter/Select**: Select the highlighted app
- **Escape**: Go back to app selection (if you have a selected app)

## Installation

1. Build the app: `flutter build apk`
2. Install on your Android device: `flutter install`
3. Set as default launcher in Android settings

## Requirements

- Android 5.0+ (API level 21+)
- Android TV support for TV devices
- `QUERY_ALL_PACKAGES` permission for app listing

## Technical Details

- Built with Flutter
- Uses `installed_apps` package for app listing
- Uses `shared_preferences` for storing user selection
- Uses `url_launcher` for launching selected apps
- Configured as Android launcher with proper intent filters
# SmartFetchBot — Mobile Controller App

Flutter app to control the SmartFetchBot robot from your phone.

## Requirements

- Flutter SDK 3.11.0 or higher → https://flutter.dev/get-started
- Android phone (USB debugging enabled) or Android emulator
- The SmartFetchBot backend running on a laptop on the same WiFi network

## Setup

### 1. Install dependencies
```bash
flutter pub get
```

### 2. Connect your phone
- Enable **Developer Options** on your Android phone
- Enable **USB Debugging**
- Connect via USB cable

### 3. Run the app
```bash
flutter run
```

### 4. Set the backend IP
- Tap the **⚙️ settings icon** in the top right of the app
- Enter your laptop's WiFi IP address (e.g. `192.168.1.45`)
- Tap **Save & Test Connection**

> **How to find your laptop's IP:**
> - Windows: open Command Prompt → `ipconfig` → look for `Wireless LAN adapter Wi-Fi → IPv4 Address`
> - Mac/Linux: open Terminal → `ifconfig | grep "inet "`

### 5. Make sure phone and laptop are on the same WiFi
The app communicates with the backend over your local WiFi network.

---

## Build a release APK (install without USB cable)

```bash
flutter build apk --release
```

The APK will be at:
```
build/app/outputs/flutter-apk/app-release.apk
```

Send it to your phone via WhatsApp, Google Drive, or email, then install it.
Android will ask to **allow installation from unknown sources** — tap Allow.

---

## Features

- 📷 Live camera feed with YOLO bounding boxes
- 👆 Tap video to select a target object
- 🕹️ Joystick for manual driving
- 🤖 Fetch button to send robot to target (autonomous mode)
- 🛑 Stop button in both manual and autonomous mode
- ⚙️ Settings screen to change backend IP without rebuilding

---

## Project structure

```
lib/
  main.dart              ← main app + joystick + controls
  settings_screen.dart   ← IP configuration screen
  services/
    api_service.dart     ← all HTTP calls to the backend
```
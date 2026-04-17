<div align="center">

# CyberDeck-Mobile

![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?logo=dart)
![Platform](https://img.shields.io/badge/Platform-Android-lightgrey)
![License](https://img.shields.io/badge/license-GNU%20GPLv3-green)

**Official mobile client for the CyberDeck remote control system**

[CyberDeck Server](https://github.com/Overl1te/CyberDeck) •
[README (Русский)](README.md)

</div>

---

## ✨ Features

### 🎯 Core capabilities

- **🖱️ Native touchpad** — control cursor via phone's touch sensor with minimal latency (Raw Touch Events).
- **⌨️ Virtual keyboard** — pull-up panel with text input and special keys (`Win`, `Alt+Tab`, `Copy`, `Paste`).
- **📺 Video stream** — real-time PC screen viewing (MJPEG / H.264 / H.265 with adaptive fallback).
- **👆 Multi-touch gestures** — two-finger scroll, Drag & Drop, right/left click.
- **📁 File transfer** — upload to PC and download from PC with SHA-256 verification.
- **🔍 QR pairing** — quick connection via QR code or manual IP/port/PIN entry.
- **🎨 Cyberpunk UI** — Glassmorphism-style interface with neon accents.

### 🛠️ Technical highlights

- **⚡ Flutter** — native performance, smooth animations.
- **🔄 Smart scroll** — pixel accumulation algorithm for smooth scrolling (like Precision Touchpad).
- **🔒 Security** — tokens stored in `flutter_secure_storage`, file checksums.
- **📱 Fullscreen** — Immersive Sticky mode for maximum immersion.

---

## 🚀 Installation & Build

### Prerequisites

- **Flutter SDK** 3.0+
- **Android Studio** / **VS Code**
- Android device or emulator

### Setup

```bash
git clone https://github.com/Overl1te/CyberDeck-Mobile.git
cd CyberDeck-Mobile
flutter pub get
```

### Run (debug)

```bash
flutter run
```

### Build APK (Release)

```bash
flutter build apk --release
# or split by ABI:
flutter build apk --split-per-abi
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## 🎮 Usage

### Connecting

1. Start the **CyberDeck** server on your PC.
2. Open the app on your phone.
3. Scan the QR code from the launcher screen, or enter **IP:PORT** and **PIN** manually.
4. Tap **CONNECT**.

### 🖱️ Gestures

| Gesture | Action |
|---|---|
| 1 finger move | Cursor move |
| 1 finger tap | Left click |
| 2 fingers move | Smooth scroll |
| 2 fingers tap | Right click |
| Double-tap + hold | Drag & Drop |

### 🎛️ UI elements

- **⏻** — shut down PC.
- **↻** — rotate stream by 90°.
- **KEYBOARD** — open keyboard and special keys panel.
- **Side Bar** — volume control (+ / − / Mute).

---

## 🔧 Project structure

```
lib/
├── main.dart                          # Entry point, deep links, MaterialApp
├── home_screen.dart                   # Main screen with device list
├── connect_screen.dart                # Connection screen (IP/PIN/QR)
├── dashboard_screen.dart              # Device control panel
├── control_screen.dart                # Control screen (touchpad, stream, gestures)
├── settings_screen.dart               # App settings
├── device_settings_screen.dart        # Per-device settings
├── diagnostics_screen.dart            # Connection diagnostics
├── help_screen.dart                   # Help screen
├── qr_scan_screen.dart                # QR scanner
├── qr_payload_parser.dart             # QR payload parser
├── device_storage.dart                # Connected device storage
├── mjpeg_view.dart                    # MJPEG widget with buffer optimisation
├── ts_stream_view.dart                # MPEG-TS (H.264/H.265) widget
├── audio_relay_view.dart              # Audio stream widget
├── file_transfer.dart                 # File transfer UI
├── services_discovery.dart            # Server discovery on the network
├── theme.dart                         # App theme
├── app_version.dart                   # App version
│
├── network/                           # Network layer
│   ├── api_client.dart                # HTTP client with retry logic
│   ├── host_port.dart                 # host:port parser
│   ├── protocol_service.dart          # Protocol version negotiation
│   └── reconnecting_ws_client.dart    # WebSocket with auto-reconnect
│
├── services/                          # Business logic
│   ├── pairing_service.dart           # Pairing (PIN/QR)
│   ├── transfer_service.dart          # File upload/download + SHA-256
│   ├── update_check_service.dart      # Update check via GitHub API
│   └── system_notifications.dart      # Local notifications
│
├── control/controllers/               # Real-time controllers
│   └── control_connection_controller  # WebSocket heartbeat, ACK, RTT
│
├── stream/                            # Video streaming
│   ├── stream_offer_parser.dart       # Server offer JSON parser
│   └── adaptive_stream_controller.dart # Adaptive candidate selection
│
├── security/                          # Security
├── errors/                            # Error catalogue
├── l10n/                              # Localisation
└── widgets/                           # Reusable widgets
```

---

## 🧪 Contract snapshots

To verify protocol compatibility with the CyberDeck server:

```powershell
./tool/sync_server_contract_snapshots.ps1
flutter test test/server_contract_snapshot_test.dart
```

Check-only mode (CI):

```powershell
./tool/sync_server_contract_snapshots.ps1 -Check
```

---

## 🐛 FAQ

| Issue | Solution |
|---|---|
| **Connection Failed** | 1. Phone and PC on the same Wi-Fi network. 2. Server is running. 3. Check Windows Firewall. |
| **Black screen** | Tap ↻ or restart the stream. |
| **Scroll too fast** | Adjust `scrollFactor` in app settings. |

---

## 🤝 Contributing

1. Fork the repository.
2. Create a branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes.
4. Open a Pull Request.

---

**📄 License:** GNU GPL v3

**🌟 Part of the [CyberDeck](https://github.com/Overl1te/CyberDeck) ecosystem**

<div align="center"><p>Made with ❤️ and Flutter</p></div>

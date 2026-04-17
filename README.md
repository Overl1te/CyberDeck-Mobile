<div align="center">

# CyberDeck-Mobile

![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?logo=dart)
![Platform](https://img.shields.io/badge/Platform-Android-lightgrey)
![License](https://img.shields.io/badge/license-GNU%20GPLv3-green)

**Официальный мобильный клиент для системы удалённого управления CyberDeck**

[Серверная часть CyberDeck](https://github.com/Overl1te/CyberDeck) •
[README (English)](README_EN.md)

</div>

---

## ✨ Особенности

### 🎯 Основные возможности

- **🖱️ Нативный тачпад** — управление курсором через сенсор телефона с минимальной задержкой (Raw Touch Events).
- **⌨️ Виртуальная клавиатура** — выдвижная панель с поддержкой текстового ввода и специальных клавиш (`Win`, `Alt+Tab`, `Copy`, `Paste`).
- **📺 Видеопоток** — просмотр экрана ПК в реальном времени (MJPEG / H.264 / H.265 с adaptive fallback).
- **👆 Мультитач-жесты** — скролл двумя пальцами, Drag & Drop, правый/левый клик.
- **📁 Передача файлов** — загрузка файлов на ПК и скачивание с ПК с проверкой SHA-256.
- **🔍 QR-сопряжение** — быстрое подключение через QR-код или ввод IP/порт/PIN.
- **🎨 Cyberpunk UI** — интерфейс в стиле Glassmorphism с неоновыми акцентами.

### 🛠️ Технические преимущества

- **⚡ Flutter** — нативная производительность, плавные анимации.
- **🔄 Умный скролл** — алгоритм накопления пикселей для плавного скроллинга (как Precision Touchpad).
- **🔒 Безопасность** — токены хранятся в `flutter_secure_storage`, контрольные суммы файлов.
- **📱 Полный экран** — Immersive Sticky режим для максимального погружения.

---

## 🚀 Установка и сборка

### Предварительные требования

- **Flutter SDK** 3.0+
- **Android Studio** / **VS Code**
- Устройство Android или эмулятор

### Установка

```bash
git clone https://github.com/Overl1te/CyberDeck-Mobile.git
cd CyberDeck-Mobile
flutter pub get
```

### Запуск (отладка)

```bash
flutter run
```

### Сборка APK (Release)

```bash
flutter build apk --release
# или раздельно по ABI:
flutter build apk --split-per-abi
```

Результат: `build/app/outputs/flutter-apk/app-release.apk`

---

## 🎮 Использование

### Подключение

1. Запустите сервер **CyberDeck** на ПК.
2. Откройте приложение на телефоне.
3. Отсканируйте QR-код с экрана лаунчера или введите **IP:PORT** и **PIN** вручную.
4. Нажмите **CONNECT**.

### 🖱️ Жесты управления

| Жест | Действие |
|---|---|
| 1 палец (движение) | Перемещение курсора |
| 1 палец (тап) | Левый клик (ЛКМ) |
| 2 пальца (движение) | Плавный скролл |
| 2 пальца (тап) | Правый клик (ПКМ) |
| Двойной тап + удержание | Перетаскивание (Drag & Drop) |

### 🎛️ Элементы интерфейса

- **⏻** — выключение компьютера.
- **↻** — поворот экрана (видеопотока) на 90°.
- **KEYBOARD** — открыть панель клавиатуры и спец. клавиш.
- **Side Bar** — управление громкостью (+ / − / Mute).

---

## 🔧 Структура проекта

```
lib/
├── main.dart                          # Точка входа, deep links, MaterialApp
├── home_screen.dart                   # Главный экран со списком устройств
├── connect_screen.dart                # Экран подключения (IP/PIN/QR)
├── dashboard_screen.dart              # Панель управления устройством
├── control_screen.dart                # Экран управления (тачпад, стрим, жесты)
├── settings_screen.dart               # Настройки приложения
├── device_settings_screen.dart        # Настройки конкретного устройства
├── diagnostics_screen.dart            # Диагностика соединения
├── help_screen.dart                   # Справка
├── qr_scan_screen.dart                # QR-сканер
├── qr_payload_parser.dart             # Парсинг QR-пакета
├── device_storage.dart                # Хранение подключённых устройств
├── mjpeg_view.dart                    # MJPEG виджет с оптимизацией буфера
├── ts_stream_view.dart                # MPEG-TS (H.264/H.265) виджет
├── audio_relay_view.dart              # Виджет аудиопотока
├── file_transfer.dart                 # UI передачи файлов
├── services_discovery.dart            # Обнаружение серверов в сети
├── theme.dart                         # Тема приложения
├── app_version.dart                   # Версия приложения
│
├── network/                           # Сетевой слой
│   ├── api_client.dart                # HTTP-клиент с retry-логикой
│   ├── host_port.dart                 # Парсинг host:port
│   ├── protocol_service.dart          # Согласование версий протокола
│   └── reconnecting_ws_client.dart    # WebSocket с автореконнектом
│
├── services/                          # Бизнес-логика
│   ├── pairing_service.dart           # Сопряжение (PIN/QR)
│   ├── transfer_service.dart          # Загрузка/скачивание файлов + SHA-256
│   ├── update_check_service.dart      # Проверка обновлений через GitHub API
│   └── system_notifications.dart      # Локальные уведомления
│
├── control/controllers/               # Контроллеры реального времени
│   └── control_connection_controller  # WebSocket heartbeat, ACK, RTT
│
├── stream/                            # Потоковое видео
│   ├── stream_offer_parser.dart       # Парсинг server offer JSON
│   └── adaptive_stream_controller.dart # Адаптивный выбор кандидатов
│
├── security/                          # Безопасность
├── errors/                            # Каталог ошибок
├── l10n/                              # Локализация
└── widgets/                           # Переиспользуемые виджеты
```

---

## 🧪 Контрактные снапшоты

Для проверки совместимости протокола с сервером CyberDeck:

```powershell
./tool/sync_server_contract_snapshots.ps1
flutter test test/server_contract_snapshot_test.dart
```

Режим проверки (CI):

```powershell
./tool/sync_server_contract_snapshots.ps1 -Check
```

---

## 🐛 FAQ

| Проблема | Решение |
|---|---|
| **Connection Failed** | 1. Телефон и ПК в одной Wi-Fi сети. 2. Сервер запущен. 3. Проверьте брандмауэр Windows. |
| **Чёрный экран** | Нажмите ↻ или перезапустите стрим. |
| **Слишком быстрый скролл** | Настройте `scrollFactor` в настройках приложения. |

---

## 🤝 Вклад в проект

1. Форкните репозиторий.
2. Создайте ветку (`git checkout -b feature/AmazingFeature`).
3. Закоммитьте изменения.
4. Откройте Pull Request.

---

**📄 Лицензия:** GNU GPL v3

**🌟 Часть экосистемы [CyberDeck](https://github.com/Overl1te/CyberDeck)**

<div align="center"><p>Сделано с ❤️ и Flutter</p></div>

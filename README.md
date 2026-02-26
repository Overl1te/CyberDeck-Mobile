<div align="center">

# CyberDeck-Mobile

![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?logo=dart)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey)
![License](https://img.shields.io/badge/license-GNU%20GPLv3-green)

**Официальный мобильный клиент для системы удаленного управления CyberDeck**

[Оригинальный проект CyberDeck](https://github.com/Overl1te/CyberDeck)

[Особенности](#Особенности) • [Установка](#Установка) • [Использование](#Использование) • [Структура](#Структура) • [FAQ](#FAQ)

</div>

---

## 📸 Скриншоты

Coming soon...

---

## <div id="Особенности">✨ Особенности</div>

### 🎯 Основные возможности

- **🖱️ Нативный Тачпад** — Использование сенсора телефона для управления курсором с нулевой задержкой (Raw Touch Events).

- **⌨️ Виртуальная Клавиатура** — Выдвижная панель с поддержкой ввода текста и спец. клавиш (`Win`, `Alt+Tab`, `Copy`, `Paste`).

- **📺 MJPEG Стриминг** — Просмотр экрана ПК в реальном времени с поддержкой поворота экрана (`Rotate`).

- **👆 Мультитач Жесты** — Скролл двумя пальцами, Drag&Drop, правый/левый клик.

- **🎨 Cyberpunk UI** — Интерфейс в стиле Glassmorphism с неоновыми акцентами и шрифтом Rajdhani.

- **🔌 Быстрое подключение** — Сохранение IP-адреса и авторизация по коду сопряжения.

### 🛠️ Технические преимущества

- **⚡ Производительность** — Написано на Flutter, работает быстрее и плавнее, чем веб-версия.

- **🔄 Умный скролл** — Алгоритм накопления пикселей для плавного скроллинга (как на Precision Touchpad).

- **📱 Полный экран** — Поддержка `Immersive Sticky` режима для максимального погружения.

## <div id="Установка">🚀 Установка и Сборка</div>

### Предварительные требования

- **Flutter SDK** (версия 3.0 или выше)
- **Android Studio** / **VS Code**
- Устройство Android или Эмулятор

### Шаг 1: Клонирование репозитория

```bash
git clone https://github.com/Overl1te/CyberDeck-Mobile.git

cd CyberDeck-Mobile
```

### Шаг 2: Установка зависимостей

```bash
flutter pub get
```

### Шаг 3: Генерация иконок (Опционально)

Если вы меняли иконку в `assets/icon/icon.png`:

```bash
dart run flutter_launcher_icons
```

### Шаг 4: Запуск / Сборка

**Запуск в режиме отладки (на подключенном телефоне):**

```bash
flutter run
```

**Сборка APK (Release):**

```bash
flutter build apk --release
flutter build apk --split-per-abi
```

Файл будет находиться в: `build/app/outputs/flutter-apk/app-release.apk`

---

## <div id="Использование">🎮 Использование</div>

### Подключение

1. Запустите сервер **CyberDeck** на вашем ПК (`main.py`).
2. Узнайте локальный IP вашего ПК и код сопряжения (выводится в консоль сервера).
3. Откройте приложение на телефоне.
4. Введите **IP:PORT** (например, `192.168.1.5:8000`) и **Code**.
5. Нажмите **CONNECT SYSTEM**.

### 🖱️ Жесты управления

| Жест | Действие |
| --- | --- |
| **1 палец (движение)** | Перемещение курсора |
| **1 палец (тап)** | Левый клик (ЛКМ) |
| **2 пальца (движение)** | Плавный скролл |
| **2 пальца (тап)** | Правый клик (ПКМ) |
| **Двойной тап + удержание** | Перетаскивание (Drag & Drop) |

### 🎛️ Элементы интерфейса

* **⏻** — Выключение компьютера.
* **↻** — Поворот экрана (видеопотока) на 90 градусов.
* **KEYBOARD** — Открыть шторку с клавиатурой и спец. клавишами.
* **Side Bar** — Управление громкостью (+ / - / Mute).

---

## <div id="Структура">🔧 Структура проекта</div>

```
lib/
├── main.dart           # Точка входа, UI, логика тачпада и WebSocket
├── mjpeg_view.dart     # Виджет для обработки MJPEG потока с оптимизацией буфера
assets/
└── icon/               # Исходники иконок
pubspec.yaml            # Зависимости (http, google_fonts, shared_preferences и др.)

```

## <div id='FAQ'>🐛 Частозадаваемые вопросы (FAQ)</div>

### Частые проблемы

| Проблема | Решение |
| --- | --- |
| **Connection Failed** | 1. Убедитесь, что телефон и ПК в одной Wi-Fi сети. <br> 2. Проверьте, что сервер на ПК запущен <br>3. Отключите брандмауэр Windows или добавьте Python в исключения. |
| **Черный экран вместо видео** | Нажмите кнопку обновления ↻ или проверьте, не свернуто ли приложение на ПК. |
| **Скролл слишком быстрый** | Параметры чувствительности настроены под Windows. Их можно изменить в `main.dart` (переменная `scrollFactor`). |

## 🤝 Вклад в проект

**Вклад приветствуется!**

1. Форкните репозиторий
2. Создайте ветку (`git checkout -b feature/AmazingFeature`)
3. Закоммитьте изменения (`git commit -m 'Add some AmazingFeature'`)
4. Запушьте ветку (`git push origin feature/AmazingFeature`)
5. Откройте Pull Request

**📄 Лицензия**

* Этот проект распространяется под лицензией GNU GPL v3.

**🌟 Поддержка проекта**

* Сделано как часть экосистемы **CyberDeck**.

<div align="center"> <p>Сделано с ❤️ и Flutter</p> </div>
---

## Protocol Migration Notes (CyberDeck Protocol vNext)

- Client now probes `GET /api/protocol` before stream/WS startup.
  - `404` on `/api/protocol` enables `legacy mode`.
  - Legacy mode keeps old behavior (no required WS `hello` / `ping` / `pong` handshake logic).
- Stream startup now uses `GET /api/stream_offer` candidates in order with per-candidate startup timeout (`1200-2000ms`), then fallback to next candidate.
- Working stream candidate is remembered per-host and preferred first on next session.
- Adaptive quality now uses `adaptive_hint` from `stream_offer` plus runtime RTT/FPS.
  - Downscale and upscale are step-based.
  - Hard UX floors are enforced (`fps >= 10`, `max_w >= 640`).
- WS reliability:
  - On connect, client sends `hello` with `capabilities.heartbeat_ack=true`.
  - On server `ping`, client replies `pong` with same `id`.
  - Heartbeat timeout forces reconnect.
  - Reconnect is exponential backoff with jitter.
  - Control state recovery sends safety sync (`drag_e`) after reconnect.
- Diagnostics:
  - New diagnostics screen in control UI (`bug_report` icon).
  - `Copy diagnostic report` includes `/api/diag`, fresh `/api/stream_offer`, and current candidate/runtime state.
- File transfer:
  - Supports new WS payload fields: `transfer_id`, `sha256`, `accept_ranges`, `expires_at`.
  - Download uses HTTP Range resume when allowed.
  - SHA-256 is validated after download.
  - On checksum mismatch, download is retried from scratch with bounded attempts.

### Logging

- Fallback/adaptive transitions: `[CyberDeck][Stream] ...`
- WS protocol/heartbeat/reconnect: `[CyberDeck][WS] ...`
- WS transport reconnect scheduling: `CyberDeck.WS` logger (developer log)

## Manual Test Checklist (Android + iOS)

1. New protocol negotiation:
   - Server supports `/api/protocol` -> client connects, stream starts, controls work.
2. Legacy compatibility:
   - Server returns `404` on `/api/protocol` -> client still connects and controls/stream continue in legacy mode.
3. Candidate fallback:
   - Break first stream candidate (or block endpoint) -> app switches to next candidate within timeout.
4. Stall fallback:
   - Force active stream to stop producing frames (`fps=0`) -> app falls back to next candidate after stall timeout.
5. Adaptive quality down:
   - Simulate poor network/high RTT -> observe reduced `fps/max_w/quality` and stream recovery.
6. Adaptive quality up:
   - Restore stable network -> quality parameters recover gradually (not in one jump).
7. WS heartbeat:
   - Verify `hello` send, `ping` receive, `pong` reply (same id) in server logs.
8. WS reconnect:
   - Temporarily stop WS endpoint -> client reconnects with backoff+jitter and recovers controls.
9. Diagnostics report:
   - Open diagnostics screen, verify fields update.
   - Tap `Copy diagnostic report`, paste and validate report contains `/api/diag`, `stream_offer`, current candidate.
10. File resume + checksum:
   - Trigger file transfer with `accept_ranges=true`.
   - Interrupt network mid-download, restore network -> download resumes.
   - Force checksum mismatch -> app retries and reports final success/failure correctly.

---

## Release & Update Check

- Mobile app version: `1.1.2`
- Recommended CyberDeck server/launcher version: `1.3.2`
- Mobile settings screen now includes a GitHub release check against:
  - `https://api.github.com/repos/Overl1te/CyberDeck/releases/latest`
  - `https://api.github.com/repos/Overl1te/CyberDeck-Mobile/releases/latest`


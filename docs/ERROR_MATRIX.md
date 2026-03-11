# CyberDeck-Mobile Error Matrix

_Updated: 2026-03-08 08:04 UTC_

Source: `lib/errors/error_catalog.dart` (`builtinErrorCatalog`).

Columns: `Code` / `Title` / `Summary` / `Tags`.

## Pairing

Pairing/PIN/QR/approval related errors.

| Code | Title | Summary | Tags |
|---|---|---|---|
| CD-2001 | Лимит попыток PIN | Слишком много неверных PIN в короткое время. | pairing, pin |
| CD-2002 | Неверный PIN | PIN не совпадает с текущим кодом сервера. | pairing, pin |
| CD-2003 | PIN истек | Срок действия кода сопряжения завершился. | pairing, ttl |
| CD-2102 | QR-токен недействителен | QR-токен устарел, уже использован или поврежден. | pairing, qr |
| CD-2103 | Ожидается подтверждение на ПК | Запрос отправлен, но устройство еще не одобрено на хосте. | pairing, approval |

## Upload

Upload and file-transfer related errors.

| Code | Title | Summary | Tags |
|---|---|---|---|
| CD-3001 | Расширение файла запрещено | Сервер отклонил тип файла по whitelist. | upload, file |
| CD-3002 | Файл слишком большой | Превышен лимит размера загрузки. | upload, limit |
| CD-3003 | Не совпала контрольная сумма | Передача повреждена или завершилась с ошибкой целостности. | upload, checksum |

## Auth

Token/permission related errors.

| Code | Title | Summary | Tags |
|---|---|---|---|
| CD-1401 | Неавторизованный запрос | Токен сессии отсутствует или недействителен. | auth, token |
| CD-1403 | Недостаточно прав | Для текущего действия запрещен permission на стороне ПК. | permissions, security |

## System

System and input backend related errors.

| Code | Title | Summary | Tags |
|---|---|---|---|
| CD-5009 | Keyboard backend недоступен | Сервер не может отправить клавиатурное событие в ОС. | input, keyboard |

## Other

Errors outside core subsystems (validation/internal/etc).

| Code | Title | Summary | Tags |
|---|---|---|---|
| CD-1000 | Некорректные входные данные | Сервер отклонил запрос из-за неверного формата параметров. | validation, request |
| CD-9000 | Внутренняя ошибка сервера | На стороне ПК возникла непредвиденная ошибка. | internal, server |

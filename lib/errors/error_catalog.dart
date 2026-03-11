class ErrorArticle {
  final String code;
  final int? number;
  final int? status;
  final String slug;
  final String docsUrl;
  final String title;
  final String summary;
  final List<String> steps;
  final List<String> tags;

  const ErrorArticle({
    required this.code,
    this.number,
    this.status,
    this.slug = '',
    this.docsUrl = '',
    required this.title,
    required this.summary,
    required this.steps,
    this.tags = const <String>[],
  });
}

const List<ErrorArticle> builtinErrorCatalog = <ErrorArticle>[
  ErrorArticle(
    code: 'CD-1000',
    title: 'Некорректные входные данные',
    summary: 'Сервер отклонил запрос из-за неверных параметров.',
    steps: <String>[
      'Проверьте обязательные поля и формат значений.',
      'Убедитесь, что IP/порт и код подключения введены корректно.',
      'Повторите действие.',
    ],
    tags: <String>['validation', 'request'],
  ),
  ErrorArticle(
    code: 'CD-1401',
    title: 'Неавторизованный запрос',
    summary: 'Токен сессии отсутствует или недействителен.',
    steps: <String>[
      'Переподключите устройство через экран Connect.',
      'Проверьте, что устройство не удалено из доверенных на ПК.',
      'При необходимости выполните повторное сопряжение.',
    ],
    tags: <String>['auth', 'token'],
  ),
  ErrorArticle(
    code: 'CD-1403',
    title: 'Недостаточно прав',
    summary: 'Для действия не хватает разрешений на стороне ПК.',
    steps: <String>[
      'Откройте Devices в лаунчере на ПК.',
      'Выдайте нужные права для этого телефона.',
      'Повторите действие.',
    ],
    tags: <String>['permissions', 'security'],
  ),
  ErrorArticle(
    code: 'CD-2001',
    title: 'Превышен лимит попыток PIN',
    summary: 'Слишком много неверных PIN за короткое время.',
    steps: <String>[
      'Подождите время из Retry-After.',
      'Проверьте актуальный PIN в лаунчере.',
      'Попробуйте снова.',
    ],
    tags: <String>['pairing', 'pin'],
  ),
  ErrorArticle(
    code: 'CD-2002',
    title: 'Неверный PIN',
    summary: 'Введенный PIN не совпадает с текущим кодом сервера.',
    steps: <String>[
      'Сверьте PIN с лаунчером на ПК.',
      'Проверьте, что подключаетесь к нужному хосту.',
      'При необходимости сгенерируйте новый PIN.',
    ],
    tags: <String>['pairing', 'pin'],
  ),
  ErrorArticle(
    code: 'CD-2003',
    title: 'Срок действия PIN истек',
    summary: 'Код сопряжения устарел.',
    steps: <String>[
      'Сгенерируйте новый PIN на ПК.',
      'Отсканируйте новый QR или введите PIN заново.',
      'Повторите подключение.',
    ],
    tags: <String>['pairing', 'ttl'],
  ),
  ErrorArticle(
    code: 'CD-2102',
    title: 'QR-токен недействителен',
    summary: 'QR-токен устарел, уже использован или поврежден.',
    steps: <String>[
      'Откройте свежий QR-код в лаунчере.',
      'Сканируйте код повторно.',
      'Если не помогло, используйте PIN-подключение.',
    ],
    tags: <String>['pairing', 'qr'],
  ),
  ErrorArticle(
    code: 'CD-2103',
    title: 'Ожидается подтверждение на ПК',
    summary: 'Запрос отправлен, но устройство еще не одобрено на хосте.',
    steps: <String>[
      'Откройте вкладку Devices в лаунчере.',
      'Подтвердите подключение устройства.',
      'Вернитесь в приложение и повторите действие.',
    ],
    tags: <String>['pairing', 'approval'],
  ),
  ErrorArticle(
    code: 'CD-3001',
    title: 'Тип файла не разрешен',
    summary: 'Сервер отклонил расширение файла по whitelist.',
    steps: <String>[
      'Выберите файл с разрешенным расширением.',
      'Или обновите upload_allowed_ext на ПК.',
      'Повторите загрузку.',
    ],
    tags: <String>['upload', 'file'],
  ),
  ErrorArticle(
    code: 'CD-3002',
    title: 'Файл слишком большой',
    summary: 'Превышен лимит размера загрузки.',
    steps: <String>[
      'Сожмите файл или отправьте его частями.',
      'При необходимости увеличьте upload_max_bytes на ПК.',
      'Повторите загрузку.',
    ],
    tags: <String>['upload', 'limit'],
  ),
  ErrorArticle(
    code: 'CD-3003',
    title: 'Ошибка контрольной суммы',
    summary: 'Передача повреждена или завершилась с ошибкой целостности.',
    steps: <String>[
      'Повторите передачу при стабильной сети.',
      'Проверьте исходный файл на устройстве.',
      'Если ошибка повторяется, перезапустите сервер и приложение.',
    ],
    tags: <String>['upload', 'checksum'],
  ),
  ErrorArticle(
    code: 'CD-5009',
    title: 'Keyboard backend недоступен',
    summary: 'Сервер не смог отправить клавиатурное событие в ОС.',
    steps: <String>[
      'Проверьте права ввода на ПК.',
      'Запустите лаунчер с нужными системными разрешениями.',
      'Перезапустите сервер.',
    ],
    tags: <String>['input', 'keyboard'],
  ),
  ErrorArticle(
    code: 'CD-9000',
    title: 'Внутренняя ошибка сервера',
    summary: 'На стороне ПК произошла непредвиденная ошибка.',
    steps: <String>[
      'Повторите действие через несколько секунд.',
      'Проверьте логи на ПК и incident_id.',
      'При необходимости перезапустите сервер.',
    ],
    tags: <String>['internal', 'server'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4100',
    title: 'Канал WS отключен',
    summary: 'Канал управления (WebSocket) разорван.',
    steps: <String>[
      'Проверьте, что сервер на ПК запущен.',
      'Проверьте сеть телефона и ПК (одна подсеть/точка доступа).',
      'Нажмите Smart recovery или переподключитесь.',
    ],
    tags: <String>['mobile', 'ws'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4101',
    title: 'Таймаут heartbeat',
    summary: 'Пакеты heartbeat перестали приходить вовремя.',
    steps: <String>[
      'Проверьте качество сети и пинг.',
      'Уменьшите нагрузку, выберите профиль Mobile hotspot.',
      'Запустите Smart recovery.',
    ],
    tags: <String>['mobile', 'ws', 'heartbeat'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4102',
    title: 'Таймаут подтверждения ввода',
    summary: 'Событие клавиатуры/ввода не подтвердилось вовремя.',
    steps: <String>[
      'Убедитесь, что канал WS стабильный.',
      'Проверьте доступность input backend на ПК.',
      'Повторите ввод после восстановления соединения.',
    ],
    tags: <String>['mobile', 'input', 'ack'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4201',
    title: 'Видеопоток устарел',
    summary: 'Поток перестал обновляться, но сессия еще не завершена.',
    steps: <String>[
      'Нажмите Smart recovery.',
      'Переключите сетевой профиль на Mobile hotspot.',
      'Если не помогло, переподключитесь к устройству.',
    ],
    tags: <String>['mobile', 'video', 'stream'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4202',
    title: 'Таймаут stream_offer',
    summary: 'Сервер не успел выдать параметры видеопотока.',
    steps: <String>[
      'Проверьте нагрузку на ПК.',
      'Проверьте доступность /api/stream_offer.',
      'Повторите попытку через несколько секунд.',
    ],
    tags: <String>['mobile', 'video', 'api'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4301',
    title: 'Ошибка аудио-релея',
    summary: 'Не удалось воспроизвести резервный аудиопоток.',
    steps: <String>[
      'Проверьте, что звук включен в приложении и на ПК.',
      'Проверьте доступность /audio_stream.',
      'Перезапустите воспроизведение или запустите Smart recovery.',
    ],
    tags: <String>['mobile', 'audio'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4401',
    title: 'API канала управления недоступен',
    summary:
        'Канал API отвечает нестабильно или перестал обновлять статистику.',
    steps: <String>[
      'Проверьте, что сервер на ПК запущен и доступен по HTTP/HTTPS.',
      'Проверьте сеть и порт подключения.',
      'Запустите автовосстановление или переподключитесь.',
    ],
    tags: <String>['mobile', 'api', 'network'],
  ),
  ErrorArticle(
    code: 'CD-MOB-4999',
    title: 'Неизвестная ошибка клиента',
    summary: 'Сформировано локальное сообщение без явного кода каталога.',
    steps: <String>[
      'Откройте Diagnostics и скопируйте отчет.',
      'Сверьте последнее сообщение и состояние каналов.',
      'Попробуйте Smart recovery.',
    ],
    tags: <String>['mobile', 'unknown'],
  ),
];

List<ErrorArticle> searchErrorCatalog(
  String query, {
  List<ErrorArticle> extra = const <ErrorArticle>[],
}) {
  final mergedByCode = <String, ErrorArticle>{};
  for (final item in builtinErrorCatalog) {
    mergedByCode[item.code] = item;
  }
  for (final item in extra) {
    final existing = mergedByCode[item.code];
    if (existing == null) {
      mergedByCode[item.code] = item;
      continue;
    }
    mergedByCode[item.code] = _mergeErrorArticle(existing, item);
  }
  final rows = mergedByCode.values.toList()
    ..sort((a, b) {
      final an = a.number;
      final bn = b.number;
      if (an != null && bn != null) return an.compareTo(bn);
      return a.code.compareTo(b.code);
    });

  final q = query.trim().toLowerCase();
  if (q.isEmpty) return rows;
  return rows.where((item) {
    final haystack = <String>[
      item.code,
      if (item.number != null) item.number.toString(),
      if (item.status != null) 'http ${item.status}',
      item.slug,
      item.title,
      item.summary,
      ...item.tags,
      ...item.steps,
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }).toList();
}

ErrorArticle _mergeErrorArticle(ErrorArticle local, ErrorArticle remote) {
  final remoteTitle = remote.title.trim();
  final remoteSummary = remote.summary.trim();
  final mergedSteps = remote.steps
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  final effectiveSteps = mergedSteps.isNotEmpty ? mergedSteps : local.steps;
  final mergedTags = <String>{...local.tags, ...remote.tags}
      .where((e) => e.trim().isNotEmpty)
      .toList(growable: false);
  return ErrorArticle(
    code: local.code,
    number: remote.number ?? local.number,
    status: remote.status ?? local.status,
    slug: remote.slug.trim().isNotEmpty ? remote.slug : local.slug,
    docsUrl: remote.docsUrl.trim().isNotEmpty ? remote.docsUrl : local.docsUrl,
    title: remoteTitle.isNotEmpty ? remoteTitle : local.title,
    summary: remoteSummary.isNotEmpty ? remoteSummary : local.summary,
    steps: effectiveSteps,
    tags: mergedTags,
  );
}

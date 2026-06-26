import 'package:flutter/widgets.dart' show ImageProvider;

import 'content_overlay_stub.dart'
    if (dart.library.io) 'content_overlay_io.dart' as impl;

/// Итог попытки OTA-обновления (для кнопки в Настройках и логов).
enum OtaStatus {
  updated, // скачана и применена новая версия контента
  upToDate, // на устройстве уже свежая
  skipped, // платформа без OTA (web) или гейт min_app_version не пройден
  offline, // нет сети/таймаут — молча остаёмся на кеше/ассете
  error, // ошибка загрузки/валидации — остались на прежнем контенте
}

class OtaResult {
  final OtaStatus status;
  final int? version; // версия контента после операции (если применимо)
  final String? message;
  const OtaResult(this.status, {this.version, this.message});
}

/// Слой свежего OTA-контента поверх вшитых ассетов.
///
/// Приоритет источника: применённый OTA-кеш → вшитый ассет. На web — заглушка
/// (файловой системы нет; web и так пересобирается с актуальным контентом).
abstract class ContentOverlay {
  /// Подготовка: резолв каталогов кеша, восстановление last-good. На web no-op.
  Future<void> init();

  /// JSON-контент по плоскому имени ('index.json', '01_find_error.json')
  /// из применённого OTA-кеша, или null если его там нет.
  Future<String?> tryLoadString(String relName);

  /// ImageProvider для уже скачанной картинки из кеша, иначе null (синхронно).
  ImageProvider? cachedImage(String fileName);

  /// Лениво догрузить картинку в кеш по требованию; вернуть провайдер или null.
  Future<ImageProvider?> ensureImage(String fileName);

  /// Проверить канал и применить обновление (фон при старте / кнопка в настройках).
  Future<OtaResult> checkForUpdate();
}

ContentOverlay createContentOverlay() => impl.createContentOverlay();

/// Активный overlay приложения. Ставится в main() после init(); читается
/// виджетами картинок (OtaImage), которым неудобно протаскивать его через
/// конструкторы. Один экземпляр на весь жизненный цикл приложения.
ContentOverlay? contentOverlay;

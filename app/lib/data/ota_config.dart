/// Конфигурация OTA-доставки контента (обновление заданий без переустановки).

/// Базовый URL OTA-канала на GitHub Pages. CI публикует сюда контент + manifest.json.
const String kOtaBaseUrl =
    'https://alex010101010.github.io/speech-rehab/ota';

/// Версия движка для гейта min_app_version из манифеста.
///
/// Это НЕ versionCode из pubspec. Поднимать только когда движок получает
/// возможность, которую новый контент может потребовать (новое поле/тип задания).
/// Если контент в манифесте объявляет min_app_version > kAppOtaVersion —
/// приложение игнорирует обновление (старый APK не сломается о новый контент).
const int kAppOtaVersion = 2;

/// Таймаут сетевых операций OTA. Офлайн/медленно — молча остаёмся на кеше/ассете.
const Duration kOtaTimeout = Duration(seconds: 12);

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
const int kAppOtaVersion = 3;

/// Таймаут сетевых операций OTA. Офлайн/медленно — молча остаёмся на кеше/ассете.
const Duration kOtaTimeout = Duration(seconds: 12);

/// Tier B (самообновление APK). Манифест самого свежего релиза — стабильный
/// адрес GitHub: всегда отдаёт ассет из последнего релиза, без токенов.
const String kAppManifestUrl =
    'https://github.com/Alex010101010/speech-rehab/releases/latest/download/app_manifest.json';

/// Таймаут скачивания самого APK — файл крупный, нужен запас сверх kOtaTimeout.
const Duration kApkDownloadTimeout = Duration(minutes: 5);

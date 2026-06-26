import 'package:flutter/widgets.dart' show ImageProvider;

import 'content_overlay.dart';

/// Заглушка для платформ без файловой системы (web). OTA выключен:
/// приложение всегда читает вшитые ассеты, собранные в актуальной версии.
ContentOverlay createContentOverlay() => const _StubContentOverlay();

class _StubContentOverlay implements ContentOverlay {
  const _StubContentOverlay();

  @override
  Future<void> init() async {}

  @override
  Future<String?> tryLoadString(String relName) async => null;

  @override
  ImageProvider? cachedImage(String fileName) => null;

  @override
  Future<ImageProvider?> ensureImage(String fileName) async => null;

  @override
  Future<OtaResult> checkForUpdate() async =>
      const OtaResult(OtaStatus.skipped, message: 'OTA недоступен на этой платформе');
}

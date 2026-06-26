import 'package:flutter/material.dart';

import '../data/content_overlay.dart';

/// Картинка-подсказка с цепочкой источников: OTA-кеш → вшитый ассет → emoji.
///
/// Новые картинки, добавленные через OTA уже после сборки APK, в ассетах
/// отсутствуют — тогда промах ассета запускает ленивую догрузку из кеша.
/// dart:io сюда не проникает: файловый источник прячется за ImageProvider
/// внутри io-реализации overlay (на web overlay всегда отдаёт null).
class OtaImage extends StatefulWidget {
  final String fileName; // голое имя, напр. 'lozhka.png'
  final String? emoji; // запасная опора, если картинки нет
  final double height;
  const OtaImage({
    super.key,
    required this.fileName,
    this.emoji,
    this.height = 200,
  });

  @override
  State<OtaImage> createState() => _OtaImageState();
}

class _OtaImageState extends State<OtaImage> {
  ImageProvider? _cached;
  bool _fetchTried = false;

  @override
  void initState() {
    super.initState();
    _cached = contentOverlay?.cachedImage(widget.fileName);
  }

  Widget _emoji() => (widget.emoji != null && widget.emoji!.isNotEmpty)
      ? Text(widget.emoji!, style: const TextStyle(fontSize: 110))
      : const SizedBox.shrink();

  void _lazyFetch() {
    if (_fetchTried) return;
    _fetchTried = true;
    contentOverlay?.ensureImage(widget.fileName).then((p) {
      if (p != null && mounted) setState(() => _cached = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cached != null) {
      return Image(
        image: _cached!,
        height: widget.height,
        errorBuilder: (_, __, ___) => _emoji(),
      );
    }
    // Нет в кеше — пробуем вшитый ассет; при промахе лениво качаем из OTA.
    return Image.asset(
      'assets/content/img/${widget.fileName}',
      height: widget.height,
      errorBuilder: (_, __, ___) {
        _lazyFetch();
        return _emoji();
      },
    );
  }
}

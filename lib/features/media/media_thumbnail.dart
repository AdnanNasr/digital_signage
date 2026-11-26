import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/media_file.dart';
import '../../services/signage_api.dart';

class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({super.key, required this.file, required this.api});
  final MediaFile file;
  final SignageApi? api;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  late Future<Uint8List>? _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.file.isImage ? widget.api?.preview(widget.file.id) : null;
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      widget.file.isImage ? Icons.image_outlined : Icons.movie_outlined,
      color: Theme.of(context).colorScheme.primary,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        height: 56,
        color: const Color(0xFFEDF1FC),
        alignment: Alignment.center,
        child: _preview == null
            ? icon
            : FutureBuilder<Uint8List>(
                future: _preview,
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        semanticLabel: widget.file.name,
                        errorBuilder: (context, error, stack) => icon,
                      )
                    : icon,
              ),
      ),
    );
  }
}

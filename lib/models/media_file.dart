class MediaFile {
  const MediaFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.type = 'video',
  });

  final String id;
  final String name;
  final int sizeBytes;
  final String type;
  bool get isImage => type == 'image';

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
    id: json['id'] as String,
    name: json['name'] as String,
    sizeBytes: json['size_bytes'] as int,
    type: json['type'] as String? ?? 'video',
  );

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KiB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MiB';
  }
}

abstract class MediaUpload {
  String get name;
  int get size;
  Future<void> send(Uri url, String token, void Function(double) onProgress);
  void cancel();
}

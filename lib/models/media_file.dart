class MediaFile {
  const MediaFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
  });

  final String id;
  final String name;
  final int sizeBytes;

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
    id: json['id'] as String,
    name: json['name'] as String,
    sizeBytes: json['size_bytes'] as int,
  );

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KiB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MiB';
  }
}

abstract class VideoUpload {
  String get name;
  int get size;
  Future<void> send(Uri url, String token, void Function(double) onProgress);
  void cancel();
}

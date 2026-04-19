class NetworkFile {
  final String fieldName;
  final String filePath;
  final String? filename;
  final String? contentType;

  const NetworkFile({
    required this.fieldName,
    required this.filePath,
    this.filename,
    this.contentType,
  });
}

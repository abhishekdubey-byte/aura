
enum UploadStatus { pending, uploading, uploaded, failed, retrying }

class UploadRecord {
  final String imageId; // SHA-256 hash of the image
  final String localPath;
  UploadStatus status;
  int retryCount;
  final DateTime createdAt;
  DateTime lastAttempt;
  String? errorMessage;

  UploadRecord({
    required this.imageId,
    required this.localPath,
    this.status = UploadStatus.pending,
    this.retryCount = 0,
    DateTime? createdAt,
    DateTime? lastAttempt,
    this.errorMessage,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastAttempt = lastAttempt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'imageId': imageId,
      'localPath': localPath,
      'status': status.name,
      'retryCount': retryCount,
      'createdAt': createdAt.toIso8601String(),
      'lastAttempt': lastAttempt.toIso8601String(),
      'errorMessage': errorMessage,
    };
  }

  factory UploadRecord.fromJson(Map<String, dynamic> json) {
    return UploadRecord(
      imageId: json['imageId'],
      localPath: json['localPath'],
      status: UploadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => UploadStatus.pending,
      ),
      retryCount: json['retryCount'] ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      lastAttempt: json['lastAttempt'] != null ? DateTime.parse(json['lastAttempt']) : null,
      errorMessage: json['errorMessage'],
    );
  }
}

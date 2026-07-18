/// A reference photo with its extracted pose keypoints and metadata.
class ReferenceModel {
  final String id;
  final String? imagePath;
  final String? outlinePath;
  final DateTime createdAt;
  final String? keypointsJson;
  final String? proSettingsJson;
  final double? width;
  final double? height;

  const ReferenceModel({
    required this.id,
    this.imagePath,
    this.outlinePath,
    required this.createdAt,
    this.keypointsJson,
    this.proSettingsJson,
    this.width,
    this.height,
  });

  factory ReferenceModel.fromMap(Map<String, dynamic> map) {
    return ReferenceModel(
      id: map['id'] as String,
      imagePath: map['imagePath'] as String?,
      outlinePath: map['outlinePath'] as String?,
      createdAt: map['createdAt'] is String
          ? DateTime.parse(map['createdAt'])
          : (map['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      keypointsJson: map['keypointsJson'] as String?,
      proSettingsJson: map['proSettingsJson'] as String?,
      width: (map['width'] as num?)?.toDouble(),
      height: (map['height'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'imagePath': imagePath,
        'outlinePath': outlinePath,
        'createdAt': createdAt,
        'keypointsJson': keypointsJson,
        'proSettingsJson': proSettingsJson,
        'width': width,
        'height': height,
      };
}

class Person {
  Person({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.name,
    this.photoUrl,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  final String name;
  final String? photoUrl;

  Person copyWith({
    String? name,
    String? photoUrl,
    String? ownerName,
    bool clearPhoto = false,
  }) {
    return Person(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName ?? this.ownerName,
      name: name ?? this.name,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
    );
  }

  factory Person.fromRow(
    Map<String, dynamic> row, {
    String ownerName = '',
  }) {
    return Person(
      id: row['id'].toString(),
      ownerId: row['owner_id'].toString(),
      ownerName: ownerName,
      name: row['name']?.toString() ?? '',
      photoUrl: row['photo_url'] as String?,
    );
  }

  String get initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1).toUpperCase();
  }

  bool isOwnedBy(String? userId) => userId != null && ownerId == userId;
}

/// Rola bieżącego użytkownika wobec udostępnionego profilu.
/// `null` gdy jestem ownerem (pełna kontrola).
enum ShareRole { editor, viewer }

class Person {
  Person({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.name,
    this.photoUrl,
    this.myRole,
    this.ovulationUncertainty = defaultOvulationUncertainty,
  });

  static const int defaultOvulationUncertainty = 1;
  static const int minOvulationUncertainty = 0;
  static const int maxOvulationUncertainty = 3;

  final String id;
  final String ownerId;
  final String ownerName;
  final String name;
  final String? photoUrl;

  /// Rola bieżącego użytkownika w tym profilu. `null` jeśli jestem ownerem.
  final ShareRole? myRole;

  /// Margines błędu prognozy owulacji w dniach (0..3). Domyślnie 2.
  /// Większa wartość = szersze okno owulacji i okno płodne.
  final int ovulationUncertainty;

  Person copyWith({
    String? name,
    String? photoUrl,
    String? ownerName,
    ShareRole? myRole,
    int? ovulationUncertainty,
    bool clearPhoto = false,
  }) {
    return Person(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName ?? this.ownerName,
      name: name ?? this.name,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      myRole: myRole ?? this.myRole,
      ovulationUncertainty:
          ovulationUncertainty ?? this.ovulationUncertainty,
    );
  }

  factory Person.fromRow(
    Map<String, dynamic> row, {
    String ownerName = '',
    ShareRole? myRole,
  }) {
    final rawUncert = row['ovulation_uncertainty'];
    final uncert = (rawUncert is int)
        ? rawUncert.clamp(minOvulationUncertainty, maxOvulationUncertainty)
        : defaultOvulationUncertainty;
    return Person(
      id: row['id'].toString(),
      ownerId: row['owner_id'].toString(),
      ownerName: ownerName,
      name: row['name']?.toString() ?? '',
      photoUrl: row['photo_url'] as String?,
      myRole: myRole,
      ovulationUncertainty: uncert,
    );
  }

  String get initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1).toUpperCase();
  }

  bool isOwnedBy(String? userId) => userId != null && ownerId == userId;

  /// Czy bieżący user może edytować cykle tego profilu.
  /// Owner — zawsze tak. Share-receiver — tylko jeśli ma rolę `editor`.
  bool canEdit(String? userId) {
    if (isOwnedBy(userId)) return true;
    return myRole == ShareRole.editor;
  }

  /// Helper do serializacji roli na string SQL.
  static ShareRole? parseRole(String? raw) {
    if (raw == 'editor') return ShareRole.editor;
    if (raw == 'viewer') return ShareRole.viewer;
    return null;
  }

  static String roleToSql(ShareRole role) =>
      role == ShareRole.editor ? 'editor' : 'viewer';
}

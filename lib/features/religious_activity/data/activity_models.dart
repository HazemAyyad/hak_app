enum PersonalEntityKind { group, dhikr, session, habit, khatma, tasbih }

enum TasbihStyle { buttons, fullscreen, circular, horizontal, classic, digital }

enum DhikrReadingMode { cards, list, focus }

enum ActivityKind { count, undo, complete, reset, habit, quranPage, breathing }

String activityUuid(String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value)) {
    throw const FormatException('Invalid activity identifier');
  }
  return value.toLowerCase();
}

String activitySubject(String value) {
  if (!RegExp(r'^[a-z0-9][a-z0-9:_-]{0,119}$').hasMatch(value)) {
    throw const FormatException('Invalid content identifier');
  }
  return value;
}

String activityDate(String value) {
  final date = DateTime.tryParse(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      date == null ||
      date.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid local date');
  }
  return value;
}

DateTime _instant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid activity time');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String() != value) {
    throw const FormatException('Invalid activity time');
  }
  return parsed;
}

String _text(Object? value, int max, {bool empty = false}) {
  if (value is! String ||
      value.length > max ||
      !empty && value.trim().isEmpty) {
    throw const FormatException('Invalid text');
  }
  return value.trim();
}

int _number(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw const FormatException('Invalid integer');
  }
  return value;
}

sealed class PersonalEntity {
  PersonalEntity(String id) : id = activityUuid(id);
  final String id;
  PersonalEntityKind get kind;
  String get key => '${kind.name}:$id';
  Map<String, dynamic> toJson();

  static PersonalEntity fromJson(
    PersonalEntityKind kind,
    Map<String, dynamic> data,
  ) => switch (kind) {
    PersonalEntityKind.group => PersonalDhikrGroup.fromJson(data),
    PersonalEntityKind.dhikr => PersonalDhikr.fromJson(data),
    PersonalEntityKind.session => DhikrSession.fromJson(data),
    PersonalEntityKind.habit => ReligiousHabit.fromJson(data),
    PersonalEntityKind.khatma => QuranKhatma.fromJson(data),
    PersonalEntityKind.tasbih => PersonalTasbih.fromJson(data),
  };
}

class PersonalDhikrGroup extends PersonalEntity {
  PersonalDhikrGroup({
    required String id,
    required String title,
    List<String> itemIds = const [],
    int order = 0,
  }) : title = _text(title, 160),
       itemIds = List.unmodifiable(itemIds.map(activitySubject)),
       order = _number(order, 0, 1000000),
       super(id) {
    if (itemIds.length > 1000 || itemIds.toSet().length != itemIds.length) {
      throw const FormatException('Invalid group membership');
    }
  }
  final String title;
  final List<String> itemIds;
  final int order;
  @override
  PersonalEntityKind get kind => PersonalEntityKind.group;
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'item_ids': itemIds,
    'sort_order': order,
  };
  factory PersonalDhikrGroup.fromJson(Map<String, dynamic> data) =>
      PersonalDhikrGroup(
        id: data['id'] as String,
        title: _text(data['title'], 160),
        itemIds: List<String>.from(data['item_ids'] as List),
        order: _number(data['sort_order'], 0, 1000000),
      );
}

class PersonalDhikr extends PersonalEntity {
  PersonalDhikr({
    required String id,
    required String text,
    required int target,
    String source = '',
    String preface = '',
  }) : text = _text(text, 10000),
       target = _number(target, 1, 1000000),
       source = _text(source, 500, empty: true),
       preface = _text(preface, 500, empty: true),
       super(id);
  final String text, source, preface;
  final int target;
  @override
  PersonalEntityKind get kind => PersonalEntityKind.dhikr;
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'target': target,
    'source': source,
    if (preface.isNotEmpty) 'preface': preface,
  };
  factory PersonalDhikr.fromJson(Map<String, dynamic> data) => PersonalDhikr(
    id: data['id'] as String,
    text: _text(data['text'], 10000),
    target: _number(data['target'], 1, 1000000),
    source: _text(data['source'], 500, empty: true),
    preface: _text(data['preface'] ?? '', 500, empty: true),
  );
}

class DhikrSession extends PersonalEntity {
  DhikrSession({
    required String id,
    required String groupId,
    required String day,
    required String epoch,
    required Map<String, int> targets,
    required this.mode,
    required String catalogVersion,
    this.autoAdvance = false,
    int cursor = 0,
  }) : groupId = activitySubject(groupId),
       day = activityDate(day),
       epoch = activityUuid(epoch),
       targets = Map.unmodifiable(
         targets.map(
           (key, value) =>
               MapEntry(activitySubject(key), _number(value, 1, 1000000)),
         ),
       ),
       catalogVersion = _text(catalogVersion, 80),
       cursor = _number(cursor, 0, targets.length - 1),
       super(id) {
    if (targets.isEmpty || targets.length > 1000) {
      throw const FormatException('Invalid session targets');
    }
  }
  final String groupId, day, epoch, catalogVersion;
  final Map<String, int> targets;
  final DhikrReadingMode mode;
  final bool autoAdvance;
  final int cursor;
  @override
  PersonalEntityKind get kind => PersonalEntityKind.session;
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'day': day,
    'epoch': epoch,
    'targets': targets,
    'mode': mode.name,
    'catalog_version': catalogVersion,
    'auto_advance': autoAdvance,
    'cursor': cursor,
  };
  factory DhikrSession.fromJson(Map<String, dynamic> data) => DhikrSession(
    id: data['id'] as String,
    groupId: data['group_id'] as String,
    day: data['day'] as String,
    epoch: data['epoch'] as String,
    targets: Map<String, int>.from(data['targets'] as Map),
    mode: DhikrReadingMode.values.byName(data['mode'] as String),
    catalogVersion: data['catalog_version'] as String,
    autoAdvance: data['auto_advance'] as bool,
    cursor: _number(data['cursor'], 0, 999),
  );
}

class ReligiousHabit extends PersonalEntity {
  ReligiousHabit({
    required String id,
    required String title,
    required List<int> weekdays,
    int target = 1,
    this.enabled = true,
    this.icon,
    String? epoch,
  }) : title = _text(title, 160),
       weekdays = List.unmodifiable(
         weekdays.map((value) => _number(value, 1, 7)),
       ),
       target = _number(target, 1, 1000000),
       epoch = epoch == null ? null : activityUuid(epoch),
       super(id) {
    if (icon != null && !habitIcons.contains(icon)) {
      throw const FormatException('Invalid habit icon');
    }
    if (weekdays.isEmpty || weekdays.toSet().length != weekdays.length) {
      throw const FormatException('Invalid habit days');
    }
  }
  final String title;
  final List<int> weekdays;
  final int target;
  final bool enabled;
  static const habitIcons = [
    'book',
    'beads',
    'moon',
    'sun',
    'heart',
    'water',
    'learn',
    'give',
    'prayer',
    'activity',
    'sleep',
    'read',
  ];
  final String? icon, epoch;
  String get activeEpoch => epoch ?? id;
  @override
  PersonalEntityKind get kind => PersonalEntityKind.habit;
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'weekdays': weekdays,
    'target': target,
    'enabled': enabled,
    if (icon != null) 'icon': icon,
    if (epoch != null) 'epoch': epoch,
  };
  factory ReligiousHabit.fromJson(Map<String, dynamic> data) => ReligiousHabit(
    id: data['id'] as String,
    title: _text(data['title'], 160),
    weekdays: List<int>.from(data['weekdays'] as List),
    target: _number(data['target'], 1, 1000000),
    enabled: data['enabled'] as bool,
    icon: data['icon'] as String?,
    epoch: data['epoch'] as String?,
  );
}

class QuranKhatma extends PersonalEntity {
  QuranKhatma({
    required String id,
    required String title,
    required String startDate,
    required String endDate,
    int firstPage = 1,
    int lastPage = 604,
    String? epoch,
    this.archived,
    int? reminderMinutes,
  }) : title = _text(title, 160),
       startDate = activityDate(startDate),
       endDate = activityDate(endDate),
       firstPage = _number(firstPage, 1, 604),
       lastPage = _number(lastPage, firstPage, 604),
       epoch = epoch == null ? null : activityUuid(epoch),
       reminderMinutes = reminderMinutes == null
           ? null
           : _number(reminderMinutes, 0, 1439),
       super(id) {
    if (this.endDate.compareTo(this.startDate) < 0) {
      throw const FormatException('Invalid khatma dates');
    }
  }
  final String title, startDate, endDate;
  final int firstPage, lastPage;
  final String? epoch;
  final bool? archived;
  final int? reminderMinutes;
  String get activeEpoch => epoch ?? id;
  @override
  PersonalEntityKind get kind => PersonalEntityKind.khatma;
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start_date': startDate,
    'end_date': endDate,
    'first_page': firstPage,
    'last_page': lastPage,
    if (epoch != null) 'epoch': epoch,
    if (archived != null) 'archived': archived,
    if (reminderMinutes != null) 'reminder_minutes': reminderMinutes,
  };
  factory QuranKhatma.fromJson(Map<String, dynamic> data) => QuranKhatma(
    id: data['id'] as String,
    title: _text(data['title'], 160),
    startDate: data['start_date'] as String,
    endDate: data['end_date'] as String,
    firstPage: _number(data['first_page'], 1, 604),
    lastPage: _number(data['last_page'], 1, 604),
    epoch: data['epoch'] as String?,
    archived: data['archived'] as bool?,
    reminderMinutes: data['reminder_minutes'] as int?,
  );
}

class PersonalTasbih extends PersonalEntity {
  PersonalTasbih({
    required String id,
    required String text,
    required int goal,
    required String epoch,
    String benefit = '',
    this.style = TasbihStyle.classic,
    int order = 0,
  }) : text = _text(text, 1000),
       benefit = _text(benefit, 2000, empty: true),
       goal = _number(goal, 1, 1000000),
       epoch = activityUuid(epoch),
       order = _number(order, 0, 1000000),
       super(id);
  final String text, benefit, epoch;
  final int goal, order;
  final TasbihStyle style;
  @override
  PersonalEntityKind get kind => PersonalEntityKind.tasbih;
  PersonalTasbih copyWith({
    String? text,
    String? benefit,
    String? epoch,
    int? goal,
    TasbihStyle? style,
  }) => PersonalTasbih(
    id: id,
    text: text ?? this.text,
    benefit: benefit ?? this.benefit,
    epoch: epoch ?? this.epoch,
    goal: goal ?? this.goal,
    style: style ?? this.style,
    order: order,
  );
  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'benefit': benefit,
    'goal': goal,
    'epoch': epoch,
    'style': style.name,
    'sort_order': order,
  };
  factory PersonalTasbih.fromJson(Map<String, dynamic> data) => PersonalTasbih(
    id: data['id'] as String,
    text: _text(data['text'], 1000),
    benefit: _text(data['benefit'], 2000, empty: true),
    goal: _number(data['goal'], 1, 1000000),
    epoch: data['epoch'] as String,
    style: TasbihStyle.values.byName(data['style'] as String),
    order: _number(data['sort_order'], 0, 1000000),
  );
}

class ReligiousActivityEvent {
  ReligiousActivityEvent({
    required String id,
    required String deviceId,
    required String sessionId,
    required String subjectId,
    required String epoch,
    required this.kind,
    required int amount,
    required DateTime occurredAt,
    required String day,
    required int utcOffsetMinutes,
    String? reverses,
  }) : id = activityUuid(id),
       deviceId = activityUuid(deviceId),
       sessionId = activityUuid(sessionId),
       subjectId = activitySubject(subjectId),
       epoch = activityUuid(epoch),
       amount = _number(
         amount,
         0,
         kind == ActivityKind.quranPage ? 604 : 1000000,
       ),
       occurredAt = DateTime.fromMillisecondsSinceEpoch(
         occurredAt.millisecondsSinceEpoch,
         isUtc: true,
       ),
       day = activityDate(day),
       utcOffsetMinutes = _number(utcOffsetMinutes, -840, 840),
       reverses = reverses == null ? null : activityUuid(reverses) {
    if ((kind == ActivityKind.undo) != (reverses != null) ||
        this.reverses == this.id ||
        ({
              ActivityKind.undo,
              ActivityKind.complete,
              ActivityKind.reset,
            }.contains(kind)
            ? amount != 0
            : amount < 1)) {
      throw const FormatException('Invalid activity event');
    }
  }
  final String id, deviceId, sessionId, subjectId, epoch, day;
  final String? reverses;
  final ActivityKind kind;
  final int amount, utcOffsetMinutes;
  final DateTime occurredAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'device_id': deviceId,
    'session_id': sessionId,
    'subject_id': subjectId,
    'epoch': epoch,
    'kind': kind.name,
    'amount': amount,
    'occurred_at': occurredAt.toIso8601String(),
    'day': day,
    'utc_offset_minutes': utcOffsetMinutes,
    'reverses': reverses,
  };
  factory ReligiousActivityEvent.fromJson(Map<String, dynamic> data) =>
      ReligiousActivityEvent(
        id: data['id'] as String,
        deviceId: data['device_id'] as String,
        sessionId: data['session_id'] as String,
        subjectId: data['subject_id'] as String,
        epoch: data['epoch'] as String,
        kind: ActivityKind.values.byName(data['kind'] as String),
        amount: _number(data['amount'], 0, 1000000),
        occurredAt: _instant(data['occurred_at']),
        day: data['day'] as String,
        utcOffsetMinutes: _number(data['utc_offset_minutes'], -840, 840),
        reverses: data['reverses'] as String?,
      );
}

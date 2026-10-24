import '../../quran/data/quran_sync.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import 'adhkar_repository.dart';

String adhkarDigits(String text) {
  const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  return text.split('').map((c) {
    final index = arabic.indexOf(c), other = persian.indexOf(c);
    return index >= 0
        ? '$index'
        : other >= 0
        ? '$other'
        : c;
  }).join();
}

class PersonalAdhkar {
  PersonalAdhkar(this.activity) : scope = activity.scope;
  final ReligiousActivityController activity;
  final String scope;
  void _owner() {
    if (activity.scope != scope) throw StateError('Account changed');
  }

  Future<void> saveDhikr({
    String? id,
    required String text,
    required String target,
    String source = '',
    String preface = '',
  }) async {
    _owner();
    final number = int.tryParse(adhkarDigits(target).trim());
    if (number == null) throw const FormatException('Invalid count');
    await activity.store.save(
      scope,
      PersonalDhikr(
        id: id ?? operationId(),
        text: text,
        target: number,
        source: source,
        preface: preface,
      ),
    );
    activity.changed(scope);
  }

  Future<void> saveGroup({
    String? id,
    required String title,
    required List<String> items,
    int? order,
  }) async {
    _owner();
    final groups = (await activity.store.entities(
      scope,
      kind: PersonalEntityKind.group,
    )).whereType<PersonalDhikrGroup>().toList();
    _owner();
    await activity.store.save(
      scope,
      PersonalDhikrGroup(
        id: id ?? operationId(),
        title: title,
        itemIds: items,
        order:
            order ??
            groups.fold<int>(0, (v, g) => g.order >= v ? g.order + 1 : v),
      ),
    );
    activity.changed(scope);
  }

  Future<void> deleteDhikr(String id) async {
    _owner();
    final key = 'dhikr:${activityUuid(id)}';
    final groups = (await activity.store.entities(
      scope,
      kind: PersonalEntityKind.group,
    )).whereType<PersonalDhikrGroup>();
    _owner();
    await activity.store.apply(
      scope,
      deletes: [key],
      upserts: [
        for (final group in groups.where((g) => g.itemIds.contains(key)))
          PersonalDhikrGroup(
            id: group.id,
            title: group.title,
            itemIds: group.itemIds.where((i) => i != key).toList(),
            order: group.order,
          ),
      ],
    );
    activity.changed(scope);
  }

  Future<void> deleteGroup(String id) async {
    _owner();
    if (id == AdhkarRepository.savedGroupId) {
      throw ArgumentError('Saved group is reserved');
    }
    await activity.store.remove(scope, PersonalEntityKind.group, id);
    activity.changed(scope);
  }

  Future<void> reorderGroups(List<PersonalDhikrGroup> groups) async {
    _owner();
    await activity.store.apply(
      scope,
      upserts: [
        for (var i = 0; i < groups.length; i++)
          PersonalDhikrGroup(
            id: groups[i].id,
            title: groups[i].title,
            itemIds: groups[i].itemIds,
            order: i,
          ),
      ],
    );
    activity.changed(scope);
  }

  Future<void> toggleSaved(String itemId) async {
    _owner();
    await activity.store.updateGroup(scope, AdhkarRepository.savedGroupId, (
      group,
    ) {
      final ids = [...?group?.itemIds];
      if (!ids.remove(itemId)) ids.add(itemId);
      return PersonalDhikrGroup(
        id: AdhkarRepository.savedGroupId,
        title: 'الأذكار المحفوظة',
        itemIds: ids,
      );
    });
    activity.changed(scope);
  }
}

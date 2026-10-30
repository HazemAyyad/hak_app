import 'package:flutter/widgets.dart';
import '../../../core/localization/app_localization.dart';

String accountPendingChanges(BuildContext context, int count) =>
    LocalizationScope.maybeOf(
      context,
    )?.pluralText('account.pendingChanges', count) ??
    '$count تغييرات بانتظار المزامنة';

String accountBackupCounts(BuildContext context, int personal, int events) {
  final localization = LocalizationScope.maybeOf(context);
  if (localization == null) {
    return '$personal عناصر شخصية • $events عمليات في السجل';
  }
  return localization.text(
    'account.backupCounts',
    args: {
      'personal': localization.pluralText('account.personalItems', personal),
      'events': localization.pluralText('account.activityEntries', events),
    },
  );
}

String accountBackupDate(BuildContext context, DateTime date) {
  final localization = LocalizationScope.maybeOf(context);
  final value =
      localization?.formats.gregorianDateTime(date.toLocal()) ??
      date.toLocal().toString().substring(0, 16);
  return localization?.text('account.backupDate', args: {'date': value}) ??
      'تاريخ النسخة: $value';
}

String accountLastSync(BuildContext context, String timestamp) {
  final localization = LocalizationScope.maybeOf(context);
  final date = DateTime.tryParse(timestamp);
  final value = date != null && localization != null
      ? localization.formats.gregorianDateTime(date.toLocal())
      : timestamp.replaceAll('T', ' ');
  return localization?.text('account.lastSync', args: {'date': value}) ??
      'آخر مزامنة: $value';
}

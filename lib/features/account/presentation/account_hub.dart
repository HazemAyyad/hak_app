import '../../../core/localization/ui_text.dart';
import 'account_labels.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../sharing/share_card.dart';
import '../../quran/presentation/quran_account.dart';
import '../../quran/presentation/quran_widgets.dart';
import '../../quran/data/quran_sync.dart';
import '../../religious_content/data/religious_controller.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../data/google_account.dart';
import '../data/haq_backup.dart';
import '../../../app_appearance.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/language_page.dart';
import '../../admin/presentation/admin_page.dart';
import '../data/app_session.dart';
import 'app_account_page.dart';

class AccountHubPage extends StatelessWidget {
  const AccountHubPage({
    super.key,
    required this.controller,
    this.beforeBackup,
    this.onRestored,
    this.appSession,
  });
  final ReligiousController controller;
  final AppSession? appSession;
  final Future<void> Function()? beforeBackup, onRestored;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.of(context).tealHeading,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.of(context).tealHeading,
        ),
      ),
    ),
    child: ListenableBuilder(
      listenable: controller.quran.account,
      builder: (context, _) => QuranAccountPage(
        controller: controller.quran,
        details: Column(
          children: [
            if (appSession != null) _AppAccessPanel(session: appSession!),
            FutureBuilder<ReligiousActivityController>(
              future: controller.activity,
              builder: (context, result) {
                if (result.hasError) {
                  return Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      context.accountLabel(
                        'تعذّر فتح بيانات النشاط؛ أعد فتح الصفحة للمحاولة.',
                      ),
                    ),
                  );
                }
                if (!result.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _AccountTools(
                  key: ValueKey(result.data!.scope),
                  controller: controller,
                  activity: result.data!,
                  beforeBackup: beforeBackup,
                  onRestored: onRestored,
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppAccessPanel extends StatelessWidget {
  const _AppAccessPanel({required this.session});
  final AppSession session;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (session.profile == null && session.religious.profile == null)
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AppAccountPage(session: session),
                  ),
                ),
                icon: const Icon(Icons.account_circle_outlined),
                label: Text(context.tr('account.login')),
              ),
            if (session.profile != null) ...[
              Text(
                session.profile?['name'] as String? ??
                    context.tr('account.title'),
              ),
              Text(
                context.tr(
                  session.areas.length == 2
                      ? 'account.both'
                      : session.areas.contains('association')
                      ? 'account.associationOnly'
                      : 'account.religiousOnly',
                ),
              ),
              if (session.areas.contains('association'))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(context.tr('account.associationPending')),
                ),
              if (session.admin)
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AdminPage(session: session),
                    ),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(context.tr('admin.title')),
                ),
              if (!session.verified)
                TextButton(
                  onPressed: session.refresh,
                  child: Text(context.tr('common.retry')),
                ),
              if (session.verified && session.areas.length == 1)
                OutlinedButton(
                  onPressed: session.busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                AppAccountPage(session: session, link: true),
                          ),
                        ),
                  child: Text(context.tr('account.link')),
                ),
              TextButton(
                onPressed: session.busy ? null : session.logout,
                child: Text(context.tr('account.logout')),
              ),
            ],
            if (session.error != null) Text(context.tr(session.error!)),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const LanguagePage()),
              ),
              icon: const Icon(Icons.language),
              label: Text(context.tr('language.title')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AccountTools extends StatefulWidget {
  const _AccountTools({
    super.key,
    required this.controller,
    required this.activity,
    this.beforeBackup,
    this.onRestored,
  });
  final ReligiousController controller;
  final ReligiousActivityController activity;
  final Future<void> Function()? beforeBackup, onRestored;
  @override
  State<_AccountTools> createState() => _AccountToolsState();
}

class _AccountToolsState extends State<_AccountTools> {
  bool working = false;
  String? message;
  int pending = 0, personal = 0;
  late final backup = HaqBackup(widget.activity, widget.controller);
  String get scope => widget.activity.scope;
  QuranAccount get account => widget.controller.quran.account;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final captured = scope;
    final p = await widget.activity.store.pendingPersonal(captured);
    final events = await widget.activity.store.events(
      captured,
      pendingOnly: true,
    );
    if (mounted && scope == captured) {
      setState(() {
        pending = events.length;
        personal = p.length;
      });
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    if (working) return;
    setState(() {
      working = true;
      message = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException
              ? e.message.toString()
              : context.accountLabel(
                  'تعذّر إكمال العملية. بياناتك المحلية محفوظة؛ حاول مجددًا.',
                ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => working = false);
        await _refresh();
      }
    }
  }

  Future<void> _export() => _run(() async {
    await widget.beforeBackup?.call();
    final archive = await backup.capture();
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox;
    final result = await SharePlus.instance.share(
      ShareParams(
        title: 'نسخة حق الاحتياطية',
        text: ShareCardContent.signature,
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(archive.encode())),
            mimeType: 'application/json',
            name: 'haq-${DateTime.now().millisecondsSinceEpoch}.json',
          ),
        ],
        fileNameOverrides: ['haq-backup.json'],
        sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    if (mounted) {
      setState(
        () => message = result.status == ShareResultStatus.dismissed
            ? context.accountLabel('أُغلقت نافذة مشاركة النسخة.')
            : context.accountLabel(
                'أُعدّت النسخة وأُرسلت لواجهة الحفظ أو المشاركة.',
              ),
      );
    }
  });
  Future<void> _import() => _run(() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'نسخة حق',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (picked == null) return;
    if (await picked.length() > HaqBackupArchive.maxBytes) {
      throw const FormatException('الملف يتجاوز 8 ميغابايت');
    }
    final archive = HaqBackupArchive.decode(await picked.readAsString());
    backup.validate(archive);
    if (!mounted) return;
    bool replace = false;
    final selectedScope = scope;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(context.accountLabel('معاينة النسخة')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(accountBackupDate(context, archive.created)),
                Text(
                  accountBackupCounts(
                    context,
                    archive.personal.length,
                    archive.events.length,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.accountLabel('استبدال المحفوظات والإعدادات'),
                  ),
                  value: replace,
                  onChanged: (v) => update(() => replace = v),
                ),
                Text(
                  replace
                      ? context.accountLabel(
                          'ستُستبدل المفضلة والتقدم والعناصر الشخصية والإعدادات. يبقى سجل النشاط ويُدمج دون تكرار.',
                        )
                      : context.accountLabel(
                          'تُضاف العناصر غير الموجودة. تبقى تعديلاتك الحالية والعناصر المحذوفة من الحساب.',
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.accountLabel(
                    'تُستعاد الإعدادات والموقع المختار أيضًا. أذونات الجهاز والتنزيلات وتسجيل الدخول تبقى مستقلة.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.accountLabel('إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.accountLabel('تأكيد الاستعادة')),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted || scope != selectedScope) return;
    await widget.beforeBackup?.call();
    await backup.restore(archive, replace: replace);
    try {
      await widget.onRestored?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => message = context.accountLabel(
            'تمت استعادة البيانات. تعذّر تحديث التنبيهات؛ راجع إعداداتها.',
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(
        () => message = context.accountLabel(
          'تمت الاستعادة على هذا الجهاز. راجع حالة المزامنة أدناه.',
        ),
      );
    }
  });
  Future<void> _edit() async {
    final username = TextEditingController(
          text: account.profile?['username'] as String? ?? '',
        ),
        name = TextEditingController(
          text: account.profile?['name'] as String? ?? '',
        );
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.accountLabel('إعدادات الحساب')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: context.accountLabel('الاسم'),
              ),
            ),
            TextField(
              controller: username,
              maxLength: 30,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.accountLabel('اسم المستخدم'),
                helperText: context.accountLabel(
                  '7–30 حرفًا أو رقمًا، يبدأ بحرف إنجليزي',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.accountLabel('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.accountLabel('حفظ')),
          ),
        ],
      ),
    );
    if (save == true && mounted) {
      await _run(() async {
        final done = await account.updateProfile(username.text, name.text);
        if (mounted) {
          setState(
            () => message = done
                ? context.accountLabel('تم حفظ الحساب')
                : account.error,
          );
        }
      });
    }
    username.dispose();
    name.dispose();
  }

  Future<void> _link() => _run(() async {
    final token = await HaqGoogleAccount.token(fresh: true);
    if (token != null) {
      final done = await account.google(token, link: true);
      if (mounted) {
        setState(
          () => message = done
              ? context.accountLabel('تم ربط حساب Google')
              : account.error,
        );
      }
    }
  });
  Future<void> _delete() async {
    final password = TextEditingController(),
        confirmation = TextEditingController();
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.accountLabel('حذف حساب حق')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.accountLabel(
                  'سيُحذف الحساب وبياناته السحابية نهائيًا. صدّر نسخة أولًا إذا احتجتها. تبقى النسخة المحلية معزولة على هذا الجهاز ولا تُنقل للضيف. حذف حساب حق لا يلغي تجديد اشتراك المتجر؛ ألغِ التجديد من إعدادات اشتراكات Google Play أو Apple قبل الحذف إذا أردت إيقاف الدفع.',
                ),
              ),
              if (account.profile?['password_enabled'] != false)
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.accountLabel('كلمة المرور'),
                  ),
                ),
              TextField(
                controller: confirmation,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.accountLabel('اكتب DELETE للتأكيد'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.accountLabel('إلغاء')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, confirmation.text == 'DELETE'),
            child: Text(context.accountLabel('حذف الحساب نهائيًا')),
          ),
        ],
      ),
    );
    if (agreed == true && mounted) {
      await _run(() async {
        String? token;
        if (account.profile?['password_enabled'] == false) {
          token = await HaqGoogleAccount.token(fresh: true);
          if (token == null) return;
        }
        final done = await account.deleteAccount(
          password: password.text,
          googleToken: token,
        );
        if (mounted) {
          setState(
            () => message = done
                ? context.accountLabel('تم حذف الحساب والعودة لبيانات الضيف')
                : account.error,
          );
        }
      });
    }
    password.dispose();
    confirmation.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([account, widget.controller, widget.activity]),
    builder: (context, _) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.accountLabel('حالة بياناتك'),
                  style: qText(context, size: 19, weight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _status(
                  context.accountLabel('القرآن'),
                  account.ledger.pending.length,
                  account.error,
                  account.syncing,
                ),
                _status(
                  context.accountLabel('المحتوى والمفضلة'),
                  widget.controller.ledger.pending.length,
                  widget.controller.syncError,
                  widget.controller.syncing,
                ),
                _status(
                  context.accountLabel('الأذكار والعادات والختمة والسجل'),
                  pending + personal,
                  widget.activity.syncError,
                  false,
                ),
                if (account.profile == null)
                  Text(
                    context.accountLabel(
                      'بيانات ضيف على هذا الجهاز. إنشاء حساب اختياري للمزامنة.',
                    ),
                    style: qText(context, size: 12),
                  ),
                const SizedBox(height: 10),
                QPrimaryButton(
                  label: working
                      ? context.accountLabel('جارٍ التنفيذ…')
                      : context.accountLabel('مزامنة جميع الأقسام'),
                  icon: Icons.sync,
                  onTap: working || account.token == null
                      ? null
                      : () => _run(() async {
                          await account.sync();
                          await widget.controller.sync();
                          await widget.activity.sync();
                        }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          QCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.accountLabel('النسخ الاحتياطي والاستعادة'),
                  style: qText(context, size: 19, weight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  context.accountLabel(
                    'نسخة خاصة بمحفوظاتك وتقدمك وسجل نشاطك وإعداداتك، بما فيها الموقع المختار. الملف غير مشفّر؛ احفظه في مكان خاص. كلمات المرور ورموز الدخول والتنزيلات لا تُضمّن.',
                  ),
                  style: qText(context, size: 13),
                ),
                const SizedBox(height: 14),
                QPrimaryButton(
                  label: context.accountLabel('أخذ نسخة احتياطية'),
                  icon: Icons.backup_outlined,
                  onTap: working ? null : _export,
                ),
                OutlinedButton.icon(
                  onPressed: working ? null : _import,
                  icon: const Icon(Icons.restore),
                  label: Text(context.accountLabel('اختيار نسخة للاستعادة')),
                ),
              ],
            ),
          ),
          if (account.profile != null && !account.sessionExpired) ...[
            const SizedBox(height: 14),
            QCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: working ? null : _edit,
                    icon: const Icon(Icons.person_outline),
                    label: Text(
                      account.profile?['username'] == null
                          ? context.accountLabel('إكمال اسم المستخدم')
                          : context.accountLabel('الاسم واسم المستخدم'),
                    ),
                  ),
                  if (HaqGoogleAccount.configured &&
                      account.googleAvailable &&
                      account.profile?['google_linked'] != true)
                    TextButton(
                      onPressed: working ? null : _link,
                      child: Text(context.accountLabel('ربط حساب Google')),
                    ),
                  TextButton(
                    onPressed: working ? null : _delete,
                    child: Text(
                      context.accountLabel('حذف حساب حق'),
                      style: TextStyle(
                        color: AppPalette.of(context).dark
                            ? const Color(0xFFFFAAAA)
                            : const Color(0xFFAB3838),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (working)
            Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                context.accountLabel(message!),
                style: qText(context, size: 13),
              ),
            ),
        ],
      ),
    ),
  );
  Widget _status(String title, int count, String? error, bool syncing) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              syncing
                  ? Icons.sync
                  : error != null
                  ? Icons.cloud_off_outlined
                  : Icons.folder_outlined,
              color: AppPalette.of(context).tealHeading,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.accountLabel(title),
                    style: qText(context, size: 14, weight: FontWeight.w700),
                  ),
                  Text(
                    account.profile == null
                        ? context.accountLabel('محفوظ محليًا')
                        : error != null
                        ? context.accountLabel(error)
                        : (syncing
                              ? context.accountLabel('جارٍ المزامنة…')
                              : accountPendingChanges(context, count)),
                    style: qText(context, size: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

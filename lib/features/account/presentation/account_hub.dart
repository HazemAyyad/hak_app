import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../quran/presentation/quran_account.dart';
import '../../quran/presentation/quran_widgets.dart';
import '../../quran/data/quran_sync.dart';
import '../../religious_content/data/religious_controller.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../data/google_account.dart';
import '../data/haq_backup.dart';
import '../../../app_appearance.dart';

class AccountHubPage extends StatelessWidget {
  const AccountHubPage({
    super.key,
    required this.controller,
    this.beforeBackup,
    this.onRestored,
  });
  final ReligiousController controller;
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
        details: FutureBuilder<ReligiousActivityController>(
          future: controller.activity,
          builder: (context, result) {
            if (result.hasError) {
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'تعذّر فتح بيانات النشاط؛ أعد فتح الصفحة للمحاولة.',
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
              : 'تعذّر إكمال العملية. بياناتك المحلية محفوظة؛ حاول مجددًا.',
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
            ? 'أُغلقت نافذة مشاركة النسخة.'
            : 'أُعدّت النسخة وأُرسلت لواجهة الحفظ أو المشاركة.',
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
          title: const Text('معاينة النسخة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تاريخ النسخة: ${archive.created.toLocal().toString().substring(0, 16)}',
                ),
                Text(
                  '${archive.personal.length} عناصر شخصية • ${archive.events.length} عمليات في السجل',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('استبدال المحفوظات والإعدادات'),
                  value: replace,
                  onChanged: (v) => update(() => replace = v),
                ),
                Text(
                  replace
                      ? 'ستُستبدل المفضلة والتقدم والعناصر الشخصية والإعدادات. يبقى سجل النشاط ويُدمج دون تكرار.'
                      : 'تُضاف العناصر غير الموجودة. تبقى تعديلاتك الحالية والعناصر المحذوفة من الحساب.',
                ),
                const SizedBox(height: 10),
                const Text(
                  'تُستعاد الإعدادات والموقع المختار أيضًا. أذونات الجهاز والتنزيلات وتسجيل الدخول تبقى مستقلة.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد الاستعادة'),
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
          () => message =
              'تمت استعادة البيانات. تعذّر تحديث التنبيهات؛ راجع إعداداتها.',
        );
      }
      return;
    }
    if (mounted) {
      setState(
        () =>
            message = 'تمت الاستعادة على هذا الجهاز. راجع حالة المزامنة أدناه.',
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
        title: const Text('إعدادات الحساب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            TextField(
              controller: username,
              maxLength: 30,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'اسم المستخدم',
                helperText: '7–30 حرفًا أو رقمًا، يبدأ بحرف إنجليزي',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (save == true && mounted) {
      await _run(() async {
        final done = await account.updateProfile(username.text, name.text);
        if (mounted) {
          setState(() => message = done ? 'تم حفظ الحساب' : account.error);
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
        setState(() => message = done ? 'تم ربط حساب Google' : account.error);
      }
    }
  });
  Future<void> _delete() async {
    final password = TextEditingController(),
        confirmation = TextEditingController();
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف حساب حق'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'سيُحذف الحساب وبياناته السحابية نهائيًا. صدّر نسخة أولًا إذا احتجتها. تبقى النسخة المحلية معزولة على هذا الجهاز ولا تُنقل للضيف.',
              ),
              if (account.profile?['password_enabled'] != false)
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور'),
                ),
              TextField(
                controller: confirmation,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'اكتب DELETE للتأكيد',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, confirmation.text == 'DELETE'),
            child: const Text('حذف الحساب نهائيًا'),
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
                ? 'تم حذف الحساب والعودة لبيانات الضيف'
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
                  'حالة بياناتك',
                  style: qText(context, size: 19, weight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _status(
                  'القرآن',
                  account.ledger.pending.length,
                  account.error,
                  account.syncing,
                ),
                _status(
                  'المحتوى والمفضلة',
                  widget.controller.ledger.pending.length,
                  widget.controller.syncError,
                  widget.controller.syncing,
                ),
                _status(
                  'الأذكار والعادات والختمة والسجل',
                  pending + personal,
                  widget.activity.syncError,
                  false,
                ),
                if (account.profile == null)
                  Text(
                    'بيانات ضيف على هذا الجهاز. إنشاء حساب اختياري للمزامنة.',
                    style: qText(context, size: 12),
                  ),
                const SizedBox(height: 10),
                QPrimaryButton(
                  label: working ? 'جارٍ التنفيذ…' : 'مزامنة جميع الأقسام',
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
                  'النسخ الاحتياطي والاستعادة',
                  style: qText(context, size: 19, weight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'نسخة خاصة بمحفوظاتك وتقدمك وسجل نشاطك وإعداداتك، بما فيها الموقع المختار. الملف غير مشفّر؛ احفظه في مكان خاص. كلمات المرور ورموز الدخول والتنزيلات لا تُضمّن.',
                  style: qText(context, size: 13),
                ),
                const SizedBox(height: 14),
                QPrimaryButton(
                  label: 'أخذ نسخة احتياطية',
                  icon: Icons.backup_outlined,
                  onTap: working ? null : _export,
                ),
                OutlinedButton.icon(
                  onPressed: working ? null : _import,
                  icon: const Icon(Icons.restore),
                  label: const Text('اختيار نسخة للاستعادة'),
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
                          ? 'إكمال اسم المستخدم'
                          : 'الاسم واسم المستخدم',
                    ),
                  ),
                  if (HaqGoogleAccount.configured &&
                      account.googleAvailable &&
                      account.profile?['google_linked'] != true)
                    TextButton(
                      onPressed: working ? null : _link,
                      child: const Text('ربط حساب Google'),
                    ),
                  TextButton(
                    onPressed: working ? null : _delete,
                    child: Text(
                      'حذف حساب حق',
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
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(message!, style: qText(context, size: 13)),
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
                    title,
                    style: qText(context, size: 14, weight: FontWeight.w700),
                  ),
                  Text(
                    account.profile == null
                        ? 'محفوظ محليًا'
                        : error ??
                              (syncing
                                  ? 'جارٍ المزامنة…'
                                  : '$count تغييرات بانتظار المزامنة'),
                    style: qText(context, size: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

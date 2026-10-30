import '../../../core/localization/ui_text.dart';
import '../../account/presentation/account_labels.dart';
import 'package:flutter/material.dart';
import '../data/quran_controller.dart';
import 'quran_widgets.dart';
import '../../account/data/google_account.dart';

class QuranAccountPage extends StatefulWidget {
  const QuranAccountPage({super.key, required this.controller, this.details});
  final QuranController controller;
  final Widget? details;
  @override
  State<QuranAccountPage> createState() => _QuranAccountPageState();
}

class _QuranAccountPageState extends State<QuranAccountPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool register = false, mergeGuest = true, obscure = true;
  bool googleBusy = false;
  String? googleError;
  @override
  void initState() {
    super.initState();
    email.text = widget.controller.account.profile?['email'] as String? ?? '';
    widget.controller.account.capabilities();
  }

  Future<void> _google() async {
    final username = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.accountLabel('الدخول بحساب Google')),
        content: TextField(
          controller: username,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: context.accountLabel('اسم مستخدم للحساب الجديد'),
            helperText: context.accountLabel(
              '7–30 حرفًا إنجليزيًا أو رقمًا، يبدأ بحرف',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.accountLabel('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, username.text.trim()),
            child: Text(context.accountLabel('متابعة')),
          ),
        ],
      ),
    );
    username.dispose();
    if (value == null || !mounted) return;
    setState(() {
      googleBusy = true;
      googleError = null;
    });
    try {
      final token = await HaqGoogleAccount.token();
      if (token != null && mounted) {
        await widget.controller.account.google(
          token,
          username: value,
          mergeGuest: mergeGuest,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => googleError = context.accountLabel(
            'تعذّر فتح Google. تحقق من إعدادات الدخول وحاول مجددًا.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => googleBusy = false);
    }
  }

  Future<void> _recover() async {
    final address = TextEditingController(text: email.text),
        code = TextEditingController(),
        next = TextEditingController();
    String? notice;
    bool sent = false, working = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(context.accountLabel('استعادة كلمة المرور')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: address,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: context.accountLabel('البريد الإلكتروني'),
                  ),
                ),
                if (sent) ...[
                  TextField(
                    controller: code,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: context.accountLabel(
                        'رمز الاستعادة من البريد',
                      ),
                    ),
                  ),
                  TextField(
                    controller: next,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: context.accountLabel(
                        'كلمة مرور جديدة (10 أحرف على الأقل)',
                      ),
                    ),
                  ),
                ],
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(context.accountLabel(notice!)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(ctx),
              child: Text(context.accountLabel('إغلاق')),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      update(() => working = true);
                      final result = await widget.controller.account.recovery(
                        address.text,
                        code: sent ? code.text : null,
                        password: sent ? next.text : null,
                      );
                      if (!ctx.mounted) return;
                      update(() {
                        working = false;
                        notice = result ?? widget.controller.account.error;
                        if (result != null && !sent) sent = true;
                      });
                      if (result != null && sent && code.text.isNotEmpty) {
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
              child: Text(
                working
                    ? context.accountLabel('جارٍ الاتصال…')
                    : sent
                    ? context.accountLabel('تغيير كلمة المرور')
                    : context.accountLabel('إرسال رمز الاستعادة'),
              ),
            ),
          ],
        ),
      ),
    );
    address.dispose();
    code.dispose();
    next.dispose();
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.account,
    builder: (context, _) {
      final account = widget.controller.account;
      final creating = register && !account.sessionExpired;
      return ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          QuranHeader(
            title: context.accountLabel('الحساب والمزامنة'),
            subtitle: context.accountLabel('حسابك ومحفوظاتك ونسخك الاحتياطية'),
            onBack: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: QCard(
              child: account.profile != null && !account.sessionExpired
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.account_circle_outlined,
                          color: qAccent(context),
                          size: 52,
                        ),
                        Text(
                          account.profile!['name'] as String,
                          textAlign: TextAlign.center,
                          style: qText(context, size: 21),
                        ),
                        Text(
                          account.profile!['email'] as String,
                          textAlign: TextAlign.center,
                          style: qText(context, size: 13),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          account.syncing
                              ? context.accountLabel(
                                  'جارٍ مزامنة بيانات القرآن…',
                                )
                              : accountPendingChanges(
                                  context,
                                  account.ledger.pending.length,
                                ),
                          style: qText(context),
                        ),
                        if (account.lastSync != null)
                          Text(
                            accountLastSync(context, account.lastSync!),
                            style: qText(context, size: 12),
                          ),
                        if (account.profile!['username'] != null)
                          Text(
                            '@${account.profile!['username']}',
                            textAlign: TextAlign.center,
                            style: qText(context, size: 13),
                          ),
                        const SizedBox(height: 12),
                        QPrimaryButton(
                          label: context.accountLabel('مزامنة الآن'),
                          icon: Icons.sync,
                          onTap: account.syncing || account.busy
                              ? null
                              : account.sync,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.accountLabel(
                            'لكل حساب محفوظاته الخاصة. عند تعارض تعديلين يُعتمد الإصدار الأحدث الموجود على الحساب، وتبقى عمليات الحذف محفوظة.',
                          ),
                          style: qText(context, size: 12),
                        ),
                        TextButton(
                          onPressed: account.busy ? null : account.logout,
                          child: Text(
                            context.accountLabel(
                              'تسجيل الخروج والعودة لبيانات الضيف',
                            ),
                          ),
                        ),
                      ],
                    )
                  : Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            account.sessionExpired
                                ? context.accountLabel('تجديد جلسة الحساب')
                                : creating
                                ? context.accountLabel('إنشاء حساب')
                                : context.accountLabel('تسجيل الدخول'),
                            textAlign: TextAlign.center,
                            style: qText(
                              context,
                              size: 22,
                              weight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (account.sessionExpired)
                            Text(
                              context.accountLabel(
                                'بياناتك محفوظة. ادخل بنفس الحساب لاستكمال المزامنة، أو سجل الخروج للعودة للضيف.',
                              ),
                              style: qText(context, size: 13),
                            ),
                          if (creating)
                            TextFormField(
                              controller: name,
                              decoration: InputDecoration(
                                labelText: context.accountLabel('الاسم'),
                              ),
                              maxLength: 100,
                              validator: (v) => v!.trim().isEmpty
                                  ? context.accountLabel('أدخل الاسم')
                                  : null,
                            ),
                          TextFormField(
                            controller: email,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                              labelText: context.accountLabel(
                                'البريد الإلكتروني',
                              ),
                            ),
                            validator: (v) =>
                                RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(v!.trim())
                                ? null
                                : context.accountLabel('أدخل بريدًا صحيحًا'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: password,
                            obscureText: obscure,
                            textDirection: TextDirection.ltr,
                            autofillHints: [
                              creating
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: context.accountLabel('كلمة المرور'),
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => obscure = !obscure),
                                icon: Icon(
                                  obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                            validator: (v) => v!.length < (creating ? 10 : 1)
                                ? (creating
                                      ? context.accountLabel(
                                          'استخدم 10 أحرف على الأقل',
                                        )
                                      : context.accountLabel(
                                          'أدخل كلمة المرور',
                                        ))
                                : null,
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: mergeGuest,
                            onChanged: account.busy
                                ? null
                                : (v) => setState(() => mergeGuest = v!),
                            title: Text(
                              context.accountLabel(
                                'دمج محفوظات الضيف مع هذا الحساب',
                              ),
                              style: qText(context, size: 13),
                            ),
                            subtitle: Text(
                              context.accountLabel(
                                'تُضاف المحفوظات غير الموجودة، وتُحترم العناصر المحذوفة وإعدادات الحساب السابقة.',
                              ),
                              style: qText(context, size: 11),
                            ),
                          ),
                          QPrimaryButton(
                            label: account.busy
                                ? context.accountLabel('جارٍ الاتصال…')
                                : creating
                                ? context.accountLabel('إنشاء الحساب')
                                : context.accountLabel('تسجيل الدخول'),
                            icon: Icons.login,
                            onTap: account.busy
                                ? null
                                : () {
                                    if (form.currentState!.validate()) {
                                      account.authenticate(
                                        register: creating,
                                        name: name.text,
                                        email: email.text,
                                        password: password.text,
                                        mergeGuest: mergeGuest,
                                      );
                                    }
                                  },
                          ),
                          TextButton(
                            onPressed: account.busy || account.sessionExpired
                                ? null
                                : () => setState(() => register = !register),
                            child: Text(
                              register
                                  ? context.accountLabel(
                                      'لديك حساب؟ تسجيل الدخول',
                                    )
                                  : context.accountLabel('إنشاء حساب جديد'),
                            ),
                          ),
                          if (account.recoveryAvailable)
                            TextButton(
                              onPressed: account.busy ? null : _recover,
                              child: Text(
                                context.accountLabel('نسيت كلمة المرور؟'),
                              ),
                            ),
                          if (HaqGoogleAccount.configured &&
                              account.googleAvailable)
                            OutlinedButton.icon(
                              onPressed: account.busy || googleBusy
                                  ? null
                                  : _google,
                              icon: const Icon(Icons.account_circle_outlined),
                              label: Text(
                                googleBusy
                                    ? context.accountLabel('جارٍ فتح Google…')
                                    : context.accountLabel(
                                        'المتابعة باستخدام Google',
                                      ),
                              ),
                            ),
                          if (account.sessionExpired)
                            TextButton(
                              onPressed: account.busy ? null : account.logout,
                              child: Text(
                                context.accountLabel(
                                  'تسجيل الخروج والعودة للضيف',
                                ),
                              ),
                            ),
                          Text(
                            context.accountLabel(
                              'يمكنك قراءة القرآن وحفظ تقدمك كضيف دون إنشاء حساب.',
                            ),
                            textAlign: TextAlign.center,
                            style: qText(context, size: 12),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          if (account.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                context.accountLabel(account.error!),
                style: qText(context, size: 13, color: const Color(0xFFAB3838)),
              ),
            ),
          if (googleError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.accountLabel(googleError!),
                style: qText(context, size: 13),
              ),
            ),
          if (widget.details != null) widget.details!,
        ],
      );
    },
  );
}

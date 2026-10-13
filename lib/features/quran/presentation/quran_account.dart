import 'package:flutter/material.dart';
import '../data/quran_controller.dart';
import 'quran_widgets.dart';

class QuranAccountPage extends StatefulWidget {
  const QuranAccountPage({super.key, required this.controller});
  final QuranController controller;
  @override
  State<QuranAccountPage> createState() => _QuranAccountPageState();
}

class _QuranAccountPageState extends State<QuranAccountPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool register = false, mergeGuest = true, obscure = true;
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
      return ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          QuranHeader(
            title: 'الحساب والمزامنة',
            subtitle: 'المفضلة والعلامات وآخر قراءة',
            onBack: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: QCard(
              child: account.profile != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.account_circle_outlined,
                          color: qTeal,
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
                              ? 'جارٍ مزامنة بيانات القرآن…'
                              : '${account.ledger.pending.length} تغييرات بانتظار المزامنة',
                          style: qText(context),
                        ),
                        if (account.lastSync != null)
                          Text(
                            'آخر مزامنة: ${account.lastSync!.substring(0, 16).replaceAll('T', ' ')}',
                            style: qText(context, size: 12),
                          ),
                        const SizedBox(height: 12),
                        QPrimaryButton(
                          label: 'مزامنة الآن',
                          icon: Icons.sync,
                          onTap: account.syncing || account.busy
                              ? null
                              : account.sync,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لكل حساب محفوظاته الخاصة. عند تعارض تعديلين يُعتمد الإصدار الأحدث الموجود على الحساب، وتبقى عمليات الحذف محفوظة.',
                          style: qText(context, size: 12),
                        ),
                        TextButton(
                          onPressed: account.busy ? null : account.logout,
                          child: const Text(
                            'تسجيل الخروج والعودة لبيانات الضيف',
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
                            register ? 'إنشاء حساب' : 'تسجيل الدخول',
                            textAlign: TextAlign.center,
                            style: qText(
                              context,
                              size: 22,
                              weight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (register)
                            TextFormField(
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: 'الاسم',
                              ),
                              maxLength: 100,
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'أدخل الاسم' : null,
                            ),
                          TextFormField(
                            controller: email,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'البريد الإلكتروني',
                            ),
                            validator: (v) =>
                                RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(v!.trim())
                                ? null
                                : 'أدخل بريدًا صحيحًا',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: password,
                            obscureText: obscure,
                            textDirection: TextDirection.ltr,
                            autofillHints: [
                              register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
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
                            validator: (v) => v!.length < (register ? 10 : 1)
                                ? (register
                                      ? 'استخدم 10 أحرف على الأقل'
                                      : 'أدخل كلمة المرور')
                                : null,
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: mergeGuest,
                            onChanged: account.busy
                                ? null
                                : (v) => setState(() => mergeGuest = v!),
                            title: Text(
                              'دمج محفوظات الضيف مع هذا الحساب',
                              style: qText(context, size: 13),
                            ),
                            subtitle: Text(
                              'تُضاف المحفوظات غير الموجودة، وتُحترم العناصر المحذوفة وإعدادات الحساب السابقة.',
                              style: qText(context, size: 11),
                            ),
                          ),
                          QPrimaryButton(
                            label: account.busy
                                ? 'جارٍ الاتصال…'
                                : register
                                ? 'إنشاء الحساب'
                                : 'تسجيل الدخول',
                            icon: Icons.login,
                            onTap: account.busy
                                ? null
                                : () {
                                    if (form.currentState!.validate()) {
                                      account.authenticate(
                                        register: register,
                                        name: name.text,
                                        email: email.text,
                                        password: password.text,
                                        mergeGuest: mergeGuest,
                                      );
                                    }
                                  },
                          ),
                          TextButton(
                            onPressed: account.busy
                                ? null
                                : () => setState(() => register = !register),
                            child: Text(
                              register
                                  ? 'لديك حساب؟ تسجيل الدخول'
                                  : 'إنشاء حساب جديد',
                            ),
                          ),
                          Text(
                            'يمكنك قراءة القرآن وحفظ تقدمك كضيف دون إنشاء حساب.',
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
                account.error!,
                style: qText(context, size: 13, color: const Color(0xFFAB3838)),
              ),
            ),
        ],
      );
    },
  );
}

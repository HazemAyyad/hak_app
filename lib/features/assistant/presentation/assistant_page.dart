import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app_appearance.dart';
import '../../../app_refresh.dart';
import '../../../navigation/more_page.dart';
import '../../account/presentation/account_hub.dart';
import '../../religious_content/data/religious_controller.dart';
import '../data/assistant_controller.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({
    super.key,
    required this.religious,
    required this.controller,
    this.subscription = false,
  });
  final ReligiousController religious;
  final AssistantController controller;
  final bool subscription;
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  late String owner;
  String? credential;
  GlobalKey<NavigatorState> navigator = GlobalKey();
  AssistantController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    owner = c.scope;
    credential = c.quran.account.token;
    c.addListener(_owner);
    unawaited(c.load());
  }

  void _owner() {
    if (owner == c.scope && credential == c.quran.account.token) return;
    setState(() {
      owner = c.scope;
      credential = c.quran.account.token;
      navigator = GlobalKey();
    });
    unawaited(c.load());
  }

  @override
  void dispose() {
    c.removeListener(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!(await navigator.currentState?.maybePop() ?? false) &&
            context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Navigator(
        key: navigator,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => _AssistantBody(
            religious: widget.religious,
            c: c,
            subscription: widget.subscription,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  );
}

class _AssistantBody extends StatefulWidget {
  const _AssistantBody({
    required this.religious,
    required this.c,
    required this.subscription,
    required this.onBack,
  });
  final ReligiousController religious;
  final AssistantController c;
  final bool subscription;
  final VoidCallback onBack;
  @override
  State<_AssistantBody> createState() => _AssistantBodyState();
}

class _AssistantBodyState extends State<_AssistantBody>
    with WidgetsBindingObserver {
  final text = TextEditingController();
  AssistantController get c => widget.c;
  bool consent = false;
  String? localError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    text.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final question = text.text.trim();
    if (question.isEmpty || !consent) return;
    await c.send(question);
    if (mounted && c.pending == null && c.error == null) text.clear();
  }

  Future<void> external(String url) async {
    final uri = Uri.tryParse(url);
    try {
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('link');
      }
    } catch (_) {
      if (mounted) setState(() => localError = 'تعذّر فتح الرابط');
    }
  }

  Future<void> abandonPending() async {
    final scope = c.scope, credential = c.quran.account.token;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('إيقاف إعادة المحاولة؟'),
        content: const Text(
          'قد يكون السؤال وصل للخادم. سيبقى إيصال العملية واستهلاكها على حسابك؛ هذا الخيار يوقف المحاولة المحلية فقط. إرسال سؤال جديد قد يُحتسب طلبًا آخر.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        c.scope == scope &&
        c.quran.account.token == credential) {
      await c.forgetPending();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final p = AppPalette.of(context);
      final q = c.quota;
      final caps = c.capabilities;
      final showPaywall = widget.subscription || !c.active;
      return Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: AppRefreshRegion(
            onRefresh: c.load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                DirectoryHeader(
                  title: widget.subscription ? 'باكج حق' : 'المساعد',
                  subtitle: 'مصادر موثقة • شرح واضح',
                  onBack: widget.onBack,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (c.loading) const LinearProgressIndicator(),
                      if (!c.signedIn)
                        _AssistantCard(
                          child: Column(
                            children: [
                              Icon(Icons.lock_outline, size: 46, color: p.gold),
                              const SizedBox(height: 14),
                              const Text(
                                'سجّل الدخول للمتابعة',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'المساعد والباكج مرتبطان بحساب حق، ويمكنك متابعة الأقسام الأخرى كضيف.',
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => Scaffold(
                                          body: SafeArea(
                                            child: AccountHubPage(
                                              controller: widget.religious,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                child: const Text('تسجيل الدخول أو إنشاء حساب'),
                              ),
                            ],
                          ),
                        ),
                      if (c.signedIn) ...[
                        if (!c.enabled && !c.loading)
                          _AssistantCard(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.hourglass_top,
                                  color: p.gold,
                                  size: 40,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'المساعد غير متاح حاليًا',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'لم تُنفّذ عملية شراء. أعد المحاولة لاحقًا.',
                                ),
                                const SizedBox(height: 14),
                                OutlinedButton.icon(
                                  onPressed: c.load,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('إعادة المحاولة'),
                                ),
                              ],
                            ),
                          ),
                        if (c.enabled && showPaywall)
                          _AssistantCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(
                                  c.active
                                      ? Icons.verified_outlined
                                      : Icons.workspace_premium_outlined,
                                  color: p.gold,
                                  size: 52,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  c.active
                                      ? 'اشتراكك موثّق وسارٍ'
                                      : 'باكج المساعد',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '${caps?['monthly_limit'] ?? '—'} سؤالًا كل شهر خدمة، وبحد ${caps?['daily_limit'] ?? '—'} أسئلة يوميًا. الإجابات مرتبطة بمصادر مكتبة حق، مع عرض النص الأصلي والمصدر.',
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'الأسئلة مستقلة ولا تشمل فتاوى شخصية. تتجدد الحصة مع بداية شهر الخدمة، وقد يتوقف المساعد مؤقتًا عند حد الاستهلاك العام.',
                                ),
                                if (!c.active) ...[
                                  const SizedBox(height: 16),
                                  if (c.product != null) ...[
                                    Text(
                                      c.product!.title,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: p.tealHeading,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      c.product!.price,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (c.product!.description.isNotEmpty)
                                      Text(c.product!.description),
                                    const Text(
                                      'اشتراك يتجدد تلقائيًا وفق دورة وسعر المتجر. راجع شروط الدفع في نافذة المتجر قبل التأكيد، ويمكنك إلغاء التجديد من إعدادات الاشتراكات.',
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton.icon(
                                      onPressed: c.buying || c.loading
                                          ? null
                                          : c.buy,
                                      icon: const Icon(Icons.workspace_premium),
                                      label: Text(
                                        c.buying
                                            ? 'بانتظار المتجر…'
                                            : 'الاشتراك من المتجر',
                                      ),
                                    ),
                                  ] else
                                    const Text(
                                      'الباكج غير متاح من المتجر حاليًا؛ لن نعرض سعرًا أو شراءً غير محمّل.',
                                    ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: c.store.platform == null
                                          ? null
                                          : c.restore,
                                      child: const Text('استعادة مشترياتي'),
                                    ),
                                    TextButton(
                                      onPressed: () => external(
                                        c.store.platform == 'ios'
                                            ? 'https://apps.apple.com/account/subscriptions'
                                            : 'https://play.google.com/store/account/subscriptions',
                                      ),
                                      child: const Text('إدارة الاشتراك'),
                                    ),
                                  ],
                                ),
                                if (caps?['policy'] case final Map policy)
                                  Wrap(
                                    spacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      if (policy['terms'] is String &&
                                          (policy['terms'] as String)
                                              .isNotEmpty)
                                        TextButton(
                                          onPressed: () => external(
                                            policy['terms'] as String,
                                          ),
                                          child: const Text('شروط الاستخدام'),
                                        ),
                                      if (policy['privacy'] is String &&
                                          (policy['privacy'] as String)
                                              .isNotEmpty)
                                        TextButton(
                                          onPressed: () => external(
                                            policy['privacy'] as String,
                                          ),
                                          child: const Text('الخصوصية'),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        if (q != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _AssistantCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'رصيد الأسئلة',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'هذا الشهر: ${q['monthly_used']} من ${q['monthly_limit']} • اليوم: ${q['daily_used']} من ${q['daily_limit']}',
                                  ),
                                  const Text(
                                    'يشمل الرصيد الطلبات التي عولجت أو التي ما زالت بانتظار التأكيد. حذف السجل لا يعيد الرصيد.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (c.enabled && c.active && !widget.subscription)
                          _AssistantCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'بماذا أساعدك؟',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: text,
                                  maxLength: 600,
                                  minLines: 2,
                                  maxLines: 5,
                                  readOnly: c.sending || c.pending != null,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'اسأل عن الأذكار أو الأدعية في المكتبة…',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: consent,
                                  onChanged: c.sending
                                      ? null
                                      : (v) =>
                                            setState(() => consent = v == true),
                                  title: const Text(
                                    'أوافق على إرسال سؤالي لخدمة ذكاء اصطناعي لمعالجته، وسأتجنب كتابة معلومات شخصية.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                                const Text(
                                  'الشرح آلي وقد يخطئ، وليس فتوى أو بديلًا عن أهل الاختصاص. كل سؤال مستقل.',
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed:
                                      !consent || c.sending || c.pending != null
                                      ? null
                                      : send,
                                  icon: const Icon(Icons.send_outlined),
                                  label: Text(
                                    c.sending ? 'جارٍ التحقق…' : 'إرسال السؤال',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (c.pending != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _AssistantCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'سؤال بانتظار التأكيد',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 19,
                                    ),
                                  ),
                                  Text(c.pending!['question'] as String),
                                  const Text(
                                    'قد يكون الطلب وصل للخادم. سنفحص الإيصال نفسه دون تكرار طلب مدفوع.',
                                  ),
                                  OutlinedButton(
                                    onPressed: c.sending
                                        ? null
                                        : c.checkPending,
                                    child: const Text('التحقق من حالة السؤال'),
                                  ),
                                  TextButton(
                                    onPressed: c.sending
                                        ? null
                                        : abandonPending,
                                    child: const Text('إيقاف إعادة المحاولة'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        for (final reply in c.replies)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: _ReplyCard(
                              reply: reply,
                              onDelete: () async {
                                final owner = c.scope;
                                final ok = await showDialog<bool>(
                                  context: context,
                                  useRootNavigator: false,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('حذف السؤال من السجل؟'),
                                    content: const Text(
                                      'يُحذف النص والجواب من حسابك، ويبقى إيصال الاستهلاك لمنع تكرار العملية. لا يعيد الحذف رصيد الأسئلة.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('إلغاء'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('تأكيد'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true && mounted && c.scope == owner) {
                                  try {
                                    await c.erase(reply.id);
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() => localError = c.message(e));
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                        if (c.next != null)
                          TextButton(
                            onPressed: () async {
                              try {
                                await c.history(more: true);
                              } catch (e) {
                                if (mounted) {
                                  setState(() => localError = c.message(e));
                                }
                              }
                            },
                            child: const Text('أسئلة أقدم'),
                          ),
                      ],
                      if (c.error != null ||
                          c.purchaseError != null ||
                          c.notice != null ||
                          localError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: _AssistantCard(
                            child: Column(
                              children: [
                                for (final value in [
                                  c.error,
                                  c.purchaseError,
                                  c.notice,
                                  localError,
                                ])
                                  if (value != null) Text(value),
                                if (c.purchaseError != null)
                                  TextButton(
                                    onPressed: c.retryPurchases,
                                    child: const Text('إعادة التحقق من الشراء'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AssistantCard extends StatelessWidget {
  const _AssistantCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: p.heading, height: 1.8),
          child: child,
        ),
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({required this.reply, required this.onDelete});
  final AssistantReply reply;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return _AssistantCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reply.question ?? 'سؤال محذوف',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'حذف السؤال',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if (reply.answer != null) ...[
            const Divider(height: 28),
            const Text('شرح آلي • قد يخطئ', style: TextStyle(fontSize: 12)),
            SelectableText(
              reply.answer!,
              style: TextStyle(color: p.tealHeading, fontSize: 18, height: 1.9),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: reply.answer!)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('نسخ الشرح'),
              ),
            ),
          ],
          if (reply.status != 'completed')
            Text(switch (reply.status) {
              'reserved' =>
                'السؤال قيد التحقق؛ لا ترسل سؤالًا بديلًا قبل فحص الحالة.',
              'uncertain' =>
                'تعذّر تأكيد نتيجة الطلب. احتُسب ضمن الحد احتياطيًا ولم نكرر المعالجة.',
              'failed_billed' =>
                'لم نعرض الجواب لتعذّر توثيق بنيته أو مصادره. عولج الطلب واحتُسب ضمن الحد.',
              _ => 'لم يُرسل السؤال للمعالجة ولم يُحتسب من الرصيد.',
            }),
          if (reply.answer != null && reply.sources.isNotEmpty) ...[
            const Divider(height: 28),
            const Text(
              'النصوص الأصلية ومصادرها',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            for (final source in reply.sources)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      source['text'] as String,
                      style: TextStyle(
                        color: p.tealHeading,
                        fontSize: 19,
                        height: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      source['source'] as String,
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

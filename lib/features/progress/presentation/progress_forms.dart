part of 'progress_page.dart';

class _HabitForm extends StatefulWidget {
  const _HabitForm({required this.c, this.value});
  final ProgressController c;
  final ReligiousHabit? value;
  @override
  State<_HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends State<_HabitForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.value?.title ?? '');
  late final _target = TextEditingController(
    text: '${widget.value?.target ?? 1}',
  );
  late Set<int> _days = widget.value?.weekdays.toSet() ?? {1, 2, 3, 4, 5, 6, 7};
  late String _icon = widget.value?.icon ?? 'book';
  late bool _enabled = widget.value?.enabled ?? true;
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy ||
        !widget.c.available ||
        !_form.currentState!.validate() ||
        _days.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    final old = widget.value;
    final target = _positive(_target.text)!;
    final value = ReligiousHabit(
      id: old?.id ?? operationId(),
      title: _title.text.trim(),
      weekdays: _days.toList()..sort(),
      target: target,
      enabled: _enabled,
      icon: _icon,
      epoch: old == null || old.target != target
          ? operationId()
          : old.activeEpoch,
    );
    await widget.c.saveHabit(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.c.available && widget.c.error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) => _ProgressShell(
      c: widget.c,
      title: widget.value == null ? 'إضافة عادة' : 'تعديل العادة',
      subtitle: 'خطوة تناسب يومك',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel(
                context,
                Column(
                  children: [
                    Icon(
                      _habitIcon(_icon),
                      size: 38,
                      color: const Color(0xFF2A8C82),
                    ),
                    TextFormField(
                      key: const ValueKey('habit-title'),
                      controller: _title,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'اسم العادة',
                      ),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'اكتب اسم العادة' : null,
                    ),
                    TextFormField(
                      key: const ValueKey('habit-target'),
                      controller: _target,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الهدف اليومي',
                      ),
                      validator: (v) => _positive(v!) == null
                          ? 'اختر عددًا من 1 إلى 1000000'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final n in [1, 2, 3, 5, 10, 33, 100])
                          ActionChip(
                            label: Text('$n'),
                            onPressed: () =>
                                setState(() => _target.text = '$n'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _panel(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'التكرار',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('كل يوم'),
                          onPressed: () =>
                              setState(() => _days = {1, 2, 3, 4, 5, 6, 7}),
                        ),
                        ActionChip(
                          label: const Text('أيام العمل'),
                          onPressed: () =>
                              setState(() => _days = {7, 1, 2, 3, 4}),
                        ),
                        ActionChip(
                          label: const Text('نهاية الأسبوع'),
                          onPressed: () => setState(() => _days = {5, 6}),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final day in [7, 1, 2, 3, 4, 5, 6])
                          FilterChip(
                            label: Text(_weekday(day)),
                            selected: _days.contains(day),
                            onSelected: (_) => setState(() {
                              if (_days.contains(day)) {
                                if (_days.length > 1) _days.remove(day);
                              } else {
                                _days.add(day);
                              }
                            }),
                          ),
                      ],
                    ),
                    const Text(
                      'يمكن تخصيص الأيام مباشرة. أيام العمل الافتراضية من الأحد إلى الخميس.',
                    ),
                  ],
                ),
              ),
              _panel(
                context,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final icon in ReligiousHabit.habitIcons)
                      ChoiceChip(
                        avatar: Icon(_habitIcon(icon)),
                        label: Text(_iconName(icon)),
                        selected: _icon == icon,
                        onSelected: (_) => setState(() => _icon = icon),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('العادة مفعّلة'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              if (widget.value != null)
                const Text(
                  'تغيير الهدف يبدأ دورة جديدة لعدّ هذه العادة ويحفظ السجل السابق.',
                ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'جارٍ الحفظ…' : 'حفظ العادة'),
              ),
              if (widget.value != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm(
                            context,
                            'حذف العادة؟',
                            'ستُزال من القائمة ويبقى سجل النشاط محفوظًا.',
                          )) {
                            await widget.c.deleteHabit(widget.value!);
                            if (context.mounted &&
                                widget.c.available &&
                                widget.c.error == null) {
                              Navigator.pop(context);
                            }
                          }
                        },
                  child: const Text('حذف العادة'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

int? _positive(String text) {
  const eastern = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(eastern[i], '$i').replaceAll(persian[i], '$i');
  }
  final n = int.tryParse(text.trim());
  return n != null && n >= 1 && n <= 1000000 ? n : null;
}

String _iconName(String icon) => const {
  'book': 'كتاب',
  'beads': 'مسبحة',
  'moon': 'قمر',
  'sun': 'شمس',
  'heart': 'قلب',
  'water': 'ماء',
  'learn': 'تعلم',
  'give': 'عطاء',
  'prayer': 'صلاة',
  'activity': 'نشاط',
  'sleep': 'نوم',
  'read': 'قراءة',
}[icon]!;

class _KhatmaForm extends StatefulWidget {
  const _KhatmaForm({required this.c, this.value});
  final ProgressController c;
  final QuranKhatma? value;
  @override
  State<_KhatmaForm> createState() => _KhatmaFormState();
}

class _KhatmaFormState extends State<_KhatmaForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.value?.title ?? 'ختمتي',
  );
  late final _duration = TextEditingController(
    text: '${widget.value == null ? 30 : khatmaPlan(widget.value!).length}',
  );
  late String _start = widget.value?.startDate ?? widget.c.day;
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !widget.c.available || !_form.currentState!.validate()) return;
    final old = widget.value;
    final value = QuranKhatma(
      id: old?.id ?? operationId(),
      title: _title.text.trim(),
      startDate: _start,
      endDate: progressDay(
        civilDate(_start).add(Duration(days: _positive(_duration.text)! - 1)),
      ),
      firstPage: old?.firstPage ?? 1,
      lastPage: old?.lastPage ?? 604,
      epoch: old?.activeEpoch ?? operationId(),
      archived: old?.archived ?? false,
      reminderMinutes: old?.reminderMinutes,
    );
    setState(() => _busy = true);
    await widget.c.saveKhatma(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.c.available && widget.c.error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) => _ProgressShell(
      c: widget.c,
      title: widget.value == null ? 'إنشاء ختمة جديدة' : 'تعديل خطة الختمة',
      subtitle: 'ورد ثابت يناسب وقتك',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panel(
                context,
                Column(
                  children: [
                    TextFormField(
                      controller: _title,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'اسم الختمة',
                      ),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'اكتب اسم الختمة' : null,
                    ),
                    TextFormField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'مدة الختمة بالأيام',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => (_positive(v!) ?? 4000) > 3650
                          ? 'اختر مدة من 1 إلى 3650 يومًا'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final (days, title) in [
                          (10, 'عشرة أيام'),
                          (15, 'أسبوعان ويوم'),
                          (30, 'شهر'),
                          (40, 'أربعون يومًا'),
                          (60, 'شهران'),
                          (120, 'أربعة أشهر'),
                        ])
                          ActionChip(
                            label: Text(title),
                            onPressed: () =>
                                setState(() => _duration.text = '$days'),
                          ),
                      ],
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('تاريخ البدء'),
                      subtitle: Text(_start),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          useRootNavigator: false,
                          initialDate: DateTime.parse(_start),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null && mounted) {
                          setState(() => _start = progressDay(picked));
                        }
                      },
                    ),
                  ],
                ),
              ),
              _panel(
                context,
                Text(
                  'الورد اليومي نحو ${((widget.value == null ? 604 : widget.value!.lastPage - widget.value!.firstPage + 1) / (_positive(_duration.text) ?? 30)).toStringAsFixed(1)} صفحة. تُوزع الصفحات كاملة حتى نهاية القرآن، وقد تختلف حصة يوم عن آخر بصفحة واحدة.',
                ),
                tinted: true,
              ),
              if (widget.value != null)
                const Text(
                  'تعديل المدة وتاريخ البدء يحتفظان بآخر آية مؤكدة. لإعادة القراءة من البداية استخدم إعادة الضبط.',
                ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'جارٍ الحفظ…' : 'حفظ الخطة'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _KhatmaDetails extends StatelessWidget {
  const _KhatmaDetails({required this.c, required this.id});
  final ProgressController c;
  final String id;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final found = c.khatmas.where((k) => k.id == id);
      if (found.isEmpty || !c.available) return const SizedBox.shrink();
      final k = found.first, plan = khatmaPlan(found.first);
      final read = c.lastRead(k), pages = c.readPages(k);
      final stopped = k.archived == true || c.completed(k);
      void push(Widget page) => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => page),
      );
      return _ProgressShell(
        c: c,
        title: k.title,
        subtitle: 'رحلة اليوم مع القرآن',
        children: [
          _panel(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.completed(k)
                      ? 'اكتملت الختمة، تقبّل الله منك'
                      : k.archived == true
                      ? 'ختمة متوقفة'
                      : 'الختمة الحالية',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: c.fraction(k),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 10),
                Text(
                  '${pages.length} من ${k.lastPage - k.firstPage + 1} صفحة • ${(100 * c.fraction(k)).toStringAsFixed(0)}%',
                ),
                Text(
                  read == null
                      ? 'لم تحدد آخر آية بعد'
                      : 'آخر قراءة: سورة ${c.repository.surah(read.surah).name} • الآية ${read.ayah}',
                ),
                if (k.startDate.compareTo(c.day) > 0)
                  Text('تبدأ الخطة في ${k.startDate}'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: stopped || k.startDate.compareTo(c.day) > 0
                      ? null
                      : () =>
                            push(_KhatmaReader(c: c, k: k, verse: c.resume(k))),
                  icon: const Icon(Icons.menu_book),
                  label: const Text('متابعة وردي'),
                ),
              ],
            ),
            tinted: true,
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => push(_KhatmaForm(c: c, value: k)),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('تعديل الخطة'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    useRootNavigator: false,
                    initialTime: TimeOfDay(
                      hour: (k.reminderMinutes ?? 480) ~/ 60,
                      minute: (k.reminderMinutes ?? 480) % 60,
                    ),
                  );
                  if (time != null && c.available) {
                    await c.saveKhatma(
                      QuranKhatma(
                        id: k.id,
                        title: k.title,
                        startDate: k.startDate,
                        endDate: k.endDate,
                        firstPage: k.firstPage,
                        lastPage: k.lastPage,
                        epoch: k.activeEpoch,
                        archived: k.archived,
                        reminderMinutes: time.hour * 60 + time.minute,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('موعد التذكير'),
              ),
              if (k.reminderMinutes != null)
                TextButton(
                  onPressed: () => c.saveKhatma(
                    QuranKhatma(
                      id: k.id,
                      title: k.title,
                      startDate: k.startDate,
                      endDate: k.endDate,
                      firstPage: k.firstPage,
                      lastPage: k.lastPage,
                      epoch: k.activeEpoch,
                      archived: k.archived,
                    ),
                  ),
                  child: const Text('إلغاء تذكير الختمة'),
                ),
            ],
          ),
          Text(
            k.reminderMinutes == null
                ? 'لم تحدد موعداً لتذكير هذه الختمة.'
                : 'موعد محفوظ: ${(k.reminderMinutes! ~/ 60).toString().padLeft(2, '0')}:${(k.reminderMinutes! % 60).toString().padLeft(2, '0')} • يعتمد التنبيه على تفعيل التذكيرات وإذن الإشعارات في إعدادات التطبيق.',
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < plan.length; i++)
            _panel(
              context,
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  plan[i].pages > 0 &&
                          List.generate(
                            plan[i].pages,
                            (j) => plan[i].first + j,
                          ).every(pages.contains)
                      ? Icons.check_circle_outline
                      : Icons.menu_book_outlined,
                  color: const Color(0xFF2A8C82),
                ),
                title: Text('ورد اليوم ${i + 1}'),
                subtitle: Text(
                  '${plan[i].day}\n${plan[i].pages == 0 ? 'يوم راحة' : 'الصفحات ${plan[i].first}–${plan[i].last} • ${plan[i].pages} صفحة'}',
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap:
                    stopped ||
                        plan[i].pages == 0 ||
                        k.startDate.compareTo(c.day) > 0
                    ? null
                    : () {
                        final v = c.repository.verses.firstWhere(
                          (v) => v.page >= plan[i].first,
                        );
                        push(_KhatmaReader(c: c, k: k, verse: v));
                      },
              ),
            ),
          if (c.previousCycles(k).isNotEmpty)
            ExpansionTile(
              title: const Text('سجل الدورات السابقة'),
              children: [
                for (final cycle in c.previousCycles(k))
                  ListTile(
                    leading: Icon(
                      cycle.complete
                          ? Icons.check_circle_outline
                          : Icons.history,
                    ),
                    title: Text(
                      '${cycle.pages} صفحة • ${cycle.complete ? 'مكتملة' : 'قراءة سابقة'}',
                    ),
                    subtitle: Text(cycle.day),
                  ),
              ],
            ),
          TextButton(
            onPressed: () async {
              if (await _confirm(
                context,
                'إعادة ضبط الختمة؟',
                'تبدأ دورة جديدة من اليوم وتبقى القراءة السابقة محفوظة في التاريخ.',
              )) {
                await c.resetKhatma(k);
              }
            },
            child: const Text('إعادة الضبط'),
          ),
          if (!stopped)
            TextButton(
              onPressed: () async {
                if (await _confirm(
                  context,
                  'إيقاف هذه الختمة؟',
                  'تُنقل الخطة إلى سجل الختمات المتوقفة دون اعتبار الصفحات غير المقروءة مكتملة.',
                )) {
                  await c.saveKhatma(
                    QuranKhatma(
                      id: k.id,
                      title: k.title,
                      startDate: k.startDate,
                      endDate: k.endDate,
                      firstPage: k.firstPage,
                      lastPage: k.lastPage,
                      epoch: k.activeEpoch,
                      archived: true,
                      reminderMinutes: k.reminderMinutes,
                    ),
                  );
                }
              },
              child: const Text('إيقاف الختمة'),
            ),
        ],
      );
    },
  );
}

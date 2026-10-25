part of 'progress_page.dart';

class _KhatmaReader extends StatefulWidget {
  const _KhatmaReader({required this.c, required this.k, required this.verse});
  final ProgressController c;
  final QuranKhatma k;
  final QuranVerse verse;
  @override
  State<_KhatmaReader> createState() => _KhatmaReaderState();
}

class _KhatmaReaderState extends State<_KhatmaReader> {
  late QuranVerse _selected = widget.verse;
  String? _saved;
  bool _busy = false, _canLeave = false, _fullscreen = false, _leaving = false;
  Future<void> _confirmProgress() async {
    if (_busy || !widget.c.available) return;
    final verse = _selected;
    if (!await _confirm(
      context,
      'قرأت حتى هذه الآية؟',
      'سورة ${widget.c.repository.surah(verse.surah).name} • الآية ${verse.ayah}\nيُسجّل أنك قرأت من بداية الختمة حتى هذه الآية، وليس بمجرد فتح الصفحة.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    await widget.c.confirmRead(
      widget.k.id,
      verse,
      expectedEpoch: widget.k.activeEpoch,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      final current = widget.c.khatmas
          .where((k) => k.id == widget.k.id)
          .firstOrNull;
      if (widget.c.error == null &&
          current?.activeEpoch == widget.k.activeEpoch &&
          widget.c.lastRead(current!)?.key == verse.key) {
        _saved = verse.key;
      }
    });
  }

  Future<void> _leave() async {
    if (_canLeave || !mounted || _leaving || _fullscreen) return;
    _leaving = true;
    if (_saved != _selected.key &&
        !await _confirm(
          context,
          'قبل مغادرة الورد',
          'لتسجيل القراءة اضغط «تحديد آخر آية قرأتها». هل تريد الخروج دون تحديد جديد؟',
        )) {
      _leaving = false;
      return;
    }
    if (!mounted) return;
    setState(() => _canLeave = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      if (!widget.c.available) return const SizedBox.shrink();
      final k = widget.c.khatmas.where((k) => k.id == widget.k.id).firstOrNull;
      final valid =
          k != null &&
          k.activeEpoch == widget.k.activeEpoch &&
          k.archived != true;
      return PopScope<void>(
        canPop: _canLeave,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_leave());
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('ورد الختمة'),
            leading: IconButton(
              tooltip: 'رجوع',
              onPressed: _leave,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: QuranReader(
                    controller: widget.c.activity.quran,
                    verse: widget.verse,
                    onFullscreenChanged: (v) {
                      _fullscreen = v;
                    },
                    onActiveVerseChanged: (v) {
                      _selected = v;
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.c.error != null) Text(widget.c.error!),
                      FilledButton.icon(
                        onPressed: _busy || !valid ? null : _confirmProgress,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: Text(
                          _busy ? 'جارٍ الحفظ…' : 'تحديد آخر آية قرأتها',
                        ),
                      ),
                      if (_saved != null)
                        const Text('حُفظ تقدمك', textAlign: TextAlign.center),
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

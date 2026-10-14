import 'package:flutter/material.dart';

import '../data/quran_page_downloads.dart';
import '../data/quran_repository.dart';
import 'quran_widgets.dart';
import '../../../app_appearance.dart';

Future<void> showQuranPageDownloadSheet(
  BuildContext context, {
  required QuranPageDownloads downloads,
  required QuranRepository repository,
  required int surahId,
}) async {
  try {
    await downloads.initialize();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذّر فتح ملفات المصحف؛ تحقق من مساحة الجهاز'),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppPalette.of(context).surface,
    builder: (context) => _QuranPageDownloadSheet(
      downloads: downloads,
      repository: repository,
      surahId: surahId,
    ),
  );
}

class _QuranPageDownloadSheet extends StatelessWidget {
  const _QuranPageDownloadSheet({
    required this.downloads,
    required this.repository,
    required this.surahId,
  });
  final QuranPageDownloads downloads;
  final QuranRepository repository;
  final int surahId;

  String _size(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر بدء التنزيل؛ تحقق من مساحة الجهاز'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: SafeArea(
      child: AnimatedBuilder(
        animation: downloads,
        builder: (context, _) {
          final pages = downloads.pagesForSurah(repository, surahId);
          final currentSize = pages.fold(
            0,
            (sum, page) => sum + downloads.manifest[page]!.bytes,
          );
          final allSize = downloads.manifest.values.fold(
            0,
            (sum, spec) => sum + spec.bytes,
          );
          final saved = pages.where(downloads.hasPage).length;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .82,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.download_for_offline_outlined,
                    color: qTeal,
                    size: 34,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'تنزيل صفحات المصحف',
                    textAlign: TextAlign.center,
                    style: qText(context, size: 19),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'نزّل صور هذه السورة أو المصحف كاملًا لتتصفح الصفحات بدون إنترنت.',
                    textAlign: TextAlign.center,
                    style: qText(context, size: 13),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: saved == pages.length
                        ? null
                        : () => _run(
                            context,
                            () => downloads.downloadSurah(repository, surahId),
                          ),
                    icon: Icon(
                      saved == pages.length
                          ? Icons.offline_pin_outlined
                          : Icons.download_outlined,
                    ),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        saved == pages.length
                            ? 'سورة ${repository.surah(surahId).name} محفوظة'
                            : 'هذه السورة • ${pages.length} صفحة • ${_size(currentSize)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: qTeal),
                    onPressed: downloads.completed == 604
                        ? null
                        : () => _run(context, downloads.downloadAll),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(
                        downloads.completed == 604
                            ? 'المصحف كاملًا محفوظ'
                            : 'المصحف كاملًا • 604 صفحات • ${_size(allSize)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  if (downloads.total > 0) ...[
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: downloads.progress,
                      color: qTeal,
                      borderRadius: BorderRadius.circular(6),
                      minHeight: 6,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'حُفظت ${downloads.completed} من ${downloads.total} صفحة'
                      ' • ${(downloads.progress * 100).floor()}٪',
                      style: qText(context, size: 12),
                      textAlign: TextAlign.center,
                    ),
                    if (downloads.error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        downloads.error!,
                        textAlign: TextAlign.center,
                        style: qText(
                          context,
                          size: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                    if (downloads.isActive)
                      TextButton.icon(
                        onPressed: () => _run(context, downloads.pauseAll),
                        icon: const Icon(Icons.pause_circle_outline),
                        label: const Text('إيقاف التنزيل'),
                      )
                    else if (downloads.hasPending)
                      TextButton.icon(
                        onPressed: () => _run(context, downloads.resumeAll),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('استكمال التنزيل'),
                      ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'صور مصحف المدينة • مجمع الملك فهد / Quran.ws',
                    textAlign: TextAlign.center,
                    style: qText(context, size: 10),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(downloads.total == 0 ? 'لاحقًا' : 'إغلاق'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

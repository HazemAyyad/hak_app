import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/published_meaning_card.dart';
import '../../account/data/app_session.dart';
import 'admin_page.dart' show AdminSessionBoundary, adminError;
import 'source_request_id.dart';

class AdminSourcesPage extends StatefulWidget {
  const AdminSourcesPage({
    super.key,
    required this.session,
    required this.locale,
    required this.name,
  });
  final AppSession session;
  final String locale, name;
  @override
  State<AdminSourcesPage> createState() => _AdminSourcesPageState();
}

class _AdminSourcesPageState extends State<AdminSourcesPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  int _page = 1, _request = 0;
  Timer? _poll;
  final _pending = <String, String>{};

  bool _inFlight(String key) => (_data?['imports']['data'] as List? ?? []).any(
    (row) =>
        row['provider_key'] == key &&
        ['queued', 'running'].contains(row['status']),
  );
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    _poll?.cancel();
    try {
      final data = await widget.session.adminRequest(
        'GET',
        'languages/${widget.locale}/sources?page=$_page',
      );
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _error = null;
      });
      if ((data['imports']['data'] as List).any(
        (row) => ['queued', 'running'].contains(row['status']),
      )) {
        _poll = Timer(const Duration(seconds: 15), _load);
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = adminError(e));
      }
    }
  }

  Future<void> _import(String sourceKey) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preferences = LocalizationScope.maybeOf(context)?.preferences;
      final storageKey =
          'app.source.request.${widget.session.profile?['id']}.${widget.locale}.$sourceKey';
      final request =
          _pending[sourceKey] ??
          preferences?.getString(storageKey) ??
          sourceRequestId();
      _pending[sourceKey] = request;
      if (preferences != null &&
          !await preferences.setString(storageKey, request)) {
        throw StateError('Cannot persist import request');
      }
      await widget.session.adminRequest(
        'POST',
        'languages/${widget.locale}/sources',
        data: {'request_id': request, 'provider_key': sourceKey},
      );
      _pending.remove(sourceKey);
      await preferences?.remove(storageKey);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(int? id) async {
    if (_busy || _data == null) return;
    setState(() => _busy = true);
    try {
      await widget.session.adminRequest(
        'POST',
        'languages/${widget.locale}/sources/selection',
        data: {
          'source_id': id,
          'language_revision': _data!['language_revision'],
        },
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSessionBoundary(
    session: widget.session,
    child: Scaffold(
      appBar: AppBar(
        title: Text('${context.tr('source.title')} · ${widget.name}'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: context.tr('common.retry'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('source.workflow')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                context.tr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_data == null && _error == null || _busy)
            const LinearProgressIndicator(),
          for (final source in _data?['catalog'] as List? ?? [])
            Card(
              child: ListTile(
                title: Text(source['title'] as String),
                subtitle: Text('QuranEnc.com · v${source['version']}'),
                trailing: widget.session.can('content.edit')
                    ? IconButton(
                        onPressed: _busy || _inFlight(source['key'] as String)
                            ? null
                            : () => _import(source['key'] as String),
                        tooltip: context.tr('source.import'),
                        icon: const Icon(Icons.cloud_download_outlined),
                      )
                    : null,
              ),
            ),
          if (_data != null && (_data!['catalog'] as List).isEmpty)
            Text(context.tr('source.noCatalog')),
          const Divider(),
          Text(
            context.tr('source.imports'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final row in _data?['imports']['data'] as List? ?? [])
            Card(
              child: ListTile(
                title: Text(
                  row['summary']?['title'] as String? ??
                      row['provider_key'] as String,
                ),
                subtitle: Text(
                  '${context.tr('source.status.${row['status']}')}${row['summary'] == null ? '' : ' · v${row['summary']['version']} · ${row['summary']['surahs']} ${context.tr('source.surahs')}'}',
                ),
                leading: row['id'] == _data?['selected_id']
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: ['ready', 'reviewed'].contains(row['status'])
                    ? () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AdminSourceReviewPage(
                              session: widget.session,
                              locale: widget.locale,
                              importId: row['id'] as int,
                            ),
                          ),
                        );
                        await _load();
                      }
                    : null,
                trailing:
                    row['status'] == 'reviewed' && widget.session.can('publish')
                    ? IconButton(
                        tooltip: context.tr('source.select'),
                        onPressed: _busy
                            ? null
                            : () => _select(row['id'] as int),
                        icon: const Icon(Icons.playlist_add_check),
                      )
                    : null,
              ),
            ),
          if (_data?['selected_id'] != null && widget.session.can('publish'))
            TextButton(
              onPressed: _busy ? null : () => _select(null),
              child: Text(context.tr('source.unselect')),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _page > 1
                    ? () {
                        _page--;
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_page'),
              IconButton(
                onPressed: _data?['imports']['next_page_url'] != null
                    ? () {
                        _page++;
                        _load();
                      }
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AdminSourceReviewPage extends StatefulWidget {
  const AdminSourceReviewPage({
    super.key,
    required this.session,
    required this.locale,
    required this.importId,
  });
  final AppSession session;
  final String locale;
  final int importId;
  @override
  State<AdminSourceReviewPage> createState() => _AdminSourceReviewPageState();
}

class _AdminSourceReviewPageState extends State<AdminSourceReviewPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false, _mapping = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load([int? surah]) async {
    final request = ++_request;
    try {
      final data = await widget.session.adminRequest(
        'GET',
        'languages/${widget.locale}/sources/${widget.importId}${surah == null ? '' : '?surah=$surah'}',
      );
      if (mounted && request == _request) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = adminError(e));
      }
    }
  }

  Future<void> _review() async {
    if (_data == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.session.adminRequest(
        'POST',
        'languages/${widget.locale}/sources/${widget.importId}/review',
        data: {'revision': _data!['revision'], 'mapping_confirmed': _mapping},
      );
      await _load(_data!['surah'] as int);
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _request++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSessionBoundary(
    session: widget.session,
    child: Scaffold(
      appBar: AppBar(title: Text(context.tr('source.review'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Text(context.tr(_error!)),
          if (_data == null && _error == null || _busy)
            const LinearProgressIndicator(),
          if (_data != null) ...[
            Text(
              _data!['source']['title'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(_data!['attribution'] as String),
            if (_data!['source']['description'] case final String description)
              Text(description),
            Text(context.tr('source.policy')),
            if (_data!['mapping_review_required'] == true)
              CheckboxListTile(
                title: Text(context.tr('source.mapping')),
                value: _mapping,
                onChanged: (value) => setState(() => _mapping = value ?? false),
              ),
            DropdownButton<int>(
              value: _data!['surah'] as int,
              isExpanded: true,
              items: [
                for (final surah in _data!['surahs'] as List)
                  DropdownMenuItem(
                    value: surah as int,
                    child: Text('${context.tr('source.surah')} $surah'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) _load(value);
                    },
            ),
            if (widget.session.can('review') && _data!['status'] == 'ready')
              FilledButton(
                onPressed:
                    _busy ||
                        _data!['mapping_review_required'] == true && !_mapping
                    ? null
                    : _review,
                child: Text(context.tr('admin.review')),
              ),
            if (_data!['status'] == 'reviewed')
              Text(context.tr('admin.reviewed')),
            for (final row in _data!['rows'] as List)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Directionality(
                    textDirection: _data!['source']['direction'] == 'rtl'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${row['sura']}:${row['aya']}'),
                        if (widget
                                .session
                                .religious
                                .controller
                                .repository
                                ?.byKey['${row['sura']}:${row['aya']}']
                                ?.text
                            case final String original)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SelectableText(
                              original,
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                        PublishedTranslationText(row['translation'] as String),
                        if ((row['footnotes'] as String).isNotEmpty) ...[
                          const Divider(),
                          Text(context.tr('source.footnotes')),
                          PublishedTranslationText(row['footnotes'] as String),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

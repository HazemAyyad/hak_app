import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/app_localization.dart';
import '../../../core/localization/published_hadith_card.dart';
import '../../account/data/app_session.dart';
import 'admin_page.dart' show AdminSessionBoundary, adminError;
import 'source_request_id.dart';

class AdminHadithSourcesPage extends StatefulWidget {
  const AdminHadithSourcesPage({
    super.key,
    required this.session,
    required this.locale,
    required this.name,
  });
  final AppSession session;
  final String locale, name;
  @override
  State<AdminHadithSourcesPage> createState() => _AdminHadithSourcesPageState();
}

class _AdminHadithSourcesPageState extends State<AdminHadithSourcesPage> {
  final _mapping = TextEditingController(text: '{}');
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  int _page = 1, _request = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_request;
    _poll?.cancel();
    try {
      final data = await widget.session.adminRequest(
        'GET',
        'languages/${widget.locale}/hadith-sources?page=$_page',
      );
      if (!mounted || generation != _request) return;
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
      if (mounted && generation == _request) {
        setState(() => _error = adminError(e));
      }
    }
  }

  Future<void> _import() async {
    if (_busy || _data == null) return;
    Map<String, String> mapping;
    try {
      if (_mapping.text.length > 65536) throw const FormatException();
      mapping = Map<String, String>.from(jsonDecode(_mapping.text) as Map);
      final ids = (_data!['items'] as List).map((item) => item['id']).toSet();
      if (mapping.isEmpty ||
          mapping.length > 100 ||
          mapping.entries.any(
            (entry) =>
                !ids.contains(entry.key) ||
                !RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(entry.value),
          )) {
        throw const FormatException();
      }
    } catch (_) {
      setState(() => _error = 'hadith.invalidMapping');
      return;
    }
    final ordered = <String, String>{
      for (final key in mapping.keys.toList()..sort()) key: mapping[key]!,
    };
    final preferences = LocalizationScope.maybeOf(context)?.preferences;
    final digest = sha256.convert(utf8.encode(jsonEncode(ordered))).toString();
    final storageKey =
        'app.hadith.request.${widget.session.profile?['id']}.${widget.locale}.$digest';
    setState(() => _busy = true);
    try {
      final request = preferences?.getString(storageKey) ?? sourceRequestId();
      if (preferences != null &&
          !await preferences.setString(storageKey, request)) {
        throw StateError('Cannot persist source request');
      }
      await widget.session.adminRequest(
        'POST',
        'languages/${widget.locale}/hadith-sources',
        data: {'request_id': request, 'mapping': ordered},
      );
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
        'languages/${widget.locale}/hadith-sources/selection',
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
    _mapping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSessionBoundary(
    session: widget.session,
    child: Scaffold(
      appBar: AppBar(
        title: Text('${context.tr('hadith.sources')} · ${widget.name}'),
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
          Text(context.tr('hadith.workflow')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.tr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy || _data == null && _error == null)
            const LinearProgressIndicator(),
          if (_data != null) ...[
            if (_data!['available'] != true)
              Text(context.tr('source.noCatalog')),
            if (_data!['available'] == true &&
                widget.session.can('content.edit')) ...[
              TextField(
                key: const ValueKey('hadith-mapping'),
                controller: _mapping,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.tr('hadith.mapping'),
                  hintText: '{"nawawi-01":"66511"}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('import-hadith-source'),
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.cloud_download_outlined),
                label: Text(context.tr('source.import')),
              ),
            ],
            ExpansionTile(
              title: Text(context.tr('hadith.localReferences')),
              children: [
                for (final item in _data!['items'] as List)
                  ListTile(
                    title: Text(item['title'] as String),
                    subtitle: SelectableText(
                      item['id'] as String,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
              ],
            ),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://hadeethenc.com/${_data!['source_locale']}/home',
                ),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text(context.tr('hadith.browsePublisher')),
            ),
            const Divider(),
            Text(
              context.tr('source.imports'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final row in _data!['imports']['data'] as List)
              Card(
                child: ListTile(
                  title: Text(
                    'HadeethEnc.com · ${row['summary']?['version'] ?? row['id']}',
                  ),
                  subtitle: Text(context.tr('source.status.${row['status']}')),
                  leading: row['id'] == _data!['selected_id']
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: _busy || !['ready', 'reviewed'].contains(row['status'])
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AdminHadithReviewPage(
                                session: widget.session,
                                locale: widget.locale,
                                importId: row['id'] as int,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                  trailing:
                      row['status'] == 'reviewed' &&
                          widget.session.can('publish')
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
            if (_data!['selected_id'] != null && widget.session.can('publish'))
              TextButton(
                onPressed: _busy ? null : () => _select(null),
                child: Text(context.tr('source.unselect')),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: context.tr('exchange.previous'),
                  onPressed: _busy || _page < 2
                      ? null
                      : () {
                          _page--;
                          _load();
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_page'),
                IconButton(
                  tooltip: context.tr('exchange.next'),
                  onPressed: _busy || _data!['imports']['next_page_url'] == null
                      ? null
                      : () {
                          _page++;
                          _load();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class AdminHadithReviewPage extends StatefulWidget {
  const AdminHadithReviewPage({
    super.key,
    required this.session,
    required this.locale,
    required this.importId,
  });
  final AppSession session;
  final String locale;
  final int importId;
  @override
  State<AdminHadithReviewPage> createState() => _AdminHadithReviewPageState();
}

class _AdminHadithReviewPageState extends State<AdminHadithReviewPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false, _mapping = false, _loading = false;
  int _request = 0;
  final _confirmed = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load([String? id]) async {
    final generation = ++_request;
    setState(() => _loading = true);
    try {
      final data = await widget.session.adminRequest(
        'GET',
        'languages/${widget.locale}/hadith-sources/${widget.importId}${id == null ? '' : '?content_id=${Uri.encodeQueryComponent(id)}'}',
      );
      if (!mounted || generation != _request) return;
      setState(() {
        if (_data != null && _data!['revision'] != data['revision']) {
          _confirmed.clear();
          _mapping = false;
        }
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (mounted && generation == _request) {
        setState(() => _error = adminError(e));
      }
    } finally {
      if (mounted && generation == _request) setState(() => _loading = false);
    }
  }

  Future<void> _review() async {
    if (_busy ||
        _loading ||
        _data == null ||
        _confirmed.length != (_data!['content_ids'] as List).length) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.session.adminRequest(
        'POST',
        'languages/${widget.locale}/hadith-sources/${widget.importId}/review',
        data: {
          'revision': _data!['revision'],
          'references_confirmed': _confirmed.toList(),
          'mapping_confirmed': _mapping,
        },
      );
      if (mounted) Navigator.pop(context);
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
          if (_data == null && _error == null || _busy || _loading)
            const LinearProgressIndicator(),
          if (_data != null) ...[
            Text(context.tr('hadith.reviewInstructions')),
            DropdownButton<String>(
              key: const ValueKey('review-hadith-reference'),
              isExpanded: true,
              value: _data!['content_id'] as String,
              items: [
                for (final id in _data!['content_ids'] as List)
                  DropdownMenuItem(
                    value: id as String,
                    child: Text(id, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy || _loading
                  ? null
                  : (id) {
                      if (id != null) _load(id);
                    },
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.tr('hadith.localOriginal'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(_data!['original']['title'] as String),
                      SelectableText(_data!['original']['text'] as String),
                      SelectableText(
                        _data!['original']['sourceUrl'] as String,
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PublishedHadithRecord(
              record: Map<String, String>.from(_data!['record'] as Map),
              source: Map<String, dynamic>.from(_data!['source'] as Map),
              direction: _data!['direction'] as String,
              expandArabic: true,
            ),
            if (widget.session.can('review') &&
                _data!['status'] != 'reviewed') ...[
              CheckboxListTile(
                key: const ValueKey('confirm-hadith-reference'),
                title: Text(context.tr('hadith.confirmReference')),
                value: _confirmed.contains(_data!['content_id']),
                onChanged: _busy || _loading
                    ? null
                    : (value) => setState(() {
                        value == true
                            ? _confirmed.add(_data!['content_id'] as String)
                            : _confirmed.remove(_data!['content_id']);
                      }),
              ),
              if (_data!['mapping_review_required'] == true)
                CheckboxListTile(
                  title: Text(context.tr('source.mapping')),
                  value: _mapping,
                  onChanged: _busy || _loading
                      ? null
                      : (value) => setState(() => _mapping = value ?? false),
                ),
              Text(
                context.tr(
                  'hadith.confirmedCount',
                  args: {
                    'count': _confirmed.length,
                    'total': (_data!['content_ids'] as List).length,
                  },
                ),
              ),
              FilledButton(
                key: const ValueKey('approve-hadith-source'),
                onPressed:
                    _busy ||
                        _loading ||
                        _confirmed.length !=
                            (_data!['content_ids'] as List).length ||
                        _data!['mapping_review_required'] == true && !_mapping
                    ? null
                    : _review,
                child: Text(context.tr('source.review')),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

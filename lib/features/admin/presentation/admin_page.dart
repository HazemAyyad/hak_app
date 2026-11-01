import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/localization/app_localization.dart';
import '../../account/data/app_session.dart';
import 'admin_sources_page.dart';
import 'admin_translation_exchange_page.dart';
import 'admin_hadith_sources_page.dart';

String adminError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 409) return 'admin.conflict';
    if ([401, 403].contains(error.response?.statusCode)) return 'admin.denied';
    final data = error.response?.data;
    if (error.response?.statusCode == 422 &&
        data is Map &&
        data['errors'] is Map) {
      final locale = data['errors']['locale'];
      if (locale is List && locale.contains('reviewed_content_required')) {
        return 'admin.reviewedContentRequired';
      }
    }
  }
  return 'common.error';
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.session});
  final AppSession session;
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>>? _languages;
  String? _error;
  bool _busy = false;
  String _kind = 'ui';
  AppSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await session.adminRequest('GET', 'languages');
      if (mounted) {
        setState(() {
          _languages = List<Map<String, dynamic>>.from(data['items'] as List);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    }
  }

  Future<bool> _confirm(
    String title, {
    String message = 'admin.publishConfirm',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr(title)),
          content: Text(ctx.tr(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('common.continue')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _publish(
    Map<String, dynamic> language, {
    int? restore,
    bool contentOnly = false,
  }) async {
    if (_busy ||
        !await _confirm(
          restore != null
              ? 'admin.restore'
              : contentOnly
              ? 'admin.publishContent'
              : 'admin.publish',
          message: contentOnly
              ? 'admin.publishContentConfirm'
              : 'admin.publishConfirm',
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.adminRequest(
        'POST',
        'languages/${language['locale']}/publish',
        data: {
          'revision': language['revision'],
          'restore_release_id': ?restore,
          if (contentOnly && restore == null) 'content_only': true,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> language) async {
    try {
      final data = await session.adminRequest(
        'GET',
        'languages/${language['locale']}/releases',
      );
      if (!mounted) return;
      final selected = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(ctx.tr('admin.restore')),
          children: [
            for (final row in data['items'] as List)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, row['id'] as int),
                child: Text('#${row['id']} · ${row['created_at']}'),
              ),
          ],
        ),
      );
      if (selected != null && mounted) {
        await _publish(language, restore: selected);
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (!session.admin) {
        return Scaffold(
          appBar: AppBar(title: Text(context.tr('admin.title'))),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.tr('admin.denied')),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('admin.preview')),
                ),
              ],
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(context.tr('admin.title')),
          actions: [
            IconButton(
              tooltip: context.tr('admin.preview'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.visibility_outlined),
            ),
            IconButton(
              tooltip: context.tr('common.retry'),
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (session.can('team.manage'))
              Wrap(
                spacing: 8,
                children: [
                  for (final path in ['team', 'audit'])
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => AdminTeamPage(
                            session: session,
                            audit: path == 'audit',
                          ),
                        ),
                      ),
                      child: Text(context.tr('admin.$path')),
                    ),
                ],
              ),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'ui',
                  label: Text(context.tr('admin.languages')),
                ),
                ButtonSegment(
                  value: 'content',
                  label: Text(context.tr('admin.content')),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) =>
                  setState(() => _kind = value.single),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.tr(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_languages == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            for (final language in _languages ?? <Map<String, dynamic>>[])
              Card(
                child: ListTile(
                  title: Text(language['name'] as String),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'admin.coverage',
                          args: {
                            'reviewed': language['reviewed'] as int,
                            'total': language['total'] as int,
                          },
                        ),
                      ),
                      if (language.containsKey('interface_ready'))
                        Text(
                          context.tr(
                            language['interface_ready'] == true
                                ? 'admin.interfaceReady'
                                : 'admin.interfacePending',
                          ),
                        ),
                      if (language.containsKey('ui_release_id') &&
                          language['release_id'] != null &&
                          language['release_id'] != language['ui_release_id'])
                        Text(context.tr('admin.contentPublished')),
                    ],
                  ),
                  onTap: _busy
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AdminTranslationPage(
                                session: session,
                                locale: language['locale'] as String,
                                name: language['name'] as String,
                                kind: _kind,
                              ),
                            ),
                          );
                          await _load();
                        },
                  trailing: PopupMenuButton<String>(
                    enabled: !_busy,
                    onSelected: (value) async {
                      if (value == 'exchange') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AdminTranslationExchangePage(
                              session: session,
                              locale: language['locale'] as String,
                              kind: _kind,
                            ),
                          ),
                        );
                        await _load();
                        return;
                      }
                      if (value == 'sources') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AdminSourcesPage(
                              session: session,
                              locale: language['locale'] as String,
                              name: language['name'] as String,
                            ),
                          ),
                        );
                        await _load();
                        return;
                      }
                      if (value == 'hadith-sources') {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => AdminHadithSourcesPage(
                              session: session,
                              locale: language['locale'] as String,
                              name: language['name'] as String,
                            ),
                          ),
                        );
                        await _load();
                        return;
                      }
                      if (value == 'publish') await _publish(language);
                      if (value == 'publish-content') {
                        await _publish(language, contentOnly: true);
                      }
                      if (value == 'restore') await _restore(language);
                      if (value == 'hide') {
                        try {
                          await session.adminRequest(
                            'POST',
                            'languages/${language['locale']}/hide',
                            data: {'revision': language['revision']},
                          );
                          await _load();
                        } catch (e) {
                          if (mounted) setState(() => _error = adminError(e));
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'exchange',
                        child: Text(ctx.tr('exchange.title')),
                      ),
                      PopupMenuItem(
                        value: 'sources',
                        child: Text(ctx.tr('source.title')),
                      ),
                      PopupMenuItem(
                        value: 'hadith-sources',
                        child: Text(ctx.tr('hadith.sources')),
                      ),
                      if (session.can('publish'))
                        PopupMenuItem(
                          value: 'publish-content',
                          child: Text(ctx.tr('admin.publishContent')),
                        ),
                      if (session.can('publish'))
                        PopupMenuItem(
                          value: 'publish',
                          child: Text(ctx.tr('admin.publish')),
                        ),
                      if (session.can('publish') &&
                          language['release_id'] != null)
                        PopupMenuItem(
                          value: 'restore',
                          child: Text(ctx.tr('admin.restore')),
                        ),
                      if (session.can('languages.manage') &&
                          language['enabled'] == true)
                        PopupMenuItem(
                          value: 'hide',
                          child: Text(ctx.tr('admin.hide')),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class AdminTranslationPage extends StatefulWidget {
  const AdminTranslationPage({
    super.key,
    required this.session,
    required this.locale,
    required this.name,
    required this.kind,
  });
  final AppSession session;
  final String locale, name, kind;
  @override
  State<AdminTranslationPage> createState() => _AdminTranslationPageState();
}

class _AdminTranslationPageState extends State<AdminTranslationPage> {
  final _search = TextEditingController();
  Map<String, dynamic>? _data;
  String? _error;
  int _page = 1, _request = 0;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final data = await widget.session.adminRequest(
        'GET',
        'languages/${widget.locale}/records?kind=${widget.kind}&page=$_page&q=${Uri.encodeQueryComponent(_search.text)}',
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

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSessionBoundary(
    session: widget.session,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: context.tr('common.search'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _page = 1;
              _debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
          if (_error != null) Text(context.tr(_error!)),
          if (_data == null && _error == null) const LinearProgressIndicator(),
          for (final row in _data?['items'] as List? ?? [])
            ListTile(
              title: Text(
                row['kind'] == 'ui'
                    ? row['original'] as String
                    : row['original']['title'] as String,
              ),
              subtitle: Text(
                '${row['key']} · ${context.tr('admin.${row['status']}')}',
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AdminEditorPage(
                      session: widget.session,
                      locale: widget.locale,
                      row: Map<String, dynamic>.from(row as Map),
                    ),
                  ),
                );
                await _load();
              },
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: context.tr('common.back'),
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
                tooltip: context.tr('common.continue'),
                onPressed:
                    _data != null && _page * 30 < (_data!['total'] as int)
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

class AdminEditorPage extends StatefulWidget {
  const AdminEditorPage({
    super.key,
    required this.session,
    required this.locale,
    required this.row,
  });
  final AppSession session;
  final String locale;
  final Map<String, dynamic> row;
  @override
  State<AdminEditorPage> createState() => _AdminEditorPageState();
}

class _AdminEditorPageState extends State<AdminEditorPage> {
  late final _ui = widget.row['kind'] == 'ui';
  late int _revision = widget.row['revision'] as int;
  late final Map<String, TextEditingController> _fields = _ui
      ? {
          'value': TextEditingController(
            text:
                widget.row['value'] as String? ??
                (widget.locale == 'en'
                    ? widget.row['suggestion'] as String?
                    : ''),
          ),
        }
      : {
          for (final field in [
            'title',
            'text',
            'summary',
            'source',
            'sourceUrl',
          ])
            field: TextEditingController(
              text: (widget.row['value'] as Map?)?[field] as String? ?? '',
            ),
        };
  String? _error, _message;
  bool _busy = false, _dirty = false;
  Future<void> _run(bool review) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      if (review) {
        await widget.session.adminRequest(
          'POST',
          'languages/${widget.locale}/review',
          data: {'key': widget.row['key'], 'revision': _revision},
        );
      } else {
        final data = await widget.session.adminRequest(
          'PUT',
          'languages/${widget.locale}/records',
          data: {
            'key': widget.row['key'],
            'revision': _revision,
            'value': _ui
                ? _fields['value']!.text
                : {
                    for (final field in _fields.entries)
                      field.key: field.value.text,
                  },
          },
        );
        _revision = data['revision'] as int;
        _dirty = false;
      }
      if (mounted) {
        setState(() => _message = review ? 'admin.reviewed' : 'common.saved');
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSessionBoundary(
    session: widget.session,
    child: Scaffold(
      appBar: AppBar(title: Text(context.tr('admin.translation'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.row['key'] as String, textDirection: TextDirection.ltr),
          Text(
            context.tr('admin.original'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SelectableText(
            _ui
                ? widget.row['original'] as String
                : (widget.row['original'] as Map)['text'] as String,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 16),
          for (final field in _fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: field.value,
                minLines: field.key == 'text' ? 5 : 1,
                maxLines: field.key == 'text' || _ui ? 14 : 3,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: InputDecoration(
                  labelText: context.tr(
                    field.key == 'value'
                        ? 'admin.translation'
                        : 'admin.${field.key == 'title' ? 'contentTitle' : field.key}',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          if (_error != null)
            Text(
              context.tr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_message != null) Text(context.tr(_message!)),
          if (_busy) const LinearProgressIndicator(),
          Wrap(
            spacing: 12,
            children: [
              if (widget.session.can(
                _ui ? 'translations.edit' : 'content.edit',
              ))
                FilledButton(
                  onPressed: _busy ? null : () => _run(false),
                  child: Text(context.tr('common.save')),
                ),
              if (widget.session.can('review'))
                OutlinedButton(
                  onPressed: _busy || _dirty || _revision == 0
                      ? null
                      : () => _run(true),
                  child: Text(context.tr('admin.review')),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AdminTeamPage extends StatefulWidget {
  const AdminTeamPage({super.key, required this.session, this.audit = false});
  final AppSession session;
  final bool audit;
  @override
  State<AdminTeamPage> createState() => _AdminTeamPageState();
}

class _AdminTeamPageState extends State<AdminTeamPage> {
  Map<String, dynamic>? _data;
  String? _error;
  int _page = 1;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final data = await widget.session.adminRequest(
        'GET',
        '${widget.audit ? 'audit' : 'team'}?page=$_page',
      );
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    }
  }

  Future<void> _edit(Map row) async {
    var active = row['active'] == true || row['active'] == 1;
    final permissions = Set<String>.from(
      jsonDecode(row['permissions'] as String) as List,
    );
    final locales = List<String>.from(
      jsonDecode(row['locales'] as String) as List,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(ctx.tr('admin.team')),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: Text(ctx.tr('admin.status')),
                    value: active,
                    onChanged: (v) => update(() => active = v),
                  ),
                  for (final permission in widget.session.permissions)
                    CheckboxListTile(
                      title: Text(ctx.tr('permission.$permission')),
                      value: permissions.contains(permission),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          permissions.add(permission);
                        } else {
                          permissions.remove(permission);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('common.save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await widget.session.adminRequest(
        'PATCH',
        'team/${row['id']}',
        data: {
          'active': active,
          'permissions': permissions.toList(),
          'locales': locales,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    }
  }

  @override
  Widget build(BuildContext context) => AdminSessionBoundary(
    session: widget.session,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.tr(widget.audit ? 'admin.audit' : 'admin.team')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Text(context.tr(_error!)),
          for (final row in _data?['data'] as List? ?? [])
            ListTile(
              title: Text(
                widget.audit
                    ? row['action'] as String
                    : '#${row['app_account_id']}',
              ),
              subtitle: Text(
                widget.audit
                    ? '${row['subject']} · ${row['created_at']}'
                    : '${row['permissions']} · ${row['locales']}',
              ),
              onTap:
                  widget.audit ||
                      row['app_account_id'] == widget.session.profile?['id']
                  ? null
                  : () => _edit(row as Map),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _page > 1
                    ? () {
                        _page--;
                        _load();
                      }
                    : null,
                child: const Icon(Icons.chevron_left),
              ),
              Text('$_page'),
              TextButton(
                onPressed: _data?['next_page_url'] != null
                    ? () {
                        _page++;
                        _load();
                      }
                    : null,
                child: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AdminSessionBoundary extends StatefulWidget {
  const AdminSessionBoundary({
    super.key,
    required this.session,
    required this.child,
  });
  final AppSession session;
  final Widget child;
  @override
  State<AdminSessionBoundary> createState() => AdminSessionBoundaryState();
}

class AdminSessionBoundaryState extends State<AdminSessionBoundary> {
  late final Object? _owner = widget.session.profile?['id'];
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      if (widget.session.admin && widget.session.profile?['id'] == _owner) {
        return widget.child;
      }
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('admin.title'))),
        body: Center(child: Text(context.tr('admin.denied'))),
      );
    },
  );
}

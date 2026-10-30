import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/localization/app_localization.dart';
import '../../account/data/app_session.dart';
import 'admin_page.dart' show AdminSessionBoundary, adminError;

class AdminTranslationExchangePage extends StatefulWidget {
  const AdminTranslationExchangePage({
    super.key,
    required this.session,
    required this.locale,
    required this.kind,
  });
  final AppSession session;
  final String locale, kind;
  @override
  State<AdminTranslationExchangePage> createState() => _ExchangeState();
}

class _ExchangeState extends State<AdminTranslationExchangePage> {
  final _text = TextEditingController();
  bool _busy = false;
  bool _review = false;
  String? _error, _validated;
  int _page = 1, _count = 0;
  Map<String, dynamic>? _export;

  @override
  void initState() {
    super.initState();
    _review =
        !widget.session.can(
          widget.kind == 'ui' ? 'translations.edit' : 'content.edit',
        ) &&
        widget.session.can('review');
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _validated = null;
    });
    try {
      final data = await widget.session.adminRequest(
        'GET',
        'languages/${widget.locale}/translations/export?kind=${widget.kind}&page=$_page',
      );
      if (!mounted) return;
      setState(() {
        _export = data;
        _text.text = const JsonEncoder.withIndent('  ').convert(data);
      });
    } catch (e) {
      if (mounted) setState(() => _error = adminError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit({required bool apply}) async {
    if (_busy || (apply && _validated != _text.text)) return;
    final raw = _text.text;
    if (utf8.encode(raw).length > 5 * 1024 * 1024) {
      setState(() => _error = 'exchange.invalid');
      return;
    }
    Map<String, dynamic> package;
    try {
      package = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      setState(() => _error = 'exchange.invalid');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.session.adminRequest(
        'POST',
        'languages/${widget.locale}/translations/${_review ? "review" : "import"}',
        data: {'package': package, 'dry_run': !apply},
      );
      if (!mounted) return;
      setState(() {
        _count = result['count'] as int;
        _validated = apply ? null : raw;
      });
      if (apply) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(_review ? 'exchange.reviewed' : 'exchange.saved'),
              ),
            ),
          );
        }
        // Old revisions cannot be submitted again accidentally after success.
        _text.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = adminError(e);
          _validated = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminSessionBoundary(
    session: widget.session,
    child: Scaffold(
      appBar: AppBar(title: Text(context.tr('exchange.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr(
              _review ? 'exchange.reviewInstructions' : 'exchange.instructions',
            ),
          ),
          if (widget.session.can('review'))
            SwitchListTile(
              title: Text(context.tr('exchange.reviewMode')),
              value: _review,
              onChanged:
                  _busy ||
                      !widget.session.can(
                        widget.kind == 'ui'
                            ? 'translations.edit'
                            : 'content.edit',
                      )
                  ? null
                  : (value) => setState(() {
                      _review = value;
                      _validated = null;
                    }),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _load,
                child: Text(context.tr('exchange.export')),
              ),
              OutlinedButton(
                onPressed: _busy || _text.text.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: _text.text),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.tr('exchange.copied')),
                            ),
                          );
                        }
                      },
                child: Text(context.tr('exchange.copy')),
              ),
              IconButton(
                tooltip: context.tr('exchange.previous'),
                onPressed: _busy || _page <= 1
                    ? null
                    : () {
                        _page--;
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Padding(padding: const EdgeInsets.all(12), child: Text('$_page')),
              IconButton(
                tooltip: context.tr('exchange.next'),
                onPressed:
                    _busy ||
                        _export == null ||
                        _page * (_export!['per_page'] as int) >=
                            (_export!['total'] as int)
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              context.tr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            enabled: !_busy,
            minLines: 8,
            maxLines: 18,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: context.tr('exchange.document'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _validated = null),
          ),
          const SizedBox(height: 12),
          if (_validated != null)
            Text(
              context.tr(
                _review ? 'exchange.validReview' : 'exchange.valid',
                args: {'count': _count},
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _busy || _text.text.isEmpty
                    ? null
                    : () => _submit(apply: false),
                child: Text(
                  context.tr(
                    _review ? 'exchange.previewReview' : 'exchange.preview',
                  ),
                ),
              ),
              FilledButton(
                onPressed:
                    _busy || _validated != _text.text || _validated == null
                    ? null
                    : () => _submit(apply: true),
                child: Text(
                  context.tr(_review ? 'exchange.review' : 'exchange.apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

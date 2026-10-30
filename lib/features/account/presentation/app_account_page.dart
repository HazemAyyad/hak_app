import 'package:flutter/material.dart';
import '../../../core/localization/app_localization.dart';
import '../data/app_session.dart';
import '../data/google_account.dart';

class AppAccountPage extends StatefulWidget {
  const AppAccountPage({super.key, required this.session, this.link = false});
  final AppSession session;
  final bool link;
  @override
  State<AppAccountPage> createState() => _AppAccountPageState();
}

class _AppAccountPageState extends State<AppAccountPage> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  String _provider = 'association';
  @override
  void initState() {
    super.initState();
    if (widget.link) {
      _provider = widget.session.areas.contains('association')
          ? 'religious'
          : 'association';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _currentPassword.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    String? google;
    if (widget.link &&
        widget.session.areas.single == 'religious' &&
        widget.session.religious.profile?['password_enabled'] == false) {
      google = await HaqGoogleAccount.token(fresh: true);
      if (google == null) return;
    }
    final ok = widget.link
        ? await widget.session.link(
            _provider,
            _email.text,
            _password.text,
            _currentPassword.text,
            currentGoogleToken: google,
          )
        : await widget.session.login(_provider, _email.text, _password.text);
    _password.clear();
    _currentPassword.clear();
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(context.tr('account.title'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _provider,
              isExpanded: true,
              items: [
                for (final provider in ['association', 'religious'])
                  DropdownMenuItem(
                    value: provider,
                    child: Text(context.tr('account.$provider')),
                  ),
              ],
              onChanged: widget.session.busy || widget.link
                  ? null
                  : (value) => setState(() => _provider = value!),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                widget.link ? 'account.linkHelp' : 'account.providerHelp',
              ),
            ),
            const SizedBox(height: 12),
            if (widget.link &&
                !(widget.session.areas.single == 'religious' &&
                    widget.session.religious.profile?['password_enabled'] ==
                        false))
              TextFormField(
                controller: _currentPassword,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.tr('account.currentPassword'),
                ),
                validator: (value) => (value ?? '').isNotEmpty
                    ? null
                    : context.tr('account.currentPassword'),
              ),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.username],
              decoration: InputDecoration(
                labelText: context.tr(
                  widget.link ? 'account.otherEmail' : 'account.email',
                ),
              ),
              validator: (value) => (value ?? '').contains('@')
                  ? null
                  : context.tr('account.email'),
            ),
            TextFormField(
              controller: _password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: context.tr(
                  widget.link ? 'account.otherPassword' : 'account.password',
                ),
              ),
              onFieldSubmitted: (_) {
                if (!widget.session.busy) _login();
              },
              validator: (value) => (value ?? '').isNotEmpty
                  ? null
                  : context.tr('account.password'),
            ),
            if (widget.session.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  context.tr(widget.session.error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: widget.session.busy ? null : _login,
              child: Text(
                context.tr(
                  widget.session.busy
                      ? 'common.loading'
                      : widget.link
                      ? 'account.link'
                      : 'account.login',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

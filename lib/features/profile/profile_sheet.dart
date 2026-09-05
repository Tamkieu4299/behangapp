import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/backend/backend.dart' show UserProfile;
import '../../core/services/app_settings.dart';
import '../../state/journey_controller.dart';
import '../../state/recap_controller.dart';

const _avatarChoices = [
  '🌱', '🍼', '💪', '🎾', '✈️', '⭐', '🔥', '🐼', '🌸', '🎸', '🐳', '🦊',
];

class ProfileSheet extends StatefulWidget {
  const ProfileSheet({super.key});

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _avatar = _avatarChoices.first;
  bool _createAccount = true;
  bool _busy = false;
  String? _error;
  bool _formInitialized = false;

  double _clipSeconds = 1.0;

  @override
  void initState() {
    super.initState();
    AppSettings.loadClipSeconds().then((seconds) {
      if (mounted) setState(() => _clipSeconds = seconds);
    });
  }

  void _setClipSeconds(double seconds) {
    setState(() => _clipSeconds = seconds);
    AppSettings.setClipSeconds(seconds);
    context.read<RecapController>().refreshClipSeconds();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _fillFromProfile(UserProfile profile) {
    if (_formInitialized) return;
    _formInitialized = true;
    _nameController.text = profile.displayName;
    _avatar = profile.avatar;
  }

  Future<void> _submitAuth(JourneyController state) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await state.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
        avatar: _avatar,
        createAccount: _createAccount,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _saveLocalProfile(JourneyController state) async {
    await state.updateProfile(UserProfile(
      uid: state.profile?.uid ?? 'local-user',
      displayName:
          _nameController.text.trim().isEmpty ? 'You' : _nameController.text.trim(),
      avatar: _avatar,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<JourneyController>();
    final scheme = Theme.of(context).colorScheme;
    final profile = state.profile;
    if (profile != null) _fillFromProfile(profile);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your profile',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            if (!state.cloudReady)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Offline mode. Run flutterfire configure and restart to enable '
                  'accounts, invites and shared journeys.',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final avatar in _avatarChoices)
                  ChoiceChip(
                    label: Text(avatar),
                    selected: _avatar == avatar,
                    showCheckmark: false,
                    labelStyle: const TextStyle(fontSize: 18),
                    onSelected: (_) => setState(() => _avatar = avatar),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            Text(
              'Daily clip length',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<double>(
                segments: [
                  for (final seconds in AppSettings.clipChoices)
                    ButtonSegment(
                      value: seconds,
                      label: Text('${seconds.toStringAsFixed(0)}s'),
                    ),
                ],
                selected: {_clipSeconds},
                onSelectionChanged: (selection) =>
                    _setClipSeconds(selection.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                'New videos are trimmed to this length and appended to your recaps.',
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).colorScheme.outline),
              ),
            ),
            if (state.cloudReady && profile == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_createAccount
                    ? 'Create new account'
                    : 'Sign in to existing account'),
                value: _createAccount,
                onChanged: (v) => setState(() => _createAccount = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!,
                      style:
                          TextStyle(color: scheme.error, fontSize: 12)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : () => _submitAuth(state),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_createAccount
                          ? 'Create account'
                          : 'Sign in'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.cloudReady
                          ? () async {
                              await state.signOut();
                            }
                          : null,
                      child: const Text('Sign out'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _saveLocalProfile(state),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

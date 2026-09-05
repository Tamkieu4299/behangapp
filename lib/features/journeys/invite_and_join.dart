import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/journey_controller.dart';

class JoinJourneyDialog extends StatefulWidget {
  const JoinJourneyDialog({super.key});

  @override
  State<JoinJourneyDialog> createState() => _JoinJourneyDialogState();
}

class _JoinJourneyDialogState extends State<JoinJourneyDialog> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final journeys = context.read<JourneyController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final journeyId = await journeys.joinWithCode(_codeController.text);
      if (!mounted) return;
      if (journeyId == null) {
        setState(() {
          _error = 'No journey found for that code.';
          _busy = false;
        });
        return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not join right now. Check your connection.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a journey'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter the 6-character code a friend shared with you.'),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4),
            decoration: const InputDecoration(
                counterText: '', hintText: 'ABC123'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _codeController.text.trim().length == 6 && !_busy
                  ? _join
                  : null,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Join'),
        ),
      ],
    );
  }
}

class InviteSheet extends StatefulWidget {
  final String journeyId;

  const InviteSheet({super.key, required this.journeyId});

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  String? _code;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  Future<void> _loadCode() async {
    final journeys = context.read<JourneyController>();
    try {
      final code = await journeys.inviteCode(widget.journeyId);
      if (mounted) setState(() => _code = code);
    } catch (_) {
      if (mounted) {
        setState(() => _hint =
            'Invites need cloud sync. Set up Firebase (flutterfire configure) '
            'and restart the app to share this journey.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invite someone',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('They can add moments and watch recaps together with you.',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
            const SizedBox(height: 16),
            if (_hint != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_hint!,
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
              )
            else if (_code == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _code!,
                    style: TextStyle(
                      fontSize: 30,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w900,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _code!));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code copied')));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        SharePlus.instance.share(ShareParams(
                            text:
                                'Join my journey on Behang! Open the app, tap the link icon and enter code $_code'));
                      },
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Share'),
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

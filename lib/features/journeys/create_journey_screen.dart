import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../app_state.dart';
import '../../core/models/journey.dart';

class CreateJourneyScreen extends StatefulWidget {
  const CreateJourneyScreen({super.key});

  @override
  State<CreateJourneyScreen> createState() => _CreateJourneyScreenState();
}

class _CreateJourneyScreenState extends State<CreateJourneyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _goalController = TextEditingController();

  JourneyCategory _category = JourneyCategory.personal;
  DateTime _startDate = DateTime.now();
  int? _durationDays;
  TimeOfDay? _reminder;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New journey')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'What are you tracking? e.g. "Baby\'s First Year"',
                  labelText: 'Title',
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Give your journey a title'
                        : null,
              ),
              const SizedBox(height: 20),
              Text('Category',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in JourneyCategory.values)
                    ChoiceChip(
                      label: Text('${category.emoji} ${category.label}'),
                      selected: _category == category,
                      onSelected: (_) =>
                          setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _goalController,
                decoration: const InputDecoration(
                  labelText: 'Goal (optional)',
                  hintText: 'e.g. "First steps before turning one"',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Start date'),
                subtitle: Text(DateFormat('EEE, MMM d, y').format(_startDate)),
                onTap: _pickStartDate,
              ),
              DropdownButtonFormField<int?>(
                initialValue: _durationDays,
                decoration:
                    const InputDecoration(labelText: 'Duration'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Open-ended'),
                  ),
                  ...[
                    (30, '30 days'),
                    (90, '3 months'),
                    (180, '6 months'),
                    (365, '1 year'),
                  ].map((e) => DropdownMenuItem(
                        value: e.$1,
                        child: Text(e.$2),
                      )),
                ],
                onChanged: (value) => setState(() => _durationDays = value),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily reminder'),
                subtitle: Text(
                  _reminder == null
                      ? 'Get a push notification each day'
                      : 'Every day at ${_reminder!.format(context)}',
                ),
                value: _reminder != null,
                onChanged: (on) async {
                  if (!on) {
                    setState(() => _reminder = null);
                    return;
                  }
                  await _pickReminder(initial: const TimeOfDay(hour: 20, minute: 0));
                },
              ),
              if (_reminder != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Remind me at'),
                  trailing: Text(
                    _reminder!.format(context),
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                  ),
                  onTap: () => _pickReminder(),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start journey',
                        style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickReminder({TimeOfDay? initial}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? _reminder ?? const TimeOfDay(hour: 20, minute: 0),
    );
    if (picked != null && mounted) setState(() => _reminder = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString('user_id');
    if (userId == null) {
      userId = const Uuid().v4();
      await prefs.setString('user_id', userId);
    }

    final goal = _goalController.text.trim();
    if (!mounted) return;
    final state = context.read<AppState>();
    final journey = Journey(
      id: const Uuid().v4(),
      userId: userId,
      title: _titleController.text.trim(),
      category: _category,
      goal: goal.isEmpty ? null : goal,
      startDate: _startDate,
      durationDays: _durationDays,
      reminderHour: _reminder?.hour,
      reminderMinute: _reminder?.minute,
      createdAt: DateTime.now(),
    );

    await state.createJourney(journey);
    if (!mounted) return;
    Navigator.pop(context);
  }
}

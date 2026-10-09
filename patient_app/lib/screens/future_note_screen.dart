import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

/// A private note the person leaves for a harder day. Between surfaces it back
/// to them after a low check-in. Writing is a Premium / clinician-covered perk;
/// reading what you've saved is always available.
class FutureNoteScreen extends StatefulWidget {
  const FutureNoteScreen({super.key});

  @override
  State<FutureNoteScreen> createState() => _FutureNoteScreenState();
}

class _FutureNoteScreenState extends State<FutureNoteScreen> {
  final _text = TextEditingController();
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final n = await context.read<AppState>().fetchFutureNotes();
      if (!mounted) return;
      setState(() {
        _notes = n;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await app.createFutureNote(body);
      _text.clear();
      await _load();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(app.s.noteSaved)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id) async {
    final app = context.read<AppState>();
    try {
      await app.deleteFutureNote(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.s;
    final canWrite = state.patient!.canWriteFutureNote;
    return Scaffold(
      appBar: AppBar(title: Text(s.futureNoteTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(s.futureNoteIntro,
                style: const TextStyle(
                    fontSize: 15, height: 1.5, color: BtwColors.inkSoft)),
            const SizedBox(height: 18),
            if (canWrite) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: BtwColors.line),
                ),
                padding: const EdgeInsets.all(6),
                child: TextField(
                  controller: _text,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  style: const TextStyle(fontSize: 15.5, height: 1.45),
                  decoration: InputDecoration(
                    hintText: s.futureNoteHint,
                    hintStyle: const TextStyle(color: BtwColors.inkSoft),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? s.sending : s.saveNote),
              ),
            ] else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: BtwColors.mossLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(s.futureNotePremium,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.45, color: BtwColors.ink)),
              ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: BtwColors.moss),
              ))
            else if (_notes.isEmpty)
              Text(s.futureNoteEmpty,
                  style: const TextStyle(fontSize: 14, color: BtwColors.inkSoft))
            else
              for (final n in _notes) _noteCard(s, n),
          ],
        ),
      ),
    );
  }

  Widget _noteCard(S s, Map<String, dynamic> n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BtwColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((n['body'] as String?) ?? '',
              style: const TextStyle(fontSize: 15, height: 1.5)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _delete((n['id'] as String)),
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 16, color: BtwColors.inkSoft),
              label: Text(s.delete,
                  style: const TextStyle(
                      fontSize: 12.5, color: BtwColors.inkSoft)),
            ),
          ),
        ],
      ),
    );
  }
}

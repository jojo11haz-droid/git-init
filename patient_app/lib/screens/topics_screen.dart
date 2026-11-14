import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../discipline.dart';
import '../theme.dart';

/// Things to bring up at the next session, the same list as on the website.
/// Their professional sees the open ones in Session prep and marks them talked
/// about. Only shown to someone who has a professional.
class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  final _ctrl = TextEditingController();
  List<SessionTopic> _topics = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AppState>().fetchTopics();
      if (!mounted) return;
      setState(() {
        _topics = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _add() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final t = await context.read<AppState>().addTopic(body);
      if (!mounted) return;
      setState(() {
        _topics = [t, ..._topics];
        _ctrl.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(SessionTopic t) async {
    try {
      await context.read<AppState>().deleteTopic(t.id);
      if (!mounted) return;
      setState(() => _topics = _topics.where((x) => x.id != t.id).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.s;
    final patient = app.patient;
    final isBody = patient != null && profileFor(patient).isBody;
    final open = _topics.where((t) => !t.discussed).toList();
    final done = _topics.where((t) => t.discussed).take(5).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.topicsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(s.topicsSub,
                style: const TextStyle(
                    fontSize: 14.5, height: 1.5, color: BtwColors.inkSoft)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    maxLength: 300,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      hintText: isBody ? s.topicsHintBody : s.topicsHint,
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _add,
                  child: Text(s.topicsAdd),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(fontSize: 13, color: BtwColors.clay)),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator()))
            else if (open.isEmpty && done.isEmpty)
              Text(s.topicsNone,
                  style: const TextStyle(fontSize: 14, color: BtwColors.inkSoft))
            else ...[
              for (final t in open)
                _row(t, trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: BtwColors.inkSoft,
                  onPressed: () => _remove(t),
                )),
              for (final t in done)
                _row(t,
                    trailing: Text(s.topicsTalkedAbout,
                        style: const TextStyle(
                            fontSize: 12, color: BtwColors.inkSoft)),
                    faded: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(SessionTopic t, {required Widget trailing, bool faded = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BtwColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(t.body,
                style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: faded ? BtwColors.inkSoft : BtwColors.ink,
                    decoration: faded ? TextDecoration.lineThrough : null)),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

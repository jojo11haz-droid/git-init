import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../strings.dart';
import '../theme.dart';

/// Documents the patient shares with their clinician — a referral, intake form,
/// or note. The patient photographs or picks an image; Between reviews it (when
/// AI is on) so the clinician starts from a summary, not a blank page. The AI
/// summary shown here is the same one the clinician sees — transparent by design.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late Future<List<PatientDocument>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().fetchDocuments();
  }

  void _reload() {
    setState(() => _future = context.read<AppState>().fetchDocuments());
  }

  Future<void> _add() async {
    final app = context.read<AppState>();
    final s = app.s;
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: BtwColors.moss),
              title: Text(s.takePhoto),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: BtwColors.moss),
              title: Text(s.chooseFromLibrary),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 2000, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _busy = true);
      final name = file.name.isNotEmpty
          ? file.name
          : 'document-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await app.uploadDocument(bytes, 'image/jpeg', name);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.documentAdded)));
      _reload();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PatientDocument doc) async {
    final app = context.read<AppState>();
    final s = app.s;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.deleteDocumentConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(s.cancel)),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s.deleteAction)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.deleteDocument(doc.id);
      _reload();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String? _statusLine(S s, PatientDocument d) {
    switch (d.aiStatus) {
      case 'pending':
        return s.documentReviewPending;
      case 'skipped':
        return s.documentReviewOff;
      case 'error':
        return s.documentReviewError;
      default:
        return null;
    }
  }

  Widget _card(S s, PatientDocument d) {
    final who =
        d.uploadedBy == 'clinician' ? s.documentAddedByClinician : s.documentSharedByYou;
    final status = _statusLine(s, d);
    final highlights = d.highlights;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: BtwColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  d.kind == 'pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.image_outlined,
                  size: 18,
                  color: BtwColors.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.filename ?? s.documentsTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: BtwColors.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: s.deleteAction,
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: BtwColors.clay),
                onPressed: () => _delete(d),
              ),
            ],
          ),
          Text(who,
              style: const TextStyle(fontSize: 12, color: BtwColors.inkSoft)),
          if (d.aiStatus == 'done') ...[
            const SizedBox(height: 8),
            if ((d.aiSummary ?? '').isNotEmpty)
              Text(d.aiSummary!,
                  style: const TextStyle(
                      fontSize: 13, height: 1.4, color: BtwColors.ink)),
            if ((d.primaryConcern ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(d.primaryConcern!,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: BtwColors.ink,
                      fontWeight: FontWeight.w600)),
            ],
            for (final h in highlights)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${h.key}: ${h.value}',
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.35, color: BtwColors.inkSoft)),
              ),
          ] else if (status != null) ...[
            const SizedBox(height: 6),
            Text(status,
                style:
                    const TextStyle(fontSize: 12, color: BtwColors.inkSoft)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.documentsTitle), actions: const [
        Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: LanguageToggle())),
      ]),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(s.documentsIntro,
                  style: const TextStyle(
                      fontSize: 13, height: 1.5, color: BtwColors.inkSoft)),
            ),
            Expanded(
              child: FutureBuilder<List<PatientDocument>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString()));
                  }
                  final docs = snapshot.data ?? const <PatientDocument>[];
                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(s.documentsEmpty,
                            style:
                                const TextStyle(color: BtwColors.inkSoft)),
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    children: [for (final d in docs) _card(s, d)],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _add,
        backgroundColor: BtwColors.moss,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add, color: Colors.white),
        label: Text(_busy ? s.documentUploading : s.addDocument,
            style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

/// Share / import public credentials via QR payload and short code.
class CredentialsScreen extends StatefulWidget {
  final MeshController mesh;

  const CredentialsScreen({super.key, required this.mesh});

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _importCtrl = TextEditingController();
  String? _importError;
  String? _importOk;
  bool _busy = false;

  MeshController get mesh => widget.mesh;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _importCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await mesh.refreshLocalCredential();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      await mesh.publishCredentialOffer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Published offer ${mesh.localCredential?.shortCode ?? ""}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _importError = null;
      _importOk = null;
    });
    try {
      final cred = await mesh.importCredential(_importCtrl.text);
      if (cred != null && mounted) {
        setState(() {
          _importOk =
              'Trusted ${cred.displayName.isEmpty ? cred.subjectId : cred.displayName} (${cred.shortCode})';
          _importCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _importError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Share'),
            Tab(text: 'Import'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildShare(),
              _buildImport(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShare() {
    final cred = mesh.localCredential;
    final id = mesh.identity;
    if (cred == null || id == null) {
      return Center(
        child: _busy
            ? const CircularProgressIndicator()
            : TextButton(
                onPressed: _refresh, child: const Text('Prepare share')),
      );
    }

    final payload = cred.toQrPayload();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Quick credential exchange',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Show this QR or short code to a nearby peer. They import it to trust '
          'your public keys for secure sessions. Private keys never leave the device.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        CredentialQrCard(payload: payload),
        const SizedBox(height: 12),
        ShortCodeBadge(
          shortCode: cred.shortCode,
          subtitle: 'Also publish over mesh so peers can type this code',
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Device'),
          subtitle: Text(
            '${id.displayName.isEmpty ? "Unnamed" : id.displayName}\n${id.id}',
          ),
          isThreeLine: true,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _publish,
          icon: const Icon(Icons.cell_tower),
          label: const Text('Publish offer on mesh'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Regenerate payload'),
        ),
      ],
    );
  }

  Widget _buildImport() {
    final offers = mesh.offerCache.all;
    final trusted = mesh.trustedCredentials.values.toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Import credentials',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Paste a QR payload (zvcomm:cred:v1:…) or enter a short code after '
          'the peer publishes an offer on the mesh.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _importCtrl,
          decoration: const InputDecoration(
            labelText: 'QR payload or short code',
            hintText: 'AB3K-9F2M  or  zvcomm:cred:v1:…',
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _import(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Import & trust'),
        ),
        if (_importError != null) ...[
          const SizedBox(height: 8),
          Text(
            _importError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_importOk != null) ...[
          const SizedBox(height: 8),
          Text(
            _importOk!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Mesh offers (${offers.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (offers.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No offers yet'),
            subtitle:
                Text('When a peer publishes, their short code appears here'),
          )
        else
          for (final o in offers)
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: Text(o.displayName.isEmpty ? o.subjectId : o.displayName),
              subtitle: Text('${o.shortCode} · ${o.subjectId}'),
              trailing: IconButton(
                tooltip: 'Trust',
                icon: const Icon(Icons.verified_user_outlined),
                onPressed: () async {
                  _importCtrl.text = o.toQrPayload();
                  await _import();
                },
              ),
            ),
        const SizedBox(height: 16),
        Text(
          'Trusted (${trusted.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (trusted.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No trusted peers yet'),
          )
        else
          for (final c in trusted)
            ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(c.displayName.isEmpty ? c.subjectId : c.displayName),
              subtitle: Text('${c.shortCode} · ${c.subjectId}'),
            ),
      ],
    );
  }
}

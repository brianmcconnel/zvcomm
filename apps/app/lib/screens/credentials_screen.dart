import 'package:flutter/material.dart';
import 'package:pki/pki.dart';
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
  final _orgCtrl = TextEditingController();
  final _certCtrl = TextEditingController();
  String? _importError;
  String? _importOk;
  String? _orgError;
  String? _orgOk;
  String? _certError;
  String? _certOk;
  bool _busy = false;
  OrganizationCategory _selectedCategory = OrganizationCategory.other;

  MeshController get mesh => widget.mesh;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _importCtrl.dispose();
    _orgCtrl.dispose();
    _certCtrl.dispose();
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

  Future<void> _nfcShare() async {
    setState(() => _busy = true);
    try {
      await mesh.shareCredentialViaNfc();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NFC share ready — hold phones together'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NFC share failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _nfcReceive() async {
    setState(() => _busy = true);
    try {
      await mesh.receiveCredentialViaNfc();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NFC receive ready — hold near peer or tag'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NFC receive failed: $e')),
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

  Future<void> _trustOrg() async {
    setState(() {
      _busy = true;
      _orgError = null;
      _orgOk = null;
    });
    try {
      final org = await mesh.trustOrganization(
        _orgCtrl.text,
        category: _selectedCategory,
      );
      if (mounted) {
        setState(() {
          _orgOk =
              'Trusted ${org.name} · ${org.category.label} (${org.shortCode})';
          _orgCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _orgError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trustCert() async {
    setState(() {
      _busy = true;
      _certError = null;
      _certOk = null;
    });
    try {
      final d = await mesh.trustExternalCertificateJson(_certCtrl.text);
      if (mounted) {
        if (d.isTrusted) {
          setState(() {
            _certOk =
                'External ${d.subjectId} via ${d.organizationName ?? "org"}';
            _certCtrl.clear();
          });
        } else {
          setState(() => _certError = d.detail ?? 'Rejected');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _certError = e.toString());
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
            Tab(text: 'Orgs'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildShare(),
              _buildImport(),
              _buildOrgs(),
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
          'Show this QR, short code, or use NFC tap to a nearby peer. '
          'They import it to trust your public keys for secure sessions. '
          'Private keys never leave the device.',
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
        Text('NFC', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          mesh.nfcAvailable
              ? (mesh.nfcCredentialArmed
                  ? 'NFC session armed — hold phones together (or cancel).'
                  : 'Tap to write your credential on the next NFC contact.')
              : 'Enable the NFC plugin in Settings (phone with NFC required).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: (_busy || !mesh.nfcAvailable) ? null : _nfcShare,
          icon: const Icon(Icons.nfc),
          label: Text(
            mesh.nfcCredentialArmed ? 'NFC share armed…' : 'Share via NFC tap',
          ),
        ),
        if (mesh.nfcCredentialArmed) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              mesh.cancelNfcCredentialExchange();
              setState(() {});
            },
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel NFC'),
          ),
        ],
        const SizedBox(height: 16),
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
          'Paste a QR payload (zvcomm:cred:v1:…), enter a short code after '
          'the peer publishes on mesh, or receive via NFC tap.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: (_busy || !mesh.nfcAvailable) ? null : _nfcReceive,
          icon: const Icon(Icons.nfc),
          label: const Text('Receive via NFC tap'),
        ),
        if (!mesh.nfcAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'NFC plugin off or no radio — enable in Settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
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
              subtitle: Text('${c.shortCode} · ${c.subjectId} · direct'),
            ),
        // Org-issued externals
        ...mesh.trustStore.externalCerts.entries.map((e) {
          final cert = e.value;
          final orgId = mesh.trustStore.externalOrgBySubject[e.key];
          final org =
              orgId != null ? mesh.trustStore.organizations[orgId] : null;
          return ListTile(
            leading: const Icon(Icons.apartment),
            title: Text(cert.subjectId),
            subtitle: Text(
              'via ${org?.name ?? cert.issuerId} · serial ${cert.serial}',
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOrgs() {
    final byCategory =
        mesh.trustStore.organizationsByCategory(includeEmpty: true);
    final total = mesh.trustStore.organizations.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Organizations',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Trust an organization CA to accept certificates it issues for '
          'external devices — without exchanging keys with each person. '
          'Group by Government, Churches, Families, Companies, Non-Profits, or Other.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<OrganizationCategory>(
          // ignore: deprecated_member_use — value is still valid on stable
          value: _selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final c in OrganizationCategory.displayOrder)
              DropdownMenuItem(value: c, child: Text(c.label)),
          ],
          onChanged: (c) {
            if (c != null) setState(() => _selectedCategory = c);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _orgCtrl,
          decoration: const InputDecoration(
            labelText: 'Organization payload',
            hintText: 'zvcomm:org:v1:…  or  org JSON  or  CA cred URI',
            border: OutlineInputBorder(),
          ),
          minLines: 2,
          maxLines: 5,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _trustOrg,
          icon: const Icon(Icons.domain_add),
          label: const Text('Trust organization'),
        ),
        if (_orgError != null) ...[
          const SizedBox(height: 8),
          Text(
            _orgError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_orgOk != null) ...[
          const SizedBox(height: 8),
          Text(
            _orgOk!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Import external certificate',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Paste a MeshCertificate JSON issued by a trusted org.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _certCtrl,
          decoration: const InputDecoration(
            labelText: 'Certificate JSON',
            hintText: '{ "subjectId": …, "issuerId": … }',
            border: OutlineInputBorder(),
          ),
          minLines: 3,
          maxLines: 8,
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _trustCert,
          icon: const Icon(Icons.badge_outlined),
          label: const Text('Trust external cert'),
        ),
        if (_certError != null) ...[
          const SizedBox(height: 8),
          Text(
            _certError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_certOk != null) ...[
          const SizedBox(height: 8),
          Text(
            _certOk!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Trusted orgs ($total)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (total == 0)
          const ListTile(
            dense: true,
            title: Text('No organizations yet'),
            subtitle: Text('Import an org QR / CA root to trust externals'),
          )
        else
          for (final cat in OrganizationCategory.displayOrder) ...[
            const SizedBox(height: 12),
            _CategoryHeader(
              category: cat,
              count: byCategory[cat]?.length ?? 0,
            ),
            if ((byCategory[cat] ?? const []).isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  'None',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              )
            else
              for (final o in byCategory[cat]!)
                ListTile(
                  leading: Icon(_iconForCategory(o.category)),
                  title: Text(o.name),
                  subtitle: Text(
                    '${o.shortCode} · ${o.id}\n'
                    '${o.description ?? "Allows: ${o.allowCapabilities.join(", ")}"}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<OrganizationCategory>(
                        tooltip: 'Change category',
                        icon: const Icon(Icons.drive_file_move_outline),
                        onSelected: (c) {
                          mesh.setOrganizationCategory(o.id, c);
                          setState(() {});
                        },
                        itemBuilder: (context) => [
                          for (final c in OrganizationCategory.displayOrder)
                            PopupMenuItem(
                              value: c,
                              child: Text(
                                c.label,
                                style: TextStyle(
                                  fontWeight: c == o.category
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          mesh.untrustOrganization(o.id);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
          ],
      ],
    );
  }

  static IconData _iconForCategory(OrganizationCategory c) => switch (c) {
        OrganizationCategory.government => Icons.account_balance,
        OrganizationCategory.churches => Icons.church,
        OrganizationCategory.families => Icons.family_restroom,
        OrganizationCategory.companies => Icons.business,
        OrganizationCategory.nonProfits => Icons.volunteer_activism,
        OrganizationCategory.other => Icons.domain,
      };
}

class _CategoryHeader extends StatelessWidget {
  final OrganizationCategory category;
  final int count;

  const _CategoryHeader({required this.category, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          _CredentialsScreenState._iconForCategory(category),
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          '${category.label} ($count)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

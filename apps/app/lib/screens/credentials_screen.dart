import 'package:flutter/material.dart';
import 'package:core/core.dart';
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
  final _orgNameCtrl = TextEditingController();
  final _memberCredCtrl = TextEditingController();
  final _issuerGrantCtrl = TextEditingController();
  final _issuerSubjectCtrl = TextEditingController();
  String? _importError;
  String? _importOk;
  String? _orgError;
  String? _orgOk;
  String? _certError;
  String? _certOk;
  String? _issuerError;
  String? _issuerOk;
  bool _busy = false;
  OrganizationCategory _selectedCategory = OrganizationCategory.companies;

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
    _orgNameCtrl.dispose();
    _memberCredCtrl.dispose();
    _issuerGrantCtrl.dispose();
    _issuerSubjectCtrl.dispose();
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
      // Preserve category from QR/JSON/mesh offer; do not force the create-form
      // dropdown (that would reclassify every import as the last create choice).
      final org = await mesh.trustOrganization(_orgCtrl.text);
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

  Future<void> _createOrg() async {
    final name = _orgNameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _orgError = 'Enter an organization name');
      return;
    }
    setState(() {
      _busy = true;
      _orgError = null;
      _orgOk = null;
    });
    try {
      final org = await mesh.createOrganization(
        name: name,
        category: _selectedCategory,
      );
      if (mounted) {
        setState(() {
          _orgOk =
              'Created ${org.name} · ${org.category.label} · ${org.shortCode}';
          _orgNameCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _orgError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishOrg(Organization org) async {
    setState(() => _busy = true);
    try {
      await mesh.publishOrganizationOffer(org);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Published org ${org.shortCode} on mesh')),
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

  Future<void> _nfcShareOrg(Organization org) async {
    setState(() => _busy = true);
    try {
      await mesh.shareOrganizationViaNfc(org);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NFC org share armed · ${org.shortCode}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('NFC org share failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issueMember(Organization org) async {
    setState(() {
      _busy = true;
      _certError = null;
      _certOk = null;
    });
    try {
      final member = PublicCredential.parse(_memberCredCtrl.text.trim());
      final pack = await mesh.issueOrganizationMemberPackage(
        orgId: org.id,
        member: member,
      );
      if (mounted) {
        setState(() {
          _certOk =
              'Issued cert serial ${pack.certificate.serial} for ${member.subjectId}';
          _certCtrl.text = pack.toJsonString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member package ready — copy JSON to share'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _certError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issueIssuerGrant(Organization org) async {
    setState(() {
      _busy = true;
      _issuerError = null;
      _issuerOk = null;
    });
    try {
      final member = PublicCredential.parse(_issuerSubjectCtrl.text.trim());
      final grant = await mesh.issueIssuerAuthority(
        orgId: org.id,
        member: member,
      );
      if (mounted) {
        setState(() {
          _issuerOk =
              'Granted issuer to ${member.displayName.isEmpty ? member.subjectId : member.displayName}';
          _issuerGrantCtrl.text = grant.toQrPayload();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Issuer grant ready — share QR/payload with them'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _issuerError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _becomeIssuer() async {
    setState(() {
      _busy = true;
      _issuerError = null;
      _issuerOk = null;
    });
    try {
      final org = await mesh.becomeOrgIssuer(_issuerGrantCtrl.text);
      if (mounted) {
        setState(() {
          _issuerOk =
              'You can now issue for ${org.name} · ${org.category.label}';
          _issuerGrantCtrl.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Became issuer for ${org.name}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _issuerError = e.toString());
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
        CredentialQrCard(payload: payload),
        const SizedBox(height: 12),
        ShortCodeBadge(shortCode: cred.shortCode),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _publish,
              icon: const Icon(Icons.cell_tower),
              label: const Text('Publish'),
            ),
            if (mesh.nfcAvailable)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _nfcShare,
                icon: const Icon(Icons.nfc),
                label: Text(
                  mesh.nfcCredentialArmed ? 'NFC armed' : 'NFC',
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'refresh') _refresh();
                if (v == 'cancel_nfc') {
                  mesh.cancelNfcCredentialExchange();
                  setState(() {});
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: Text('Regenerate'),
                ),
                if (mesh.nfcCredentialArmed)
                  const PopupMenuItem(
                    value: 'cancel_nfc',
                    child: Text('Cancel NFC'),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_horiz),
              ),
            ),
          ],
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
        if (mesh.nfcAvailable)
          FilledButton.tonalIcon(
            onPressed: (_busy || !mesh.nfcAvailable) ? null : _nfcReceive,
            icon: const Icon(Icons.nfc),
            label: const Text('Receive via NFC'),
          ),
        if (mesh.nfcAvailable) const SizedBox(height: 12),
        Text(
          'Trust only via QR or NFC public keys. Nearby radio ads never grant trust.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _importCtrl,
          decoration: const InputDecoration(
            labelText: 'QR public-key payload',
            hintText: 'zvcomm:cred:v1:… (from QR scan or paste)',
            border: OutlineInputBorder(),
          ),
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _import,
          icon: const Icon(Icons.person_add),
          label: const Text('Trust from QR'),
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
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Nearby (not trusted)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Seen on the mesh only. Scan their QR or use NFC to trust — '
            'do not trust from radio proximity.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final o in offers)
            ListTile(
              dense: true,
              leading: const Icon(Icons.sensors),
              title: Text(o.displayName.isEmpty ? o.subjectId : o.displayName),
              subtitle: Text('${o.shortCode} · untrusted advertisement'),
            ),
        ],
        if (trusted.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Trusted (QR / NFC)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final c in trusted)
            ListTile(
              dense: true,
              leading: const Icon(Icons.verified_user),
              title: Text(c.displayName.isEmpty ? c.subjectId : c.displayName),
              subtitle: Text('${c.shortCode} · public key exchanged'),
            ),
        ],
      ],
    );
  }

  Widget _buildOrgs() {
    final byCategory =
        mesh.trustStore.organizationsByCategory(includeEmpty: true);
    final total = mesh.trustStore.organizations.length;
    final sharing = mesh.sharingOrganization;
    final orgOffers = mesh.orgOfferCache.all;
    final canIssue = sharing != null && mesh.canIssueForOrg(sharing.id);
    final isRoot = sharing != null && mesh.isRootHostForOrg(sharing.id);
    final isDelegated =
        sharing != null && mesh.issuerAuthorities.containsKey(sharing.id);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Organization trust requires QR or NFC of the org public key — not mesh ads.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _orgCtrl,
          decoration: const InputDecoration(
            labelText: 'Org QR public-key payload',
            hintText: 'zvcomm:org:v1:…',
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _trustOrg,
              icon: const Icon(Icons.domain_add),
              label: const Text('Trust from QR'),
            ),
            if (mesh.nfcAvailable)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _nfcReceive,
                icon: const Icon(Icons.nfc),
                label: const Text('NFC'),
              ),
          ],
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
        if (orgOffers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Nearby org ads (${orgOffers.length}) — not trusted',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(
            'Seen on radio only. Scan org QR or use NFC to trust.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final o in orgOffers)
            ListTile(
              dense: true,
              leading: Icon(_iconForCategory(o.category)),
              title: Text(o.name),
              subtitle: Text(
                '${o.category.label} · ${o.shortCode} · untrusted advertisement',
              ),
            ),
        ],

        // ── Become issuer ────────────────────────────────────────────────
        const SizedBox(height: 24),
        Text(
          'Become an issuer',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'For an org that already has a CA: share your device credential (Share tab) '
          'with an org admin. They grant issuer authority; paste that grant here. '
          'You then issue member certs without holding the root CA private key.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _issuerGrantCtrl,
          decoration: const InputDecoration(
            labelText: 'Issuer authority grant',
            hintText: 'zvcomm:issuer:v1:…  ·  JSON',
            border: OutlineInputBorder(),
          ),
          minLines: 2,
          maxLines: 6,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _becomeIssuer,
          icon: const Icon(Icons.workspace_premium),
          label: const Text('Accept grant & become issuer'),
        ),
        if (_issuerError != null) ...[
          const SizedBox(height: 8),
          Text(
            _issuerError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_issuerOk != null) ...[
          const SizedBox(height: 8),
          Text(
            _issuerOk!,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],

        // ── Share / issue for selected org ───────────────────────────────
        if (sharing != null) ...[
          const SizedBox(height: 24),
          Text(
            'Selected: ${sharing.name}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${sharing.category.label} · ${sharing.id}'
            '${isRoot ? " · root CA host" : ""}'
            '${isDelegated ? " · delegated issuer" : ""}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          CredentialQrCard(
            payload: sharing.toQrPayload(),
            size: 200,
            title: 'Scan to import organization',
          ),
          const SizedBox(height: 8),
          ShortCodeBadge(
            shortCode: sharing.shortCode,
            subtitle: 'Peers import with this code after mesh/NFC publish',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _publishOrg(sharing),
                icon: const Icon(Icons.cell_tower),
                label: const Text('Publish on mesh'),
              ),
              FilledButton.tonalIcon(
                onPressed: (_busy || !mesh.nfcAvailable)
                    ? null
                    : () => _nfcShareOrg(sharing),
                icon: const Icon(Icons.nfc),
                label: const Text('Share via NFC'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  mesh.selectSharingOrganization(null);
                  setState(() {});
                },
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
            ],
          ),
          if (canIssue) ...[
            const SizedBox(height: 16),
            Text(
              isDelegated
                  ? 'Issue member certificate (delegated issuer)'
                  : 'Issue member certificate (root CA)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Paste a peer PublicCredential QR payload to issue an org cert.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memberCredCtrl,
              decoration: const InputDecoration(
                labelText: 'Member credential payload',
                hintText: 'zvcomm:cred:v1:…',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : () => _issueMember(sharing),
              icon: const Icon(Icons.badge),
              label: const Text('Issue member cert'),
            ),
          ],
          if (isRoot) ...[
            const SizedBox(height: 16),
            Text(
              'Grant issuer authority (root only)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Paste the peer\'s credential to authorize them as an issuer '
              'for this org. They import the grant with “Become an issuer”.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _issuerSubjectCtrl,
              decoration: const InputDecoration(
                labelText: 'Peer credential (future issuer)',
                hintText: 'zvcomm:cred:v1:…',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _issueIssuerGrant(sharing),
              icon: const Icon(Icons.how_to_reg),
              label: const Text('Issue issuer grant'),
            ),
          ],
        ],

        // ── Import external member cert ──────────────────────────────────
        const SizedBox(height: 24),
        Text(
          'Import external certificate',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Paste member cert JSON or an org member package (includes issuer chain).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _certCtrl,
          decoration: const InputDecoration(
            labelText: 'Certificate / member package JSON',
            hintText: '{ "kind": "org_member", … }  or  MeshCertificate',
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

        // ── Trusted orgs list ────────────────────────────────────────────
        const SizedBox(height: 24),
        Text(
          'Trusted orgs ($total)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (total == 0)
          const ListTile(
            dense: true,
            title: Text('No organizations yet'),
            subtitle: Text('Import a trust root or become an issuer'),
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
                  title: Text(_orgTitle(o)),
                  subtitle: Text(
                    '${o.shortCode} · ${o.id}\n'
                    '${o.description ?? "Allows: ${o.allowCapabilities.join(", ")}"}',
                  ),
                  isThreeLine: true,
                  onTap: () {
                    mesh.selectSharingOrganization(o);
                    setState(() {});
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Share QR / NFC',
                        icon: const Icon(Icons.qr_code_2),
                        onPressed: () {
                          mesh.selectSharingOrganization(o);
                          setState(() {});
                        },
                      ),
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
                          if (mesh.sharingOrganization?.id == o.id) {
                            mesh.selectSharingOrganization(null);
                          }
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
          ],

        // ── Advanced: generate root CA (rare) ────────────────────────────
        const SizedBox(height: 28),
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Advanced: generate new org CA',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            'Rare — only if you are founding a new organization trust root. '
            'Prefer importing an existing org and becoming an issuer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          children: [
            const SizedBox(height: 8),
            DropdownButtonFormField<OrganizationCategory>(
              key: ValueKey(_selectedCategory),
              initialValue: _selectedCategory,
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
            const SizedBox(height: 8),
            TextField(
              controller: _orgNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Organization name',
                hintText: 'Acme Corp',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _createOrg,
              icon: const Icon(Icons.add_business),
              label: const Text('Generate org CA root'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ],
    );
  }

  String _orgTitle(Organization o) {
    if (mesh.isRootHostForOrg(o.id)) return '${o.name} (root CA)';
    if (mesh.issuerAuthorities.containsKey(o.id)) {
      return '${o.name} (issuer)';
    }
    if (mesh.canIssueForOrg(o.id)) return '${o.name} (issuer)';
    return o.name;
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

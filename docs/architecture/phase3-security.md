# Phase 3 – Security & PKI

## Crypto stack

| Component | Choice | License |
|-----------|--------|---------|
| Algorithms | [`cryptography`](https://pub.dev/packages/cryptography) | Apache-2.0 |
| DH | X25519 | |
| Signatures | Ed25519 | |
| AEAD | ChaCha20-Poly1305 | |
| KDF | HKDF-SHA256 | |

## Device identity

`DeviceIdentity` holds:

- **X25519** key pair (session key agreement)
- **Ed25519** key pair (certificates, enrollment, handshake authentication)
- Stable `id` = first 8 bytes of SHA-256(Ed25519 public) as hex

Factories are async: `DeviceIdentity.generate()`, `fromSeed()`, `fromSeedBytes()`.

## Handshake (ZVComm Handshake v1)

Noise-inspired XX-style (not byte-compatible with Noise Protocol Framework):

1. **Init** → `e_i, s_i_x, s_i_ed, id, Ed25519(sig)`
2. **Resp** → `e_r, s_r_x, s_r_ed, id, Ed25519(sig), AEAD(confirm)`
3. Transcript secrets: `ee || es || se` → HKDF → `(k1, k2)`
4. App data: tag `0x10` + 12-byte nonce + ciphertext + 16-byte MAC

`SecureSession` / `SessionManager` / `SecureMesh` provide E2E encrypt over the mesh.

## PKI

- `MeshCertificate` v2: Ed25519-signed TBS JSON (compact, not X.509)
- `LocalCa`: issue, verify, revoke
- `EnrollmentRequest` / `EnrollmentResponse` for NFC/QR/BLE bootstrap
- `SignedRevocationList` for CRL-style gossip (`MessageKind.pki`)
- **Organizations**: trust a CA root (`zvcomm:org:v1:…`) to accept **external**
  devices that hold org-issued certificates — without pairwise credential exchange

### Organization trust

| Concept | Role |
|---------|------|
| `Organization` | Trusted CA root (public keys + name) |
| `TrustStore` | Orgs + direct peers + org-issued external certs |
| Direct trust | QR / NFC / short-code `PublicCredential` |
| External trust | `MeshCertificate` where `issuerId` is a trusted org |

```bash
# Export org root from a CA identity
dart run apps/cli/bin/cli.dart org --export-ca ca.json --name "Acme Corp"

# Validate org payload + external cert
dart run apps/cli/bin/cli.dart org --trust 'zvcomm:org:v1:…' --verify-cert cert.json
```

## Identity storage

| Store | Use |
|-------|-----|
| `MemoryIdentityStore` | Tests |
| `FileIdentityStore` | CLI / desktop (protect file perms) |

Mobile: wire `flutter_secure_storage` (MIT) behind `IdentityStore` in a later packaging step.

## CLI

```bash
dart run apps/cli/bin/cli.dart identity --seed alice --name Alice
dart run apps/cli/bin/cli.dart ca-init --out ca.json
dart run apps/cli/bin/cli.dart ca-issue --ca ca.json --subject-seed phone --name Phone
dart run apps/cli/bin/cli.dart enroll --seed phone --ca ca.json --out-cert cert.json
dart run apps/cli/bin/cli.dart noise-demo
```

## Threat notes

- Intermediate mesh hops can still observe metadata (ids, sizes, topology).
- File identity store is not HSM-backed; use OS keystores on mobile.
- Handshake is first-party; formal Noise compatibility may be added later if required.

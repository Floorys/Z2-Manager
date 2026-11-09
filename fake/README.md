# Fake payloads

These files are desynchronization payloads, not live requests or certificates.

## TLS ClientHello

The labeled `tls_clienthello_*.bin` files have SNI matching their filenames:

| Alias | SNI |
|---|---|
| `tls_google` | `www.google.com` |
| `tls_vk` | `vk.com` |
| `tls_sber` | `sberbank.ru` |
| `tls_gos` | `gosuslugi.ru` |
| additional bundled payloads | `www.onetrust.com`, `max.ru` |

The Google, VK, Sberbank and Gosuslugi files are **SNI-adjusted versions of the
previously bundled ClientHello captures**, not independently captured handshakes
from those services. Their TLS record, handshake, extension and SNI lengths were
updated together. Previously the Google file contained `www.onetrust.com`, and
the VK/Sberbank/Gosuslugi files were identical copies with `max.ru` SNI.

`tests/check-blobs.cjs` checks the lengths, SNI labels and distinct hashes.
Its optional `--repair` mode can reapply the documented SNI corrections offline.

## QUIC

`quic_initial_generic.bin` is the unchanged, common QUIC Initial previously
shipped under four names: Google, VK, 4pda and dbankcloud. Those four files were
byte-for-byte identical. Strategies now use **one alias, `quic_generic`**, without
pretending there are four service-specific captures. The checker validates its
long header and minimum size; it does not authenticate or decrypt the capture.

The additional legacy `4pda.bin`, `max.bin` and `t2.bin` payloads are retained for
compatibility, but the current catalog and generator do not reference them.
Existing installed copies of old QUIC filenames are not automatically deleted:
they may still be referenced by a user's own configuration.

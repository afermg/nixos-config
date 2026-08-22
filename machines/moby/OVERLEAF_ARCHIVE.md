# Archived Moby Overleaf deployment

Moby no longer hosts the active Overleaf service. The module
[`overleaf.nix`](overleaf.nix) and its pinned
[`overleaf-git-bridge.nix`](overleaf-git-bridge.nix) are retained for recovery
reference, but `default.nix` intentionally does not import them and this flake
no longer declares the `overleaf-nix` input.

## Current setup

The maintained deployment runs Overleaf and its state on **Oppy**, with the
public Cloudflare connector on **Karkinos**. The exact deployed configuration is
preserved in Neusis commit
[`66a7cfa10fa0a60334a7f0b3a6bc5fbc4095117d`](https://github.com/afermg/neusis/tree/66a7cfa10fa0a60334a7f0b3a6bc5fbc4095117d):

- [Oppy Overleaf service](https://github.com/afermg/neusis/blob/66a7cfa10fa0a60334a7f0b3a6bc5fbc4095117d/machines/oppy/overleaf.nix)
- [Karkinos Cloudflare ingress](https://github.com/afermg/neusis/blob/66a7cfa10fa0a60334a7f0b3a6bc5fbc4095117d/machines/karkinos/overleaf-ingress.nix)
- [Migration and recovery runbook](https://github.com/afermg/neusis/blob/66a7cfa10fa0a60334a7f0b3a6bc5fbc4095117d/machines/oppy/OVERLEAF_MIGRATION.md)
- [Restore helper](https://github.com/afermg/neusis/blob/66a7cfa10fa0a60334a7f0b3a6bc5fbc4095117d/machines/oppy/migration/restore-overleaf-on-oppy.sh)

The public service remains <https://overleaf.quasimorphic.com>.

## Frozen state archive

The stopped-state source archive and its sidecars are retained on both Moby and
Oppy:

```text
/home/amunoz/overleaf-moby-20260822T160651Z.tar.gz
/home/amunoz/overleaf-moby-20260822T160651Z.tar.gz.sha256
/home/amunoz/overleaf-moby-20260822T160651Z.tar.gz.manifest
```

Archive SHA-256:

```text
f3db727a2ea2d8ef9b2d7f94a55863d0eb97004edfa9ac3a92f1953fa874344b
```

The manifest records 7 users, 7 password hashes, 10 projects, 102 documents,
MongoDB FCV 7.0, and the stopped filesystem-state digest. The encrypted
`cloudflared-overleaf.age` and `netrc-overleaf.age` files remain in this
repository for recovery/client use; neither activates a Moby server by itself.

## Future restoration rule

Do **not** expose Moby's frozen 2026-08-22 state after Oppy has accepted newer
writes. To return service to Moby:

1. Follow the linked Neusis recovery runbook.
2. Quiesce Oppy and make a fresh stopped-state archive of its current MongoDB,
   Redis, Overleaf files, and secrets.
3. Restore that fresh state onto Moby using a runtime compatible with the
   active deployment.
4. Validate users, password-hash digest, projects, documents, compilation, and
   Git Bridge before moving the Karkinos/Cloudflare connector.

The archived Moby module is historical reference only. Prefer porting the
current Oppy/Karkinos configuration from the immutable Neusis commit rather
than re-enabling the old module verbatim.

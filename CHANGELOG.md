# Changelog

## 0.2.0 — 2026-10-08

- Add the exact Windows x64 1.5.2 build; the local tester reported the offline fixes working.
- Add guarded automatic adaptation for unlisted builds whose relevant code remains structurally identical.
- Verify five complete normalized function fingerprints, unique matches, internal branches, constructor/initializer links, stock identity slots and PE layout before building a patch.
- Keep per-original-hash backups, preserve matching legacy backups, and save locally generated recovery manifests for adaptive installs.
- Add read-only `-Analyze` mode, migration tests and adaptive refusal/rollback tests.
- Independently reproduce the previously validated 1.5.1 and 1.5.2 patched hashes with the adaptive builder.

Unlisted builds remain experimental until tested in game. Structural matching cannot guarantee compatibility with every release.

## 0.1.0 — 2026-10-03

Preview release for the exact tested Windows x64 build of Last Epoch 1.5.1.

- Complete offline identity initialization for portals, seasonal reward participation and local cosmetic selection persistence.
- Handle an unloaded supporter-pack release cache when opening skill appearances.
- Preserve stock cosmetic ownership checks and each player's inventory cache.
- Add a standalone PowerShell installer, verified original backup, hash check and rollback.
- Reconstruct the exception table from the user's original DLL instead of redistributing game binaries.
- Add English/Russian player guides, troubleshooting and developer-support links.

Further validation is needed for seasonal combat end to end and other hardware/account configurations. See `docs/compatibility.md`.

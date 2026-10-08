# How the patch works

The offline login path in the tested build can construct an incomplete `UserIdentity`. The affected portal path attempts to parse an empty `MasterAccountID`; seasonal participation and local cosmetic persistence also depend on a usable identity.

## Complete offline identity

The patch redirects the constructor call in `PlayFabUserService.BypassLogin` through a **175-byte x64 wrapper** in a new executable `.lefix` section. The call is at RVA `0x1caacac` in the known 1.5.1 build and `0x1caf19c` in 1.5.2. The original constructor retains its calling convention.

The wrapper preserves a nonempty Master ID. For the incomplete offline profile, it uses the stock offline numeric identity with canonical hexadecimal spelling (`0337173` → `337173`) and fills missing name, title and platform fields from the game's own stock offline values. Canonical spelling is needed because portal synchronization formats the numeric owner ID as hexadecimal. A nonempty title field also matters to the local identity validation used to save cosmetic selections.

The new function has its own unwind record. The installer copies the original exception table from the user's original DLL, adds the wrapper's runtime-function entry, and updates the PE section header, image/code sizes, exception-directory pointers and checksum. Known builds must match their published patched SHA-256; adaptive builds are reconstructed independently from a generated manifest and checked against their calculated hash. PE parsing follows the [Microsoft PE specification](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format).

Only the offline constructor call is redirected. The signed-in login path is not redirected by this patch. This design scope does not replace runtime validation of online behavior.

## Unloaded cosmetic release cache

`MTXStoreController.IsSupporterPackLive` has two null branches that reach an exception path when its live-pack cache is absent offline. They are redirected to its existing empty-cache return path. The branch RVAs are `0x1fdceeb` / `0x1fdcf32` for 1.5.1 and `0x1ff7d9b` / `0x1ff7de2` for 1.5.2.

This guard handles availability metadata. **Inventory membership and ownership checks are unchanged.** There are no cosmetic-ID additions, purchase overrides, Steam DLC emulation, point changes, or local inventory writes in the installer.

The game itself must already have cached the user's purchased/unlocked inventory. Files being present on disk do not establish entitlement. The patch cannot verify an uncached purchase without the game's normal account synchronization.

## Published data

[`src/patch-1.5.1.json`](../src/patch-1.5.1.json) and [`src/patch-1.5.2.json`](../src/patch-1.5.2.json) contain hashes, byte offsets, short original-byte checks, our wrapper/unwind bytes, and a runtime-function entry. The several-megabyte original exception table is read from the user's local DLL at installation time. No complete original or modified DLL is redistributed.

[`src/OfflineFix.psm1`](../src/OfflineFix.psm1) performs byte reconstruction and file replacement. It refuses unmatched inputs and damaged backups, rechecks the game process and current file hash before atomic replacement, and does not touch character saves or cosmetic-cache files.

## Guarded automatic adaptation

[`AdaptivePatch.cs`](../src/AdaptivePatch.cs) parses x64 PE sections, exports and runtime-function boundaries without a game process or injected code. [`adaptive-template.json`](../src/adaptive-template.json) stores short anchors, complete normalized function hashes and relocation descriptions for five functions: offline login, identity constructor, cache check, metadata initializer and stock identity creation. Complete game function bodies are not distributed.

Addresses in relative calls, branches and RIP-relative loads are normalized for fingerprint comparison. Internal branch destinations are checked separately, so changing a masked branch displacement is refused. Constructor and initializer links must agree, and repeated stock identity references must resolve to three distinct aligned writable data slots. Exactly one function of each required role must match. Unexpected architecture, alignment, overlapping sections, signed images, occupied headers, changed code and ambiguous matches are refused.

The generator reads the `il2cpp_string_new` export, calculates a fresh section location and all wrapper displacements, and creates a manifest tied to the exact source/output hashes. The PowerShell reconstruction independently checks that manifest before installation. An adaptive install saves its recovery manifest and a per-original-hash backup in `.le-offline-fixes`; retain this folder for rollback. The existing matching legacy backup remains valid for older installations.

This is constrained structural matching, not arbitrary program repair. It cannot prove future metadata semantics or gameplay behavior. An accepted unlisted build is experimental; changes to the relevant machine-code structure require manual analysis and a template update. The adapter reproduced both known patched DLL hashes exactly. Local tests also check changed code, changed branches, broken links, conflicting stock references, duplicate matches, unsupported architecture, occupied headers and installation/rollback of an unlisted-hash copy with only a DOS-stub byte changed.

## Reviewing a new build

Do not update only the expected hash. Revalidate the constructor ABI, native targets, metadata slots, portal owner formatting, identity validation, store-cache control flow, available PE header space, section alignment, unwind information and exception table. Then check the intended game behavior and generate a new independently verified output hash.

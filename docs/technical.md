# How the patch works

The offline login path in the tested build can construct an incomplete `UserIdentity`. The affected portal path attempts to parse an empty `MasterAccountID`; seasonal participation and local cosmetic persistence also depend on a usable identity.

## Complete offline identity

The patch redirects the constructor call at RVA `0x1caacac` in `PlayFabUserService.BypassLogin` through a **175-byte x64 wrapper** in a new executable `.lefix` section. The original constructor is then called with its original calling convention.

The wrapper preserves a nonempty Master ID. For the incomplete offline profile, it uses the stock offline numeric identity with canonical hexadecimal spelling (`0337173` → `337173`) and fills missing name, title and platform fields from the game's own stock offline values. Canonical spelling is needed because portal synchronization formats the numeric owner ID as hexadecimal. A nonempty title field also matters to the local identity validation used to save cosmetic selections.

The new function has its own unwind record. The installer copies the original exception table from the user's original DLL, adds the wrapper's runtime-function entry, and updates the PE section header, image/code sizes, exception-directory pointers and checksum. The full output must match the fixed published SHA-256.

Only the offline constructor call is redirected. The signed-in login path is not redirected by this patch. This design scope does not replace runtime validation of online behavior.

## Unloaded cosmetic release cache

`MTXStoreController.IsSupporterPackLive` has two null branches at RVAs `0x1fdceeb` and `0x1fdcf32` that reach an exception path when its live-pack cache is absent offline. They are redirected to the function's existing empty-cache return path.

This guard handles availability metadata. **Inventory membership and ownership checks are unchanged.** There are no cosmetic-ID additions, purchase overrides, Steam DLC emulation, point changes, or local inventory writes in the installer.

The game itself must already have cached the user's purchased/unlocked inventory. Files being present on disk do not establish entitlement. The patch cannot verify an uncached purchase without the game's normal account synchronization.

## Published data

[`src/patch-1.5.1.json`](../src/patch-1.5.1.json) contains hashes, byte offsets, short original-byte checks, our wrapper/unwind bytes, and a runtime-function entry. The several-megabyte original exception table is read from the user's local DLL at installation time. No complete original or modified DLL is redistributed.

[`src/OfflineFix.psm1`](../src/OfflineFix.psm1) performs byte reconstruction and file replacement. It refuses unknown inputs and damaged existing backups, rechecks the game process and current file hash before atomic replacement, and does not touch character saves or cosmetic-cache files.

## Reviewing a new build

Do not update only the expected hash. Revalidate the constructor ABI, native targets, metadata slots, portal owner formatting, identity validation, store-cache control flow, available PE header space, section alignment, unwind information and exception table. Then check the intended game behavior and generate a new independently verified output hash.

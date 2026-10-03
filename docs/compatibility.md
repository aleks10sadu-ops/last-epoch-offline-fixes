# Compatibility and validation

[English guide](../README.md) · [Русская инструкция](../README.ru.md)

This is a preview workaround for a specific **Windows x64 Last Epoch 1.5.1** build. It is not a universal patch for every DLL bearing the same version number.

| Property | Supported value |
| :--- | :--- |
| Version | 1.5.1 |
| Build identifier | 25672295 |
| Engine | Unity 6000.4.8f1, IL2CPP |
| Original DLL size | 97,185,280 bytes |
| Patched DLL size | 100,621,824 bytes |
| Runtime for installer | Windows PowerShell 5.1 or PowerShell 7 on Windows |
| Required extra dependencies | None |
| Last local validation | 2026-10-03 |

Original SHA-256:

```text
502E32F1F31BC1979AC6C387FAEF1266A62AD29F5B573E6D9B51CB577A72F5F8
```

Patched SHA-256:

```text
3A3723A4788160D10FC1A779A6CE0734C33064940A13463952DF096EA724695E
```

## Observed game behavior

| Scenario | Status |
| :--- | :--- |
| Create town portal with T and UI, travel to town and return | Passed on the initial identity fix; the current wrapper retains that change. |
| Cosmetic equipment selection survives normal game restart | Passed with a locally cached armor appearance. |
| Skill appearance selection and persistence | Passed with a locally cached Flame Ward appearance. |
| Skill appearance menu with an unloaded supporter-pack cache | Passed after the null-cache guard. |
| Seasonal participant registration, five reward credits, claim and offer refresh | Passed; one reward claimed, four credits remained, no rejected claim. |
| Complete seasonal combat, kill-earned credit and late-game rewards | Further validation required. |
| Ownership checks with a freshly synchronized, restricted purchased inventory | Static checks are unchanged; a second-account runtime validation is still needed. |
| Online multiplayer | Outside the intended scope; not tested. |
| Every cosmetic, class, area, character type and hardware setup | Not exhaustively tested. |

The locally verified inventory was a diagnostic inventory. It is not distributed or created by this release. The public installer leaves each player's existing cache unchanged.

## Installer behavior

The public installer reconstructs exactly the previously tested patched DLL. It verifies input SHA-256, original bytes at each patch site, output SHA-256, and the persistent original backup. Installation and rollback are checked on a separate copy of the supported DLL. Tests also cover corrupted manifests, unknown input, backup preservation, repeated installation and rollback, and refusal while the game is running.

CI uses a synthetic binary fixture to test the patching and file transaction logic. The real game DLL is intentionally absent from CI and this repository.

## After a game update

Restore before updating. If a launcher replaces the DLL, the installer must recheck its hash. A new hash requires review and a new patch definition, even if the displayed version is still 1.5.1. Never reuse these offsets on another build.

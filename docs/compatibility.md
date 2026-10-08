# Compatibility and validation

[English guide](../README.md) · [Русская инструкция](../README.ru.md)

The preview installer supports two known Windows x64 builds and guarded adaptation to unlisted builds with matching relevant code. Acceptance of an unlisted build is a structural result, not a guarantee of gameplay compatibility.

| Property | 1.5.1 | 1.5.2 |
| :--- | :--- | :--- |
| Build identifier | Steam build 25672295 | Local build hash 157a8290bdc30455987bf5ceb9ed4081f1c703b2; Steam build ID not established |
| Engine | Unity 6000.4.8f1, IL2CPP | Unity 6000.4.8f1, IL2CPP |
| Original DLL size | 97,185,280 bytes | 97,220,096 bytes |
| Patched DLL size | 100,621,824 bytes | 100,657,664 bytes |
| Last local validation | 2026-10-03 | 2026-10-08 |

Original SHA-256:

```text
1.5.1: 502E32F1F31BC1979AC6C387FAEF1266A62AD29F5B573E6D9B51CB577A72F5F8
1.5.2: 5DD7563CB74CF833327BFF8C074FEBE462D2FB4F2D99CC3275E7B6EB1305EAB3
```

Patched SHA-256:

```text
1.5.1: 3A3723A4788160D10FC1A779A6CE0734C33064940A13463952DF096EA724695E
1.5.2: 6E3751C24130371BFF021A6F030C2ECD8236A767A3A7872908AAB6EDD18CCDE2
```

The installer runs in Windows PowerShell 5.1 or PowerShell 7. No Python, mod loader or downloaded runtime is required; the adaptive analyzer is compiled locally with the built-in .NET tools.

## Observed game behavior

| Scenario | Evidence |
| :--- | :--- |
| Town portal through T/UI, travel and return | Directly checked on the initial 1.5.1 identity fix. |
| Armor and skill appearance selection survives restart | Directly checked on 1.5.1 with locally cached appearances. |
| Skill appearance menu with an unloaded supporter-pack cache | Checked after the 1.5.1 null-cache guard. |
| Seasonal participant registration, reward credit, claim and offer refresh | Directly checked on 1.5.1; one reward claimed, four credits remained, no rejected claim. |
| Offline fixes on 1.5.2 | The local tester reported the fixes working after receiving a checklist covering portals, a fresh seasonal encounter, cosmetics and normal exit. Separate detailed results for every checklist item were not recorded. |
| Complete seasonal combat, kill-earned credit and late-game rewards | Broader, reproducible validation is still needed; the tester report does not establish every encounter variant. |
| Ownership checks with a freshly synchronized, restricted purchased inventory | Stock code is unchanged; a second-account runtime validation is still needed. |
| Online multiplayer | Outside the intended scope; not tested. |
| Every cosmetic, class, area, character type and hardware setup | Not exhaustively tested. |

The initial diagnostic inventory is not distributed or created by this release. The public installer leaves each player's existing cache unchanged. The 1.5.2 tester session used the persistent DLL patch without a diagnostic injection or event spawn.

## Installer and adapter checks

Known-build reconstruction, installation, backup integrity, repeat installation, rollback, damaged manifests and running-game refusal pass on private DLL copies in PowerShell 5.1 and 7. Version-selection tests cover preserving a legacy 1.5.1 backup while installing and restoring 1.5.2.

The adaptive builder independently reproduces the exact published patched hashes for both known builds. Tests refuse changed function code, altered masked branches, broken constructor links, conflicting identity references, duplicate function matches, other architecture and occupied PE headers. A controlled unlisted-hash fixture changes only an unrelated DOS-stub byte; adaptive installation, saved recovery manifest, repeat installation and exact rollback pass. This fixture does not represent a third gameplay-tested version.

CI uses synthetic data and checks version selection, C# compilation and malformed-image refusal. Game binaries and real-DLL fixtures are intentionally absent from CI and this repository.

## After a game update

Restore the original before updating. Run the installer again afterward. Known hashes use a fixed manifest; unlisted original DLLs must pass the complete adaptive checks. Changed or ambiguous structures are refused and require a reviewed template update. Keep `.le-offline-fixes` for rollback. Accepted unlisted builds still need a gameplay test; there is no force option and no all-version compatibility claim.

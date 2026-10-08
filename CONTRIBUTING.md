# Contributing

Bug reports, translations, exact-build compatibility work and reproducible testing are welcome.

## Reports

Use the issue form. Include the game's build/version, the output of `Install.ps1 -Check`, offline launch method, whether the problem occurs in a new area, and exact reproduction steps. Cosmetic reports should distinguish an absent inventory item from an item that is present but fails to equip or persist.

Do not upload game binaries, account credentials, complete logs, cosmetic inventory caches or character saves. A short relevant log excerpt is enough after removing usernames, paths, account identifiers and tokens.

## Scope

This project fixes offline functionality while retaining the game's ownership checks. Changes that unlock unowned cosmetics, add inventory IDs, emulate DLC ownership, alter account entitlements or grant currency are outside the project scope.

## Tests

Run the synthetic-fixture suite in Windows PowerShell 5.1 and PowerShell 7:

```powershell
.\tests\Test-OfflineFix.ps1
.\tests\Test-VersionSelection.ps1
.\tests\Test-AdaptivePatch.ps1
```

For a real supported DLL that you own, add a private local path:

```powershell
.\tests\Test-OfflineFix.ps1 -OriginalDll "D:\Private\GameAssembly.original.dll"
.\tests\Test-OfflineFix.ps1 -OriginalDll "D:\Private\1.5.2\GameAssembly.original.dll" -GameVersion 1.5.2
.\tests\Test-VersionSelection.ps1 -Original151 "D:\Private\1.5.1\GameAssembly.dll" -Original152 "D:\Private\1.5.2\GameAssembly.dll"
.\tests\Test-AdaptivePatch.ps1 -Original151 "D:\Private\1.5.1\GameAssembly.dll" -Original152 "D:\Private\1.5.2\GameAssembly.dll"
```

This creates a temporary copy for installation and rollback checks. It does not patch your real installation. Never commit the original DLL or generated output.

## New builds

See the technical guide. First run `Install.ps1 -Analyze` on an original DLL. Matching structures may adapt automatically; changed structures require a reviewed template update. To add a known build, submit a separate manifest and explain address checks and observed game behavior. Keep claims precise: structural acceptance is not proof of gameplay compatibility, and a passing reward transaction is not proof of a complete seasonal combat sequence.

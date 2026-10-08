<p align="center"><img src="assets/banner.svg?v=adaptive-0.2.0" alt="Last Epoch Offline Fixes — portals, seasonal encounters and cosmetics" width="100%"></p>

<p align="center">
 <img src="https://img.shields.io/badge/tested-1.5.1_%7C_1.5.2-c99161?style=flat-square" alt="Tested builds: 1.5.1 and 1.5.2">
 <img src="https://img.shields.io/badge/platform-Windows_x64-73c9c3?style=flat-square" alt="Windows x64">
 <img src="https://img.shields.io/badge/release-preview-e3b362?style=flat-square" alt="Preview release">
 <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-9daec4?style=flat-square" alt="MIT license"></a>
</p>

<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a></p>
<p align="center"><a href="#install-in-four-steps">Install</a> · <a href="#what-it-fixes">Fixes</a> · <a href="#cosmetics">Cosmetics</a> · <a href="#undo-the-fix">Rollback</a> · <a href="docs/technical.md">How it works</a></p>

# Keep your offline journey moving

A small community patch for **Last Epoch 1.5.1 and 1.5.2** that fixes offline identity initialization and an empty cosmetic-store cache. It addresses broken town portals, the offline seasonal encounter reward problem, and cosmetics that cannot be selected or do not survive a restart.

**Preview release with automatic adaptation:** known builds use verified patches. Other Windows x64 builds are analyzed locally; the installer adapts only when complete function fingerprints, control flow and required references match. Changes or ambiguous matches are refused. This does not guarantee support for every version. See [compatibility and test status](docs/compatibility.md).

## What it fixes

| Problem | What changes |
| :--- | :--- |
| **Town portal does nothing** when pressing **T** or clicking the UI | Initializes the offline identity used to create and own portals. |
| **Bloodrage Crystals show 5/5**, but the reward window shows **0** | Repairs the offline identity used for seasonal participation and reward credit. |
| **Cosmetics fail to equip or reset**, including skill effects | Supplies the complete offline identity needed to save selections and handles an unloaded supporter-pack cache. |

The installer changes **GameAssembly.dll** and keeps a verified original backup. Character saves are not edited. The patch applies to the offline login path; it is intended for **Play Offline**.

## Install in four steps

1. **[Download the ZIP](https://github.com/aleks10sadu-ops/last-epoch-offline-fixes/archive/refs/heads/main.zip)** and extract the entire folder.
2. **Close Last Epoch.** Keep a separate backup of your character saves before trying a preview mod.
3. Double-click **`Install.cmd`** and select **`Last Epoch.exe`** in your game folder. Wait for the green “Installed” message.
4. Start Last Epoch normally and choose **Play Offline**.

**No Python, mod loader, account login, or administrator access is required by the core installer.** Your game folder must be writable. Originals are backed up separately as `GAME_FOLDER\.le-offline-fixes\GameAssembly.<ORIGINAL_SHA256>.original.dll`. Matching legacy backups remain usable. Keep the entire `.le-offline-fixes` folder for rollback.

<details>
<summary><b>Prefer PowerShell? Check compatibility first.</b></summary>

Open PowerShell in the extracted folder. Replace the example path with your installation:

```powershell
.\Install.ps1 -GameDirectory "D:\Games\Last Epoch" -Check
.\Install.ps1 -GameDirectory "D:\Games\Last Epoch"
```

`-Check` only reads the DLL and reports its hash and status. `adaptive-compatible` means the structural checks passed for an unlisted build; its gameplay still needs testing. `-Analyze` forces read-only function analysis on an original DLL. An unsupported file is refused before installation. `Install.cmd` uses the Windows PowerShell execution-policy option for its own process; it does not change your saved system policy.

</details>

### Known builds and automatic adaptation

Known original DLLs, Windows x64:

```text
1.5.1: 502E32F1F31BC1979AC6C387FAEF1266A62AD29F5B573E6D9B51CB577A72F5F8
1.5.2: 5DD7563CB74CF833327BFF8C074FEBE462D2FB4F2D99CC3275E7B6EB1305EAB3
```

The version number alone is insufficient. For an unlisted DLL, the installer finds the functions, verifies their structure and connections, calculates the new patch addresses, and saves a local recovery manifest. If the game changes those functions or its PE layout, a reviewed template update is required. There is no force option. An accepted unlisted build is experimental until tested in game.

## Cosmetics

After installing, open **Appearance** (`Shift+K`, or the Appearance tab in your inventory). Choose an equipment slot or the cosmetic slot under a class skill, select the appearance, and restart once to check that it persists.

**Your cosmetics stay yours.** The patch keeps the game's ownership checks and existing inventory filtering. It does not add cosmetic IDs, unlock DLC or supporter packs, replace your inventory cache, or change Epoch Points. It repairs equipping and saving the cosmetics already available to your account in the game's local cache.

True Offline needs that cache. If purchased DLC or supporter-pack cosmetics are missing, use your owning account to open Appearance while connected, let the game cache the inventory, then return to Play Offline. See the [official cosmetics guide](https://support.lastepoch.com/hc/en-us/articles/48418105189659-How-do-I-equip-cosmetics-I-ve-purchased-unlocked-in-Last-Epoch). Merely having an asset file installed does not establish ownership. The patch cannot recover purchases that were never cached.

## Undo the fix

Close the game, double-click **`Restore.cmd`**, and select the same executable. The verified original DLL is restored; your current character progress and cosmetic cache remain.

```powershell
.\Restore.ps1 -GameDirectory "D:\Games\Last Epoch"
```

Before installing a game update, restore the original. If the backup is missing, use your game launcher's file-verification feature. After updating, run the installer again so it checks the new DLL and selects or builds the matching patch.

## Troubleshooting

| Message or symptom | Next step |
| :--- | :--- |
| **Unsupported DLL** | The code or layout did not match. Restore other DLL mods, check an original installation, or report the analysis error for a reviewed update. |
| **adaptive-compatible / Unlisted build** | Structural checks passed. Test portals, rewards, cosmetics and normal exit; report your DLL hash and results. |
| **Close Last Epoch** | Exit the game completely, then rerun the installer. |
| **Access denied** | Check write permissions on the game directory and extraction folder. |
| **Already installed** | The patched hash matches; no files were changed. |
| **Purchased cosmetics are missing** | Sign in to the owning account and prepare the official offline inventory cache. The patch cannot add uncached purchases. |
| **Seasonal rewards remain stuck** | Enter a fresh combat area and test a new encounter. Existing generated offers are not rewritten by the installer. Report the result with the build and DLL hash. |

## Help improve it

If the fix helps your offline run, consider **starring the repository**. Reports from other players help establish which scenarios work reliably.

Use the [bug report form](https://github.com/aleks10sadu-ops/last-epoch-offline-fixes/issues/new?template=bug_report.yml) and include your build, DLL hash, offline launch method, and reproduction steps. Share only a relevant, sanitized log excerpt; keep character saves and account details private. See [contributing](CONTRIBUTING.md).

## Support the developers

Enjoying Last Epoch? **[Buy the game on Steam](https://store.steampowered.com/app/899770/Last_Epoch/)** and consider its officially sold DLC or supporter packs. Support Eleventh Hour Games so they can keep building Eterra. This project makes owned cosmetics usable offline and preserves the game's ownership checks.

## Background and credits

Created by **[aleks10sadu-ops](https://github.com/aleks10sadu-ops)** with Codex-assisted investigation, implementation, and documentation. This is an unofficial community project, unaffiliated with Eleventh Hour Games.

The same portal and seasonal-reward symptoms were reported on the [official Last Epoch forum](https://forum.lastepoch.com/t/gamebreaking-bugs-in-true-offline-mode-s5/81901). Version context: [1.5.1 announcement](https://forum.lastepoch.com/t/last-epoch-patch-1-5-1-notes/81911).

This repository contains patch instructions and our wrapper code. The installer reconstructs the necessary exception-table data from your own DLL; complete game binaries, assets, personal caches, and saves are not distributed. The MIT license covers this project's original code and documentation.

# Troubleshooting

| Symptom | First action |
| --- | --- |
| Source capture refuses an active patch | Run the transactional uninstaller, then recapture from the restored Steam original. |
| Build leaves the old patch unchanged | Inspect the failed staging contract; do not manually mix staging output into `patch/`. |
| Installer detects a prior or interrupted transaction | Let the uninstaller recover it; keep the manifest and `_ChinesePatchBackup` until verification succeeds. |
| Uninstaller restores files but then errors while showing the save-name notice | An empty `RenamedSaves` collection is valid: the helper must accept it and return without a dialog. Cover this path in the uninstall script test. |
| Patch-only file was changed after installation | Do not force deletion. Preserve the manifest/backup and decide whether the file is player or MOD content. |
| Locked dependency restore cannot reach NuGet | Resolve the locked restore first; the unified gate now stops before creating a game transaction, so do not manually restore game files. |
| Smoke fails | The verification gate restores pre-gate files automatically. Read the matching crash-risk topic before repair. |
| Release push lease fails | Fetch and inspect the newer release branch, rerun the gate from synchronized `main`, then publish again. |

For startup/content, runtime/assets, or managed-rewrite failures, use the
matching topic under `crash-risks/`.

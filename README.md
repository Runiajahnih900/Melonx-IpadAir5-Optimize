# Melonx iPad Air 5 Optimize

Repository ini berisi patch optimasi untuk basis `melonx/emu` (tag `2.3.1`) dengan fokus:

- Optimasi penggunaan RAM untuk iPad Air 5 (M1)
- Live log relay dari iPad ke PC via HTTP untuk debugging cepat

## Isi Patch

- `src/ARMeilleure/Translation/Cache/JitCache.cs`
- `src/Ryujinx.Graphics.Gpu/Shader/DiskCache/ParallelDiskCacheLoader.cs`
- `src/Ryujinx.UI.Common/Configuration/ConfigurationState.cs`
- `src/MeloNX/MeloNX/App/UI/MeloNXApp.swift`
- `src/MeloNX/MeloNX/App/Core/Ryujinx/Logs/LogCapture.swift`
- `src/MeloNX/MeloNX/App/UI/Main/Home/SettingsView/SettingsView.swift`
- `tools/live-log-relay/*`

## Live Log

Cara pakai live log ada di:

- `tools/live-log-relay/README.md`

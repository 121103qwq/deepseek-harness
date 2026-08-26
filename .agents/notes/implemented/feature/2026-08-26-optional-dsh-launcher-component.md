# Agent Note: Optional DSH Launcher installer component

Status: implemented

English | [中文](2026-08-26-optional-dsh-launcher-component.zh.md)

## Problem

DeepSeek Desktop users need a direct path to the separately developed DSH Launcher without running another installer or downloading dependencies on first launch. Combining both applications into one process would couple their data and release lifecycles, while copying an executable directly onto the Desktop would not provide a normal installed layout or reliable uninstall behavior.

## Decision

The Windows offline builder requires a separately built, versioned DSH Launcher Windows x64 single-file executable. It validates the PE architecture, file version, and size before copying the executable into a dedicated `launcher` payload directory, and records its version, byte count, and digest in `desktop-install-manifest.json`.

NSIS exposes Launcher as a selected-by-default component that users can clear on the component page. When selected, the installer places `DSH Launcher.exe` under the DeepSeek Desktop program directory and creates Start menu and Desktop shortcuts that target that copy. The Launcher runs as an independent application and keeps its own data, application identity, update behavior, and `DSH_HOME` ownership rules. Uninstall removes the bundled executable and its shortcuts without deleting Launcher or Harness user data.

The optional component extends the [Windows offline DeepSeek Desktop installer](2026-08-26-windows-offline-desktop-installer.md). It is the separately developed DSH Launcher application rather than the Harness-owned manager host described by [Windows DSh manager and launcher](2026-08-14-dsh-manager-launcher.md).

## Alternatives considered

**Download Launcher during installation or first launch.** Rejected because the offline installer promises one deterministic installation step and must remain usable without an additional network request.

**Copy the executable itself onto the Desktop.** Rejected because the Desktop is a shortcut surface, not an application directory; a program-directory copy gives upgrades and uninstall one owned location.

**Merge Launcher into the DeepSeek Desktop process.** Rejected because the applications have separate data and release lifecycles, and Launcher must remain usable when the Desktop host is not running.

**Commit the Launcher binary to this repository.** Rejected because generated binaries do not belong in source history. Release assembly receives the verified executable explicitly and embeds it only in the generated installer asset.

## Consequences

The offline asset carries the compressed Launcher bytes even when a user clears the component, so every Desktop release must stay within the existing 330 MiB limit and verify both selected and cleared installation paths. A Desktop release also needs an explicit Launcher build input; the installer never substitutes an unvalidated download. Launcher remains independently developed and can continue publishing its own release assets.

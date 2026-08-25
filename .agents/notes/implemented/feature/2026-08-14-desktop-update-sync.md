# Agent Note: Desktop update synchronization

Status: implemented

English | [中文](2026-08-14-desktop-update-sync.zh.md)

## Problem

The Windows community package needs one predictable place to discover updates from both the official Harness project and this community distribution. A background check must not turn into an unannounced executable download or installation, especially because the package is explicitly independent from DeepSeek.

## Decision

The installer bundles `deepseek-desktop-update-sync` and enables it by default. The plugin checks the latest GitHub Release metadata for `deepseek-ai/deepseek-harness` and `121103qwq/deepseek-harness` after startup and every six hours, then exposes read-only status at `/__deepseek_desktop/update-sync`. The installer lets the user disable background checks or opt into background download staging. Opt-in staging accepts only the offline DeepSeek Desktop setup asset, limits it to 330 MiB, requires and verifies the GitHub-provided SHA-256 digest, and writes it under the current user's update directory; it never launches or installs the staged executable.

The plugin uses release metadata rather than mutating the source checkout or silently changing the active profile. A missing Release is reported as `not_published`, so the community repository can be checked before it publishes its first desktop asset.

## Alternatives considered

**Silent automatic installation** — rejected because it would execute an installer outside the user's explicit action, can require elevation or restart, and would weaken the independent-community attribution boundary.

**A single repository check** — rejected because official Harness changes and community desktop setup changes have different release owners and can advance independently.

**A client-only settings card** — deferred because the Windows payload already has a first-run installer choice that can persist the two safety controls without changing the shared Web UI settings package. The local status endpoint leaves room for a later in-app settings surface.

## Consequences

The default installation performs small GitHub metadata requests in the background but does not download a setup executable. Users who enable background downloads get a staged file and a status record, but still confirm when to run it. The endpoint keeps only in-memory status and does not expose profile paths, credentials, or release response bodies.

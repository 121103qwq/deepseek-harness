# Agent Note: Windows DSh manager and launcher

Status: implemented

English | [中文](2026-08-14-dsh-manager-launcher.zh.md)

## Problem

Windows users need a single place to switch between DSh installations and source workspaces while keeping experimental extensions and runtime settings from leaking between instances. The manager must also preserve the useful distinction between shared conversations and isolated runtime resources.

## Decision

The repository ships a private `@deepseek-ai/dsh-manager` workspace and a Windows WebView2 host. The user-facing `DSH luncher.exe` embeds the Manager server, UI assets, and Node runtime, extracts them into `%LOCALAPPDATA%\DeepSeek Harness Manager` at startup, stores its registry there, gives each registered instance its own manager-owned DSh Home, allocates a loopback port, launches the DSh Web profile, and opens the returned URL in an independent chat window.

The UI uses a PCL2-inspired folder-and-card layout for startup, instance management, extension discovery, Skills, conversations, models, Agent presets, and diagnostics. Official npm packages use the `@deepseek-ai/dsh-*` namespace. Community plugin discovery uses the GitHub `dsh-plugin` topic, and user catalogs are accepted only through explicit HTTP(S) URLs. Unverified community entries display a warning before installation.

The instance lifecycle records detection, starting, running, HTTP health, stopping, restarting, logs, port, PID, last launch time, favorite state, icon, and description. A sync group rejects a second launch while another member is running. Source and installed instances remain distinct in the UI, while the store uses verified-first name sorting for its first release.

Instance isolation is the default. Manager registration data stays under the Manager data root and never enters a DSh configuration file or source checkout. A sync group changes only the session-persistence root; it does not share the instance Home, plugins, Skills, settings, permissions, logs, or runtime process. Local Skills are copied into the selected instance and can be removed from the manager UI; project Skills remain read-only. An explicit plugin operation invokes DSh with that instance's isolated `DSH_HOME`.

## Alternatives considered

**Reuse DeepSeek Desktop as the manager window.** Rejected because instance selection and chat sessions need independent lifecycles; the manager must stay open while a selected DSh instance is stopped or replaced.

**Share one global DSh Home.** Rejected because plugin, Skill, model, Agent, and permission changes in one instance would affect every other instance.

**Treat every GitHub repository as installable.** Rejected because the marketplace needs an explicit `dsh-plugin` marker for discovery, and unverified community code must remain visibly unverified.

**Synchronize all instance data.** Rejected because only conversations are portable between instances; synchronizing executable extensions or settings would defeat isolation.

## Consequences

The manager can launch both source and installed instances without requiring a global PATH change. The Windows distribution exposes one manager executable; its first launch expands private runtime files under the user data directory. Source launches use the project TypeScript entry with that selected Node runtime, so a usable source checkout still needs its own dependencies and built frontend artifacts. The manager's loopback service and WebView2 host are separate from the DSh chat process, which makes their logs and failures diagnosable independently.

The Models, Agent, workflow, MCP, tools, permissions, backup, and update navigation establishes the manager's resource vocabulary; runtime-specific editors can be added without changing the registry or isolation rule. The manager is built and distributed separately; the DeepSeek Desktop installer does not embed it. Both applications use the same normalized `DSH_HOME` startup-lock convention so they cannot mutate one Harness home concurrently. The desktop packaging decision is recorded in [Windows offline DeepSeek Desktop installer](2026-08-26-windows-offline-desktop-installer.md).

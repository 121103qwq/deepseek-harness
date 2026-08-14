# Agent Note: Windows network plugin installation

Status: implemented

English | [中文](2026-08-14-windows-network-plugin-install.zh.md)

## Problem

The Windows desktop setup needs useful community plugins without making the offline executable grow with every optional package. Optional downloads must be reproducible, must not run package lifecycle scripts, and must not prevent the desktop from diagnosing a failed network install.

## Decision

The offline payload always includes `deepseek-desktop-plugin-helper` and the existing desktop safety plugins. The online payload keeps the same local payload, then injects four selected network dependencies during installation: `dsh-session-export` and `dsh-mic-input` use pinned GitHub commit archives, while `dsh-client-auto-continue` and `dsh-web-attention-badge` use exact npm versions. The installer prefers `registry.npmmirror.com` and retries with `registry.npmjs.org`; all npm installs use `--ignore-scripts`, disable audit and funding prompts, and keep the selected plugin rows in the Web profile patch.

The helper is mandatory in both modes. It exposes only a read-only `/__deepseek_desktop/plugin-helper` endpoint with the current plugin id, name, and enabled state, so an incomplete optional download remains observable without exposing credentials or mutating configuration.

## Alternatives considered

**Bundle every optional plugin in the offline payload.** Rejected because the offline executable would grow and every plugin update would require rebuilding both setup modes.

**Install floating GitHub branches or run package lifecycle scripts.** Rejected because branch contents can drift and lifecycle scripts add unnecessary supply-chain execution during a user install.

**Use a dynamic plugin marketplace for the setup.** Rejected because installer contents must remain reviewable and pinned; discovery can be added later inside the installed app.

## Consequences

The online setup needs network access and may download the two GitHub archives directly because they are not published to npm. The npm registry fallback covers the Harness closure and npm-published optional packages; a GitHub archive failure still fails the install rather than silently enabling a missing plugin. Pin updates require an intentional catalog change and a new installer build. The helper adds a small local diagnostic surface but does not repair or enable plugins.

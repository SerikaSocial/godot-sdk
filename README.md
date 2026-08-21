# Serika Social — Godot SDK

Creator tooling for [Serika Social](https://github.com/SerikaSocial) worlds and avatars.
Ships as a Godot 4.7 addon (`addons/serika_sdk`).

## Install

Copy `addons/serika_sdk/` into your Godot 4.7 project and enable **Serika SDK** under
*Project → Project Settings → Plugins*. A "Serika" dock appears on the right.

This repo is itself a working Godot project — open it directly to see the demo world
(`demo/world.tscn`) and develop the addon.

## What it provides

- **Authoring nodes** — declarative, no behaviour. They appear in the *Create Node* dialog:
  - `SerikaSpawnPoint` — where players appear (weight, group, default).
  - `SerikaPortal` — jump to another world or a local marker.
  - `SerikaPickup` — grabbable object anchor; ownership follows the relay model.
  - `SerikaAudioZone` — private/quiet/reverb voice volumes.
  - `SerikaMirror` — mirror surface with explicit cost knobs.
- **Validator** (`validator/validator.gd`) — walks the scene against
  [`rules/world_rules.json`](addons/serika_sdk/rules/world_rules.json), **the same rule file
  `server/assetd` loads**. If it passes locally it passes on upload. Deny-by-default: unknown
  node types are rejected, attached scripts are fatal, budgets are enforced.
- **Uploader** (`uploader/uploader.gd`) — packages the world *source* and submits it via the
  API's presigned-upload flow (bytes go straight to storage, never through the API).
  Server-side validation + build is `assetd`'s job (M4); until its ingest endpoint exists the
  uploader packages, presigns, and reports clearly what is not yet wired.
- **Local test harness** — the dock's *Test locally* runs the current scene; the bot-client
  network inspector arrives with M2.

## Configuration

Set these in *Project Settings* (created automatically on first enable):

| Setting | Default |
|---|---|
| `serika/sdk/api_base_url` | `https://api-social.ado.ink` |
| `serika/sdk/session_token` | *(empty — paste your session token to upload)* |

## Testing

The validator has a headless test suite:

```bash
godot --headless --path godot-sdk --script res://tests/run_tests.gd
```

Exits non-zero on failure, so it drops straight into CI.

## Content rules (why validation is strict)

Uploaded worlds are **untrusted**. Creators submit a source project which is compiled
server-side in an isolated container; scripts are stripped at build time against the node
allowlist. Clients never load a creator-produced artifact directly. Behaviour comes from
**SerikaScript** — a sandboxed VM with no reflection, no file/network IO, a whitelisted API,
and per-instance instruction budgets. Static worlds ship first; scripted worlds follow.
Avatars are data-only, always.

The allowlist here and the one in `server/assetd` **must be the same file** — two copies
would drift, and the server's copy is the one that matters for security.

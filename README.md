# Serika Social — Godot SDK

Creator tooling for [Serika Social](https://github.com/SerikaSocial) worlds and avatars.
Ships as a Godot 4.7 addon (`addons/serika_sdk`) plus `Serika.Sdk.dll`.

## What it will provide

- **Authoring nodes** — spawn points, portals, pickups, audio zones, mirrors.
- **Validator** — runs the same rule file as `server/assetd`, so a world that passes
  locally passes on upload. Sharing the rules is the point; two implementations of the
  whitelist would drift and the server's copy is the one that matters for security.
- **Uploader** — packages and submits to the build farm.
- **Local test harness** — run a world with bot clients and a network inspector overlay
  without touching production.

## Content rules

Uploaded worlds are **untrusted**. Creators submit a source project which is compiled
server-side in an isolated container; scripts are stripped at build time against a node
allowlist. Clients never load a creator-produced artifact directly.

Behaviour comes from SerikaScript — a sandboxed VM with no reflection, no file or network
IO, a whitelisted API surface, and per-instance instruction budgets. Static worlds ship
first; scripted worlds follow.

Avatars are data-only, always. VRM 0.x/1.0 and glTF/FBX normalize to one canonical 55-bone
humanoid rig.

> Not started yet — this is a scaffold. See the milestone plan in
> [`docs`](https://github.com/SerikaSocial/docs).

# Edgegap for Godot

Editor plugin to export a Linux dedicated server, containerize it with Docker, and run it locally for Edgegap-oriented workflows.

Supports **Godot 4.x** on **Windows**, **macOS**, and **Ubuntu**.

## Install

1. Copy **only** the `edgegap` folder into your Godot project's `addons/` directory  
   so you end up with `res://addons/edgegap/plugin.cfg`  
   (do **not** copy the whole git repo as `addons/edgegap-godot/...`).
2. Project → Project Settings → Plugins → enable **Edgegap**.
3. Open the **Edgegap** dock (right side, with Inspector) via the toolbar button or **Project → Tools → Edgegap…**. You can drag the dock tab like any other editor panel.

## What it does (v0.1)

1. **Sign in** with an Edgegap API token (stored in EditorSettings, not in your project repo).
   Verification matches the Unity plugin: `POST /v1/wizard/init-quick-start` then `GET /v1/wizard/registry-credentials`.
2. **Validate / install** Linux debug & release export templates.
3. **Export** using preset `Edgegap Linux Server` (created if missing) via headless `--export-debug`.
4. **Containerize** with the bundled Dockerfile (`addons/edgegap/defaults/Dockerfile`).
5. **Run / terminate** local Docker containers started by the plugin.

Upload & cloud deploy come in a later version.

## Notes

- Default export path: `build/edgegap-linux-server.x86_64`
- Default local publish: UDP `7777`
- Docker must be on `PATH`
- API token: [Edgegap user settings](https://app.edgegap.com/user-settings?tab=tokens)
- Discord: https://discord.com/invite/NgCnkHbsGp

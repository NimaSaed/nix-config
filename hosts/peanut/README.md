# peanut — work laptop (Lenovo P14s Gen 5)

Work laptop running **Ubuntu 24.04 LTS** (which cannot be replaced). Nix is used as a *guest*
package manager on top of Ubuntu:

- **`homeConfigurations.peanut`** (home-manager) manages the user environment — shell, CLI tools,
  sway, and GUI apps (`home/nima/peanut.nix`).
- **`systemConfigs.peanut`** (system-manager) manages a thin slice of system state
  (`hosts/peanut/default.nix`): [`nix-system-graphics`](https://github.com/soupglasses/nix-system-graphics)
  populates `/run/opengl-driver` so Nix-built GL/Vulkan apps use the Intel Arc GPU instead of
  software rendering, and a sysctl drop-in re-enables unprivileged user namespaces so
  Chromium/Electron apps (Slack, Bitwarden) can sandbox themselves on Ubuntu 24.04.

> **Why two activations?** Ubuntu owns the base OS, so system state (`/run/opengl-driver`, system
> systemd) and user state (`$HOME`) are managed by two different tools running as two different
> owners (root vs you). `home-manager` cannot populate `/run/opengl-driver`, and you should
> **not** run it with `sudo` (it would create root-owned files in `$HOME`). The graphics step is
> set-and-forget; the daily command is just `home-manager switch`.

## One-time setup

Prerequisites: Nix installed with flakes enabled, and this repo cloned to `~/.nix-config`.

### 1. Apply the system-manager config (root — rare)

Only needs re-running when `hosts/peanut/default.nix` or its inputs change. Sets up
`/run/opengl-driver` (graphics) and the unprivileged-userns sysctl (Electron sandbox):

```bash
cd ~/.nix-config
sudo nix run github:numtide/system-manager -- switch --flake '.#peanut'
```

### 2. Bootstrap home-manager (your user — NOT sudo)

```bash
nix run github:nix-community/home-manager/release-25.11 -- switch --flake .#peanut
```

Subsequent applies (the normal daily command):

```bash
home-manager switch --flake .#peanut
```

### 3. Make sway selectable at the GDM login screen (root — once)

GDM reads session entries from a system path, so this can't be managed by home-manager. Create
`/usr/share/wayland-sessions/sway-nix.desktop`:

```ini
[Desktop Entry]
Name=Sway (Nix)
Exec=/home/nima/.nix-profile/bin/start-sway
Type=Application
```

Use `start-sway`, **not** `sway` directly: GDM execs the session command without a login shell,
so `~/.nix-profile/bin` and the home-manager session vars aren't on the environment. The
`start-sway` wrapper (defined in `home/nima/peanut.nix`) sources those first, otherwise sway
starts but `Mod+Enter` / `Mod+D` silently fail (it can't find `alacritty`/`fuzzel` on `PATH`).
Verify the path after the home-manager switch with `which start-sway`.

Alternatively, test first from a TTY (Ctrl+Alt+F3, log in, then run `start-sway`). The TTY/GDM
path uses sway's DRM backend + logind seat — this is the real test. Launching sway from inside
GNOME only nests it as a client and exercises a different code path.

### 4. Install the lock screen (apt)

The `Mod+l` binding uses Ubuntu's swaylock (`/usr/bin/swaylock`). The Nix swaylock can't
authenticate via PAM on a non-NixOS distro — it loads PAM modules from `/nix/store`, where
there's no setuid helper to read `/etc/shadow`, so the password is never accepted. The distro
build is wired into the system PAM stack:

```bash
sudo apt install swaylock
```

## Verification

```bash
# Hardware acceleration is global after step 1 — should show Intel, not llvmpipe:
nix shell nixpkgs#mesa-demos --command glxinfo -B | grep -i renderer

# SOPS via Bitwarden (after `bw login` / `bw unlock`):
echo "$SOPS_AGE_KEY_CMD"   # -> bw-sops-key
```

In a sway session, confirm: alacritty opens, `fuzzel` launches apps, `Super+Shift+s` screenshots
(grim+slurp), `mako` shows notifications, and Firefox `about:support` reports `WebRender`
(not `WebRender (Software)`).

## Optional follow-ups

Add to `home/nima/peanut.nix` once the base session is confirmed:

- Screen-share portals: `xdg-desktop-portal-wlr`
- Idle/lock management: `swayidle`
- Brightness/audio media keys

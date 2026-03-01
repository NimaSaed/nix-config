# Using the 1Password SSH Agent with the Nix Remote Builder

My Mac is Apple Silicon (aarch64). Most of my NixOS machines are x86_64. To avoid building
Linux closures through slow emulation, I use chestnut (an x86_64 server) as a remote Nix
builder by passing `--option builders` to nixos-anywhere during installation.

It took a few non-obvious steps to get it working with 1Password as the SSH key store.

## The trusted-users problem

The first thing that happens when you try this from a standard nix-darwin setup is nothing.
The daemon silently drops the flag:

```
warning: ignoring the client-specified setting 'builders',
         because it is a restricted setting and you are not a trusted user
```

`builders` is a restricted setting in Nix. Only users listed in `trusted-users` can override
it at runtime. The fix is a one-liner in your nix-darwin config:

```nix
nix.settings.trusted-users = [ "root" "nima" ];
```

After `darwin-rebuild switch`, the daemon respects the flag and actually tries to reach
the builder.

## The SSH authentication problem

The Nix daemon runs as root. Root has its own SSH environment — separate known_hosts, no
access to your user's running SSH agent, no access to your 1Password agent socket at
`~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock`.

The next failure looks like this:

```
cannot build on 'ssh://root@chestnut.nmsd.xyz': error: failed to start SSH
connection to 'chestnut.nmsd.xyz': Host key verification failed.
```

Two problems at once: chestnut isn't in root's known_hosts, and root has no key to
authenticate with.

The obvious workaround is generating a dedicated SSH key for root and adding it to the
builder's `authorized_keys`. That works, but it means storing a private key on disk, which
defeats the point of keeping keys in 1Password.

## Pointing root at the 1Password agent

The 1Password SSH agent is a Unix socket. On macOS, root bypasses DAC (discretionary access
control), so it can connect to a socket owned by another user. Unlike the standard
`ssh-agent` — which calls `getpeereid()` and rejects connections from processes running as a
different UID — the 1Password agent doesn't enforce this at the socket level. Its
authorization model is at the app layer: you approve each SSH client once in the 1Password
UI, and after that it responds to any process that can reach the socket.

Add chestnut to root's known_hosts:

```bash
sudo ssh-keyscan -t ed25519 chestnut.nmsd.xyz | sudo tee -a /var/root/.ssh/known_hosts
```

Create `/var/root/.ssh/config` pointing at the 1Password socket:

```
Host *
    IdentityAgent "/Users/nima/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

Test it:

```bash
sudo ssh -o BatchMode=yes root@chestnut.nmsd.xyz echo ok
```

If that prints `ok`, the daemon can now reach the builder and authenticate using whatever
keys you have in 1Password.

## Caveats

This relies on 1Password not adding UID enforcement to the agent socket. That's an
implementation detail, not a guarantee. The correct long-term fix is tracked in
[NixOS/nix#10124](https://github.com/NixOS/nix/issues/10124) — proper `SSH_AUTH_SOCK`
forwarding to the daemon. Until that lands, this works.

This setup isn't managed by nix-darwin, so it needs to be done manually after any OS
reinstall.

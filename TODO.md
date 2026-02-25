# Podman Modules TODO

Items identified during review that need attention.

## Security

### Collabora CODE insecure with rootless Podman
Collabora in `pod-nextcloud.nix` uses `--o:mount_namespaces=false` to work around rootless
Podman's inability to provide CAP_MKNOD. This disables document-level isolation (jails), which
is a core security feature. According to Collabora: "altering these defaults potentially opens
you to significant risk."

**Impact:** Documents from different users/sessions can potentially access each other's data.
Not acceptable for production multi-user environments.

**Solution:** Move Collabora to one of:
1. **Rootful Podman with minimal capabilities** (recommended):
   - Run under separate podman user with root privileges
   - Use `--cap-drop=ALL --cap-add=SYS_CHROOT,SYS_ADMIN,FOWNER,CHOWN`
   - Maintains document isolation while limiting attack surface
2. **Separate VM with rootful Podman** (maximum isolation):
   - VM-level isolation + proper container isolation
   - Still use minimal capabilities inside VM
3. **Custom seccomp profile** (advanced):
   - Drop all capabilities, restrict syscalls to only what Collabora needs

**Do NOT use for production** until moved to rootful environment with proper isolation.
- File: `pod-nextcloud.nix` (Collabora container, line ~298)
- Reference: https://sdk.collaboraonline.com/docs/installation/CODE_Docker_image.html

### Traefik API exposed on port 8080 without authentication
Port 8080 is published externally and `TRAEFIK_API_INSECURE=true` serves the dashboard
without auth. Either remove `"8080:8080"` from `publishPorts` (access dashboard only via
the HTTPS route) or enable Authelia protection on the Traefik dashboard route.
- File: `pod-reverse-proxy.nix` (publishPorts + TRAEFIK_API_INSECURE)

### ~~ForwardAuth uses `host.docker.internal`~~ DONE
Switched to `http://auth:9091/api/authz/forward-auth` using pod DNS on the shared
`reverse_proxy` network.

### OIDC client secrets may need hashing
Authelia has deprecated plaintext client secrets. Verify the sops-encrypted secret files
contain PBKDF2-SHA512 hashed values (not plaintext). Generate with:
```bash
authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72
```
Store the hash in sops, give the plaintext to the relying party (Nextcloud/Jellyfin).

## Configuration

### Missing `domain` on nutcracker host
`hosts/nutcracker/default.nix` doesn't set `services.pods.domain`, so it defaults to
`"example.com"`. Traefik will try to route/certify for `example.com` subdomains.

### Homepage references hardcoded subdomains
`container-configs/homepage.nix` has several services with hardcoded subdomains
(changedetection, scrypted, cloud, srv1, jellyseerr, sonarr, radarr, nzbget) that
don't come from module options. Consider adding them as options for consistency.

### LLDAP TCP router uses wildcard SNI
`HostSNI(\`*\`)` matches all hostnames on the lldapsecure entrypoint. Consider restricting
to `HostSNI(\`${cfg.lldap.subdomain}.${domain}\`)` for specificity.
- File: `pod-auth.nix` (line ~229)

## Minor

- `TRAEFIK_SERVERSTRANSPORT_INSECURESKIPVERIFY=true` skips TLS verification for
  backends. Fine for homelab but worth a comment explaining why.
- Authelia LDAP `tls.skip_verify: true` - same, document the reason.
- Missing `TZ` env var on some containers (Jellyfin, Homepage, IT Tools, Dozzle) while
  auth containers have it set.
- `autoStart = true` is redundant (it's the default in quadlet-nix). Not harmful but
  adds visual noise.

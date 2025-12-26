# SOPS Setup and Usage Guide

Complete guide for setting up and using SOPS (Secrets OPerationS) with age encryption and 1Password integration.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
  - [1. Install Required Tools](#1-install-required-tools)
  - [2. Generate Age Key Pair](#2-generate-age-key-pair)
  - [3. Store Private Key in 1Password](#3-store-private-key-in-1password)
  - [4. Configure Environment Variable](#4-configure-environment-variable)
  - [5. Create .sops.yaml Configuration](#5-create-sopsyaml-configuration)
  - [6. Test the Setup](#6-test-the-setup)
- [Working with SOPS](#working-with-sops)
  - [Creating and Editing Encrypted Files](#creating-and-editing-encrypted-files)
  - [Encrypting Existing Files](#encrypting-existing-files)
  - [Decrypting Files](#decrypting-files)
  - [Viewing Encrypted Content](#viewing-encrypted-content)
  - [Partial Encryption](#partial-encryption)
  - [Key Management](#key-management)
  - [Advanced Usage](#advanced-usage)
- [Best Practices](#best-practices)
- [Git Integration](#git-integration)
- [Troubleshooting](#troubleshooting)

---

## Overview

This guide demonstrates how to:
- Use **age** for modern, secure encryption
- Store your private key securely in **1Password**
- Retrieve keys on-demand using **1Password CLI** (never writing keys to disk)
- Configure SOPS for automatic key selection based on file paths

### Why This Setup?

- **Secure**: Private keys never written to disk
- **Convenient**: Keys retrieved automatically from 1Password
- **Flexible**: Support for multiple servers/hosts with different keys
- **Version Control Friendly**: Encrypted files can be safely committed to git

---

## Prerequisites

Before starting, ensure you have:

1. **1Password account** with CLI access
2. **1Password CLI (op)** installed and configured
3. **NixOS** or ability to use `nix-shell` (or install `age` and `sops` via your package manager)

Check if 1Password CLI is working:
```bash
op account list
```

---

## Initial Setup

### 1. Install Required Tools

**Using Nix (recommended):**
```bash
# Test that tools are available
nix-shell -p age sops --run "age-keygen --version && sops --version"
```

**Using Homebrew (macOS):**
```bash
brew install age sops
```

### 2. Generate Age Key Pair

Generate a new age encryption key:

```bash
nix-shell -p age --run "age-keygen" | tee /tmp/age-key-output.txt
```

**Output will look like:**
```
# created: 2025-11-04T21:50:11+01:00
# public key: age1v34yzz3ke7z64gfnue7pu4qqu5prkzk3xgca005hydeynjkdm5xqpu6cl5
AGE-SECRET-KEY-1498G8RJ8N0RJRJ8M4WWXUQNEA7GSKDDR56VECXL3G33AS2R29V8QYXZFN9
```

**Important:**
- Save the **public key** (age1...) - you'll need this for `.sops.yaml`
- The **secret key** (AGE-SECRET-KEY-...) will be stored in 1Password

### 3. Store Private Key in 1Password

Store the age secret key securely in 1Password:

```bash
# Replace with your actual secret key
op item create \
  --category password \
  --title "SOPS Age Private Key" \
  password="AGE-SECRET-KEY-YOUR-KEY-HERE" \
  'notesPlain=SOPS Age Public key: age1YOUR-PUBLIC-KEY-HERE'
```

Verify you can retrieve it:
```bash
op item get "SOPS Age Private Key" --fields password --reveal
```

**Clean up the temporary file:**
```bash
rm /tmp/age-key-output.txt
```

### 4. Configure Environment Variable

Add the SOPS environment variable to your shell configuration file.

**For Bash (~/.bashrc or ~/.bash_profile):**
```bash
# Add this line to your ~/.bashrc
export SOPS_AGE_KEY_CMD="op item get 'SOPS Age Private Key' --fields password --reveal"
```

**Reload your shell configuration:**
```bash
source ~/.bashrc
```

### 5. Create .sops.yaml Configuration

Create a `.sops.yaml` file in your repository root to define encryption rules:

```yaml
# SOPS Configuration File
#
# This file tells sops which keys to use for encrypting secrets.

keys:
  # Your personal age key (stored in 1Password)
  # For local encryption/decryption
  - &personal age1...

  # Server age keys (if deploying to servers)
  # Get server key: ssh root@server "cat /etc/ssh/ssh_host_ed25519_key.pub" | ssh-to-age
  - &server1 age1...

  # Add more servers as needed:
  # - &server2 age1...

creation_rules:
  # Secrets for server1
  - path_regex: hosts/server1/secrets\.yaml$
    key_groups:
      - age:
          - *personal
          - *server1

  # Secrets for server2
  # - path_regex: hosts/server2/secrets\.yaml$
  #   key_groups:
  #     - age:
  #         - *personal
  #         - *server2

  # Global secrets accessible by all hosts
  # - path_regex: secrets/common\.yaml$
  #   key_groups:
  #     - age:
  #         - *personal
  #         - *server1
  #         - *server2
```

**To get a server's age key:**
```bash
# Get SSH host key and convert to age format
ssh root@your-server.com "cat /etc/ssh/ssh_host_ed25519_key.pub" | \
  nix-shell -p ssh-to-age --run "ssh-to-age"
```

### 6. Test the Setup

Create a test secrets file:

```bash
cat > hosts/server1/secrets.yaml <<EOF
# Example secrets for server1
example_password: changeme123
api_key: test-api-key-value
database_url: postgresql://user:pass@localhost/db
EOF
```

**Encrypt the file:**
```bash
nix-shell -p sops --run "sops encrypt --in-place hosts/server1/secrets.yaml"
```

**Verify you can decrypt it:**
```bash
nix-shell -p sops --run "sops decrypt hosts/server1/secrets.yaml"
```
---

## Working with SOPS

### Creating and Editing Encrypted Files

#### Create a New Encrypted File

Use `sops edit` to create and edit encrypted files:

```bash
# Create/edit a file (SOPS determines keys from .sops.yaml)
nix-shell -p sops --run "sops hosts/server1/secrets.yaml"
```

SOPS will:
1. Check if the file exists
2. Match the path against `.sops.yaml` creation rules
3. Encrypt with the appropriate keys
4. Open in your editor (`$EDITOR` or vim by default)
5. Re-encrypt on save

#### Specify a Different Editor

```bash
# Use a specific editor
EDITOR=vim nix-shell -p sops --run "sops hosts/server1/secrets.yaml"

# Or set permanently
export SOPS_EDITOR=vim
```

### Encrypting Existing Files

#### Encrypt In-Place

```bash
# Encrypts the file directly (overwrites original)
nix-shell -p sops --run "sops encrypt --in-place myfile.yaml"
```

#### Encrypt to New File

```bash
# Encrypt and save to a new file
nix-shell -p sops --run "sops encrypt myfile.yaml > myfile.enc.yaml"
```

#### Encrypt with Specific Keys

```bash
# Override .sops.yaml and specify keys directly
nix-shell -p sops --run "sops encrypt --age age1public1,age1public2 myfile.yaml"
```

### Decrypting Files

#### Decrypt to stdout

```bash
# View decrypted content without modifying the file
nix-shell -p sops --run "sops decrypt hosts/server1/secrets.yaml"
```

#### Decrypt In-Place

```bash
# WARNING: This will overwrite the encrypted file with plaintext!
nix-shell -p sops --run "sops decrypt --in-place hosts/server1/secrets.yaml"
```

#### Decrypt to New File

```bash
# Decrypt and save to a new file
nix-shell -p sops --run "sops decrypt hosts/server1/secrets.yaml > secrets-plain.yaml"
```

### Viewing Encrypted Content

#### Extract Specific Values

```bash
# Extract a single value
nix-shell -p sops --run "sops decrypt --extract '[\"api_key\"]' hosts/server1/secrets.yaml"

# Extract nested value
nix-shell -p sops --run "sops decrypt --extract '[\"database\"][\"password\"]' hosts/server1/secrets.yaml"

# Extract array element
nix-shell -p sops --run "sops decrypt --extract '[\"servers\"][0]' hosts/server1/secrets.yaml"
```

### Partial Encryption

Encrypt only specific keys in a file, leaving others in plaintext:

#### Encrypt Only Matching Keys

```bash
# Encrypt only keys matching regex pattern
nix-shell -p sops --run "sops encrypt --encrypted-regex '^(password|secret|key)$' config.yaml"

# For Kubernetes secrets, encrypt only data/stringData
nix-shell -p sops --run "sops encrypt --encrypted-regex '^(data|stringData)$' k8s-secret.yaml"
```

#### Leave Specific Keys Unencrypted

```bash
# Encrypt everything EXCEPT matching keys
nix-shell -p sops --run "sops encrypt --unencrypted-regex '^(description|metadata|name)$' config.yaml"
```

**Example .sops.yaml with regex rules:**
```yaml
creation_rules:
  - path_regex: k8s/.*\.yaml$
    encrypted_regex: '^(data|stringData)$'
    age: 'age1...'
```

### Key Management

#### Update Keys

When you add/remove keys in `.sops.yaml`, update existing encrypted files:

```bash
# Update keys for a file based on current .sops.yaml
nix-shell -p sops --run "sops updatekeys hosts/server1/secrets.yaml"
```

#### Rotate Data Encryption Key

Generate a new data encryption key (best practice periodically):

```bash
# Rotate the data key (file stays encrypted with same master keys)
nix-shell -p sops --run "sops rotate --in-place hosts/server1/secrets.yaml"
```

#### Add/Remove Keys

```bash
# Add a new age key to an existing file
nix-shell -p sops --run "sops rotate --add-age age1newkey... --in-place hosts/server1/secrets.yaml"

# Remove an age key
nix-shell -p sops --run "sops rotate --rm-age age1oldkey... --in-place hosts/server1/secrets.yaml"
```

### Advanced Usage

#### Using Encrypted Secrets in Scripts

**Pass secrets as environment variables:**

```bash
# Decrypt file and inject as environment variables
nix-shell -p sops --run "sops exec-env hosts/server1/secrets.yaml 'bash -c \"echo \$api_key\"'"

# Run a script with secrets in environment
nix-shell -p sops --run "sops exec-env secrets.yaml './deploy.sh'"
```

**Pass secrets as a temporary file:**

```bash
# Use {} as placeholder for temporary file path
nix-shell -p sops --run "sops exec-file secrets.yaml 'cat {}'"

# Pass to a program expecting a config file
nix-shell -p sops --run "sops exec-file secrets.yaml './app --config {}'"
```

#### Working with Different Formats

SOPS supports multiple formats:

```bash
# JSON
nix-shell -p sops --run "sops encrypt secrets.json"

# YAML
nix-shell -p sops --run "sops encrypt secrets.yaml"

# ENV files
nix-shell -p sops --run "sops encrypt secrets.env"

# Binary files
nix-shell -p sops --run "sops encrypt --input-type binary secrets.key"

# INI files
nix-shell -p sops --run "sops encrypt config.ini"
```

#### Encrypt from stdin

```bash
# Encrypt data from stdin (must specify filename for format detection)
echo 'password: secret123' | \
  nix-shell -p sops --run "sops encrypt --filename-override secrets.yaml /dev/stdin > encrypted.yaml"
```

---

## Best Practices

### Security

1. **Never commit unencrypted secrets** to version control
2. **Rotate keys periodically** using `sops rotate`
3. **Use different keys** for different environments (dev/staging/prod)
4. **Limit key access** - only give server keys to the servers that need them
5. **Review .sops.yaml carefully** before committing
6. **Use specific path patterns** in `.sops.yaml` to prevent accidental encryption with wrong keys

### Key Management

1. **Backup your 1Password vault** - it contains your only copy of the private key
2. **Document which public keys** correspond to which servers/users
3. **Keep age public keys** in `.sops.yaml` under version control
4. **Never commit private keys** (your setup prevents this, but be vigilant)
5. **Use multiple recipients** for redundancy (personal key + server key)

### File Organization

```
repo/
├── .sops.yaml              # SOPS configuration (commit this)
├── hosts/
│   ├── server1/
│   │   └── secrets.yaml    # Encrypted (safe to commit)
│   ├── server2/
│   │   └── secrets.yaml    # Encrypted (safe to commit)
└── docs/
    └── SOPS-SETUP-GUIDE.md # This guide
```

### Naming Conventions

- Use `.sops.yaml` suffix for encrypted files (optional but clear)
- Use descriptive paths like `hosts/servername/secrets.yaml`
- Keep secrets files separate from regular config

---

## Git Integration

### View Diffs of Encrypted Files

Configure git to decrypt files for diffs:

**Add to `.gitattributes`:**
```
*.yaml diff=sopsdiffer
secrets.yaml diff=sopsdiffer
```

**Configure git:**
```bash
git config diff.sopsdiffer.textconv "sops decrypt"
```

Now `git diff` will show decrypted content for encrypted files.

### Pre-commit Hooks

Consider adding a pre-commit hook to ensure secrets are encrypted:

**Create `.git/hooks/pre-commit`:**
```bash
#!/bin/bash
# Check that secrets files are encrypted

FILES=$(git diff --cached --name-only | grep secrets.yaml)

for file in $FILES; do
  if ! grep -q "sops:" "$file"; then
    echo "ERROR: $file is not encrypted!"
    echo "Run: sops encrypt --in-place $file"
    exit 1
  fi
done
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

---

## Troubleshooting

### "Failed to get the data key"

**Problem:** SOPS can't retrieve your private key.

**Solutions:**
1. Check 1Password CLI is authenticated: `op account list`
2. Verify environment variable: `echo $SOPS_AGE_KEY_CMD`
3. Test key retrieval: `op item get 'SOPS Age Private Key' --fields password --reveal`
4. Reload your shell config: `source ~/.bashrc`

### "no matching creation rule"

**Problem:** SOPS can't find a rule in `.sops.yaml` for your file.

**Solutions:**
1. Check your file path matches a `path_regex` in `.sops.yaml`
2. Verify `.sops.yaml` is in the repository root or parent directory
3. Manually specify keys: `sops encrypt --age age1... myfile.yaml`

### "Error decrypting key: no key could decrypt the file"

**Problem:** Your private key doesn't match any of the encrypted recipients.

**Solutions:**
1. Verify your public key is in the file's encryption metadata
2. Check the file was encrypted for your key: `sops decrypt hosts/server1/secrets.yaml | grep -A5 "sops:"`
3. Re-encrypt with correct keys: `sops updatekeys hosts/server1/secrets.yaml`

### Editor Doesn't Open

**Problem:** `sops edit` doesn't open a file.

**Solutions:**
1. Set editor explicitly: `EDITOR=vim sops edit secrets.yaml`
2. Check `$EDITOR` or `$SOPS_EDITOR` environment variable
3. Try default: `sops edit --editor vim secrets.yaml`

### "age: invalid key format"

**Problem:** Age key format is incorrect.

**Solutions:**
1. Verify public key starts with `age1`
2. Verify secret key starts with `AGE-SECRET-KEY-`
3. Check for extra whitespace or line breaks
4. Regenerate keys if corrupted

---

## Quick Reference

### Common Commands

```bash
# Edit encrypted file
sops hosts/server1/secrets.yaml

# Encrypt existing file
sops encrypt --in-place myfile.yaml

# Decrypt to stdout
sops decrypt myfile.yaml

# Extract single value
sops decrypt --extract '["key"]' myfile.yaml

# Update keys after changing .sops.yaml
sops updatekeys myfile.yaml

# Rotate data key
sops rotate --in-place myfile.yaml

# Use secrets in script
sops exec-env secrets.yaml './script.sh'
```

### Environment Variables

```bash
export SOPS_AGE_KEY_CMD="op item get 'SOPS Age Private Key' --fields password --reveal"
export SOPS_EDITOR="vim"           # Preferred editor
export SOPS_AGE_RECIPIENTS="age1..."  # Default recipients for new files
```

---

## Additional Resources

- **SOPS GitHub**: https://github.com/getsops/sops
- **Age Encryption**: https://age-encryption.org/
- **1Password CLI**: https://developer.1password.com/docs/cli/
- **NixOS SOPS Module**: https://github.com/Mic92/sops-nix

---


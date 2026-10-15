# Security Policy

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Use GitHub's private reporting instead: go to the repository's **Security** tab → **Report a vulnerability**. Include the steps to reproduce, the macOS version and the affected commit. You should get a reply within a few days.

## Security notes for users

- **Never commit or share anything inside `vms/`.** An installed `disk.img` contains your guest system: password hashes, shell history, SSH keys, browser data and anything else you saved. The `.gitignore` excludes `vms/`, disk images and ISOs; keep it that way.
- **The shared folder is read-write.** Everything in `vms/<name>/compartilhado` on the Mac can be read, changed or deleted by the guest. Do not put sensitive files there, especially when the guest runs untrusted software or security tools.
- **Networking uses NAT.** The guest reaches the internet through the Mac and is not directly reachable from your local network. Traffic still leaves through your Mac's connection, so tools you run inside the guest are attributed to your network.
- **Download ISOs only from the distributions' official sites** and verify their checksums/signatures. This project does not ship or redistribute any ISO.
- The binary is **ad-hoc signed** (no Developer ID). Build it from source with `./build.sh` rather than running a binary from an unknown source.

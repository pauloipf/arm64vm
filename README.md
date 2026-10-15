# Virtualization ARM64

🇧🇷 [Leia em português](README.pt-BR.md)

A minimal Linux (ARM64) virtual machine manager for Apple Silicon Macs, built on macOS's native `Virtualization.framework`: no VirtualBox, UTM or Parallels. It started with **Kali Linux** and runs other ARM64 distributions too. Each VM lives in its own folder, and the whole tool is a single Swift file.

> The program's own messages (`--help`, errors) are in Portuguese.

## Requirements

- A Mac with **Apple Silicon** (M1 or later)
- **macOS 14 (Sonoma)** or later
- Xcode Command Line Tools: `xcode-select --install`
- An **ARM64/aarch64** ISO of the distribution you want to install (see [Other distributions](#other-distributions))

## Installation

```sh
git clone https://github.com/pauloipf/arm64vm.git
cd arm64vm
./build.sh
```

`build.sh` compiles `main.swift` and signs the binary with `entitlements.plist` (the `com.apple.security.virtualization` entitlement). Without that signature, macOS will not let the VM start. Run the script again after any change to the code.

## Layout

```
arm64vm/
├── main.swift           source code
├── build.sh             compiles and signs
├── entitlements.plist   com.apple.security.virtualization entitlement
├── arm64vm              binary (created by build.sh, ignored by git)
└── vms/                 your VMs: local, ignored by git, NEVER publish it
    └── <name>/          one folder per VM (e.g. kali, ubuntu)
        ├── disk.img       virtual disk (sparse: only uses the space actually written)
        ├── efi_variables  UEFI variables (created automatically)
        ├── config.json    the VM's CPU and RAM (created automatically)
        ├── *.iso          installer (only used with --install)
        └── compartilhado/ folder shared with the guest
```

## VM configuration

- **CPU:** 2 to 4 cores by default (the Mac's total minus 2), adjustable with `--cpus`
- **Memory:** 4 GB by default, adjustable with `--mem`, with a memory balloon
- **Boot:** UEFI
- **Disk:** `disk.img` over virtio. With `--install`, the ISO is attached as a USB drive
- **Network:** NAT (the VM reaches the internet through the Mac)
- **Display:** virtio, 1920×1080, resized automatically with the window
- **Input:** USB keyboard and USB screen-coordinate pointer
- **Audio:** output only
- **Shared folder:** virtiofs with the tag `compartilhado`

Files are looked up in the folder that contains the binary, so `arm64vm` can be run from any directory.

## Usage

### Step by step: an Ubuntu VM

Run every command from the project folder (`cd arm64vm`), in this order.

1. **Download the ISO.** Get the **ARM64** version of Ubuntu (Desktop or Server) from [ubuntu.com/download](https://ubuntu.com/download). Then compare its checksum with the one published on the site:
   ```sh
   shasum -a 256 ~/Downloads/ubuntu-*-arm64.iso
   ```
2. **Create the VM's folder and move the ISO into it.** The folder name is the VM's name:
   ```sh
   mkdir -p vms/ubuntu
   mv ~/Downloads/ubuntu-*-arm64.iso vms/ubuntu/
   ```
3. **Create the disk and boot the installer:**
   ```sh
   ./arm64vm --vm ubuntu --new 64g --install
   ```
   `--new` creates a sparse `disk.img` of the requested size (`64g`, `128g`...) and **refuses** to overwrite an existing disk. To also choose cores and RAM now, add them: `--cpus 4 --mem 6g`.
4. **Install Ubuntu** in the window that opens. When partitioning, pick the **virtio disk** (the size you chose). Do not pick the USB drive, which is the ISO.
5. **Reboot.** When the installer asks to reboot, the window closes on its own (or close it yourself).
6. **Start the installed system.** From now on, always start without `--install`:
   ```sh
   ./arm64vm --vm ubuntu
   ```
7. **Optional: adjust cores and RAM** with the VM off. The values are saved for later boots:
   ```sh
   ./arm64vm --vm ubuntu --cpus 6 --mem 8g
   ```
8. **Check your VMs:**
   ```sh
   ./arm64vm --list
   ```
9. **Optional: free space** by deleting the ISO, which is no longer needed:
   ```sh
   rm vms/ubuntu/ubuntu-*-arm64.iso
   ```

The same steps work for any distribution in [Other distributions](#other-distributions). Only the ISO and the VM's name change.

### Command reference

| Command | What it does |
|---|---|
| `./arm64vm --vm <name>` | Starts the VM from its disk |
| `./arm64vm --vm <name> --new 64g --install` | Creates the VM with a new disk and boots the installer |
| `./arm64vm --vm <name> --install` | Boots the installer using the only `.iso` in `vms/<name>/` |
| `./arm64vm --vm <name> --install other.iso` | Boots the installer using a specific ISO |
| `./arm64vm --vm <name> --cpus 6 --mem 8g` | Changes cores and RAM (saved) and starts the VM |
| `./arm64vm --list` | Lists VMs with cores, RAM and disk |
| `./arm64vm --help` | Shows help |

Without `--vm`, the tool uses the existing VM if there is only one. With more than one, it asks you to pick.

### Cores and RAM

Cores and RAM can be changed at any time while the VM is off, without affecting the installed system.

- Values are stored in `vms/<name>/config.json`. Each VM has its own, and you can edit the file directly.
- `--mem` accepts `8g` or `8gb`, in whole gigabytes.
- Limits: from 1 core up to the Mac's total, and from 1 GB up to the Mac's RAM minus 2 GB, which stay reserved for macOS. Values outside these limits are rejected.
- The **disk size** cannot be changed this way. It is set with `--new`.

### Reinstalling a VM from scratch

With the VM off, delete its folder and create it again. **This erases the installation**:

```sh
mv vms/kali/kali-linux-*.iso ~/Downloads/   # keep the ISO if you will reuse it
rm -r vms/kali
mkdir -p vms/kali && mv ~/Downloads/kali-linux-*.iso vms/kali/
./arm64vm --vm kali --new 64g --install
```

`efi_variables` is recreated as well. That is necessary, because it stores the previous installation's boot order.

### Shutting down

- Closing the window or pressing **Cmd+Q** sends a shutdown request to the guest, like pressing a power button. The app quits on its own once the guest has shut down.
- If the guest does not respond, close the window again. A dialog offers **Forçar desligamento** (force shutdown), which is like pulling the plug and may lose unsaved data.
- Shutting down or rebooting from inside the VM (`sudo poweroff`, `sudo reboot`) also quits the app.

### Keyboard

Click inside the window so it receives keyboard input. While the window has focus, system shortcuts such as Cmd+Tab go to the VM.

## Other distributions

Any distribution with an **ARM64 (aarch64)** ISO that boots via **UEFI** should work, for example:

| Distribution | Which ISO to download |
|---|---|
| Kali Linux | **ARM64** installer |
| Ubuntu | Ubuntu Desktop or Server for **ARM64** |
| Debian | `debian-*-arm64-netinst.iso` |
| Fedora | Workstation or Server for **aarch64** |
| openSUSE | Tumbleweed or Leap for **aarch64** |
| Rocky / AlmaLinux | DVD or minimal for **aarch64** |
| Arch Linux ARM | Manual installation, more work |

**x86_64 / amd64** ISOs (the "default" download on most sites) **do not work**, because `Virtualization.framework` does not emulate other architectures.

All of these distributions support virtio disk, network, display, keyboard and mouse out of the box.

## Shared folder

Each VM's `vms/<name>/compartilhado` folder is available inside the VM under the tag `compartilhado`. It is **read-write**: the guest can change and delete anything in it, so do not put sensitive files there.

To mount it once:

```sh
sudo mkdir -p /mnt/compartilhado
sudo mount -t virtiofs compartilhado /mnt/compartilhado
```

To mount it on every boot, add this line to the VM's `/etc/fstab`:

```
compartilhado  /mnt/compartilhado  virtiofs  rw,nofail  0  0
```

## Troubleshooting

| Problem | What to do |
|---|---|
| Keyboard does not work | Click inside the VM window |
| VM boots the installer again | Start without `--install` |
| "VM não encontrada" (VM not found) | Check the name with `./arm64vm --list`, or create the VM with `--new` |
| "disk.img já existe" (already exists) | `--new` never overwrites disks. See [Reinstalling a VM from scratch](#reinstalling-a-vm-from-scratch) |
| "Nenhuma .iso encontrada" (no .iso found) | Put the ISO inside `vms/<name>/` |
| "Mais de uma .iso na pasta" (more than one .iso) | Name the ISO: `./arm64vm --vm <name> --install <file.iso>`, or remove the old ones |
| Installer does not start or black screen | Make sure the ISO is **ARM64/aarch64**, not amd64 |
| "Núcleos inválidos" / "Memória inválida" | Use values within the limits shown in the message |
| "Indique a VM com --vm" (pick a VM) | There is more than one VM: pass `--vm <name>` (see `./arm64vm --list`) |
| "Erro ao iniciar a VM" or a permission error | Run `./build.sh` again to re-sign the binary |

## Security

- **Never publish or share the `vms/` folder.** An installed `disk.img` holds the whole guest system: password hashes, shell history, SSH keys and so on. The `.gitignore` already excludes `vms/`, disk images and ISOs.
- To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Disclaimer

This project is not affiliated with Apple, OffSec (Kali Linux) or any of the distributions mentioned. All trademarks belong to their respective owners. No ISO is distributed here: always download them from the official sites. Security tools, such as those in Kali, must only be used on systems you are authorized to test.

## License

Distributed under the [Apache License 2.0](LICENSE). See also the [NOTICE](NOTICE) file.

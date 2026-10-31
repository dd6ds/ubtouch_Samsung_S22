# Ubuntu Touch 24.04 for Galaxy S22 / S22 Ultra (Exynos)

Build + flash kit for **Ubuntu Touch 24.04-2.x on Halium 16** for

| Phone | Model | Codename | Wi-Fi |
|---|---|---|---|
| Galaxy S22 | SM-S901B, SM-S901B/DS | `r0s` | Qualcomm QCA6490 (`wlan`) |
| Galaxy S22 Ultra | SM-S908B, SM-S908B/DS | `b0s` | Broadcom BCM4389 (`dhd`) |

Both use the Exynos 2200 (`s5e9925`) and share one kernel tree.
**US/Canada Snapdragon models (S901U/U1/W, S908U/U1/W) are not supported**: their bootloader cannot be unlocked.

> **Status: experimental bring-up.** There is no official or community Ubuntu Touch port for
> these phones. This kit builds a first port from LineageOS 23.2's kernel and UBports' generic
> Halium pieces. Expect the first images to need on-device debugging. See [Known gaps](#known-gaps).

## How it fits together

```
 boot.img         LineageOS s5e9925 kernel (5.10 GKI) + Halium config  +  Halium "dynparts" initramfs
 vendor_boot.img  first-stage modules (modules/<dev>.load) + GPU/touch firmware + dtb + cmdline
 dtbo.img         board-revision overlays (dts/<dev>.cfg)
 /data/ubuntu.img UT 24.04-2.x rootfs + Halium 16 GSI (LXC) + all kernel modules + device layer
 super            untouched: the phone's own vendor / vendor_dlkm (Android 16, One UI 8 or LineageOS 23.2)
```

The Halium initramfs loads the vendor_boot modules, maps the `super` subpartitions, mounts
`/data`, loop-mounts `ubuntu.img` and starts Ubuntu Touch; Android's vendor HALs run in the LXC
container. Same idea as the [Pixel 6a port](https://github.com/logicalangel/ubuntu-touch-bluejay).

Why the kernel is rebuilt: the stock/LineageOS kernel lacks things Ubuntu needs (`SYSVIPC`,
`DEVTMPFS`, `VT`, `FHANDLE`, `USER_NS`, … see `kernel/halium-samsung.config`). Enabling them
changes the module ABI, so **every** module comes from our build: first-stage ones in
vendor_boot, the `/vendor_dlkm` ones (Wi-Fi, fingerprint) via `/etc/modules-load.d` in the rootfs.

## Before you start: read this

- **Unlocking trips Knox permanently** (Samsung Pay/Wallet, Secure Folder, Samsung Pass are gone
  for good, even after relocking) and **wipes the phone**.
- Update to the **latest stock firmware (One UI 8 / Android 16)** first. Halium 16 must match the
  Android version of the vendor partition. Samsung's anti-rollback means you cannot go back to
  older firmware later.
- Have the phone charged > 60 %, and a USB-C data cable.
- Everything here except the one-time recovery install runs from Linux with `adb`.

## 1. Unlock the bootloader

1. Settings → About phone → Software information → tap *Build number* 7× → Developer options →
   **OEM unlocking** on. (If the switch is missing, connect to the internet and wait; it can take
   days to appear on new/refurbished phones.)
2. Power off. Hold **Vol Up + Vol Down** and plug in USB → Download-mode warning → **long-press
   Vol Up** → confirm unlock. The phone wipes and reboots; skip setup, enable Developer options
   again and check *OEM unlocking* is still on (greyed out = unlocked).

## 2. Install LineageOS recovery (and preferably LineageOS 23.2)

Follow the official guide for your device: [S22 r0s](https://wiki.lineageos.org/devices/r0s/install/),
[S22 Ultra b0s](https://wiki.lineageos.org/devices/b0s/install/). It flashes `recovery.img` and
`vbmeta.img` from Download mode with Odin (Windows) or `odin4` / Heimdall (Linux).

- **Path A, recommended:** install LineageOS 23.2 completely and boot it once. Then you know the
  hardware/vendor combo works, and the kernel built here is the same source.
- **Path B:** stay on stock One UI 8 and only flash LineageOS recovery + its vbmeta. Then pass
  `--vbmeta` to `flash.sh` in step 5.

## 3. Pull templates + backup from the phone

Boot into recovery (phone off, USB connected, hold **Power + Vol Up**), choose
*Advanced → Enable ADB*, then on the PC:

```bash
scripts/pull-templates.sh r0s        # or b0s
```

This saves the phone's own `boot`, `vendor_boot`, `dtbo`, `recovery`, `vbmeta` (**keep these as
your backup**), takes the exact boot-header values (OS patch level, offsets, cmdline,
bootconfig) and extracts the first-stage firmware from vendor_boot (Xclipse GPU `sgpu`,
touchscreen, …). That firmware cannot be redistributed, which is why the boot images are always
packed locally. Offline alternative with a stock firmware download:
`scripts/pull-templates.sh r0s --from-ap AP_S901B....tar.md5`.

## 4. Build

### Option 1: GitHub Actions (recommended, your laptop disk stays free)

Push this folder to a GitHub repo, run **Actions → Build kernel + ubuntu.img → Run workflow**
(both devices, about 2 h). Download the `s22-ut-r0s` artifact, then:

```bash
scripts/import-ci.sh r0s ~/Downloads/s22-ut-r0s
./build.sh r0s images pack
```

### Option 2: local (Docker, ~25 GB free disk per device)

```bash
./build-docker.sh r0s kernel           # 30–90 min (ThinLTO)
./build-docker.sh r0s images rootfs pack
```

Without Docker, install on the host: `bc bison flex libelf-dev libssl-dev lz4 cpio fakeroot
e2fsprogs zstd kmod clang lld llvm python3 git curl`, then use `./build.sh` the same way.

| Variable | Effect |
|---|---|
| `USE_SYSTEM_CLANG=1` | use host clang/lld (Docker image: clang 18) instead of AOSP clang `r510928` |
| `JOBS=n` | parallel compile jobs |
| `MENUCONFIG=1` | open menuconfig after the config merge |

The result is the flash kit in `work/out/<dev>/`: `boot.img vendor_boot.img dtbo.img
vbmeta-disabled.img ubuntu.img flash.sh deviceinfo.conf SHA256SUMS build-info.txt`.

## 5. Flash

Phone in LineageOS recovery with ADB enabled:

```bash
cd work/out/r0s
./flash.sh              # Path A (LineageOS installed)
./flash.sh --vbmeta     # Path B (stock firmware + LineageOS recovery)
```

`flash.sh` checks the codename, **backs up** boot/vendor_boot/dtbo to `backup-<dev>-<date>/`,
formats `/data` as ext4, copies `ubuntu.img`, writes the boot images with `dd` and reboots.
Samsung has no fastboot, so everything goes through the root adb shell of the recovery.

| Command | Use |
|---|---|
| `./flash.sh --boot-only` | new kernel/boot images only, keeps `/data` (kernel iteration) |
| `./flash.sh --rootfs-only` | new `ubuntu.img` only |
| `./flash.sh --restore backup-…` | put the backed-up boot images back (LineageOS boots again) |

## 6. First boot and debugging

The first boot can take several minutes. If it hangs or loops:

- **Force restart:** hold **Vol Down + Power** ~7 s. **Recovery:** right after, hold **Power + Vol Up**
  (with USB connected).
- **Kernel log of the failed boot** (in recovery):
  `adb shell cat /proc/last_kmsg` (Samsung) or `adb shell cat /sys/fs/pstore/console-ramoops*`.
  Look for lines starting with `initrd:` (Halium initramfs) and module/firmware errors.
- **Initramfs panic:** the Halium initramfs offers a USB network shell: `telnet 192.168.2.15`.
- **Booted but no UI:** USB networking + `ssh phablet@10.15.19.82`, then
  `sudo journalctl -b`, `dmesg`, `/var/log/lxc/android.log`, `lxc-attach -n android -- logcat`.
- Back to Android at any time: `./flash.sh --restore backup-<dev>-<date>`.

Kernel loop: `./build-docker.sh r0s kernel images pack && cd work/out/r0s && ./flash.sh --boot-only`.

## Known gaps

Things that are likely to need work after the first boot, roughly in order:

1. **Display / GPU:** Xclipse 920 (`sgpu`) blobs through libhybris on Halium 16. The Pixel 6a
   port needed libhybris from the 26.04 archive for Android 16; if Lomiri doesn't start, that is
   the first thing to try. `GridUnit` in `deviceinfo/<dev>.conf` is a guess.
2. **Wi-Fi:** S22 loads `wlan` (QCA6490, firmware from `/vendor/firmware`), Ultra loads `dhd`
   with the path overrides in `/etc/modprobe.d/bcmdhd.conf` and `/etc/wifi/*` symlinks.
3. **Telephony:** Exynos/Shannon modem with Samsung's radio HAL. Start with
   `ofono-binder-plugin` as on the vayu kit; SMS/calls are not expected to work out of the box.
4. **Audio:** Cirrus CS35L41 amps via the Samsung audio HAL (`pulseaudio-modules-droid`).
5. **Camera, fingerprint, NFC, UWB, S Pen (Ultra):** not looked at yet.
6. **OTA:** no UBports system-image channel exists for these devices; update by reflashing.

## Layout

```
build.sh                    stages: kernel | images | rootfs | pack
build-docker.sh             same, inside Ubuntu 24.04 container
flash.sh                    installer (copied into each flash kit)
deviceinfo/r0s.conf b0s.conf  per-device settings
kernel/halium-samsung.config  kernel config fragment (verified by scripts/check-config.sh)
modules/<dev>.load          first-stage module list (from LineageOS)
dts/*.cfg                   dtb/dtbo tables (from LineageOS)
overlay/common, overlay/<dev>  extra files for the rootfs (optional)
scripts/                    build-kernel, make-boot-images, make-rootfs, pull-templates, import-ci
.github/workflows/build.yml CI build of kernel + ubuntu.img
templates/<dev>/            from your phone (git-ignored, contains your backup)
work/                       build output (git-ignored)
```

## Credits

LineageOS (s5e9925 kernel and device trees), UBports and Halium (rootfs, Halium GSI,
initramfs, porting tools), and the Pixel 6a port by logicalangel as reference for GKI + Halium 16.

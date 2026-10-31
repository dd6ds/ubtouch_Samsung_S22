# Ubuntu Touch 24.04 für Galaxy S22 / S22 Ultra (Exynos)

Build- und Flash-Kit für **Ubuntu Touch 24.04-2.x auf Halium 16** für

| Gerät | Modell | Codename | WLAN |
|---|---|---|---|
| Galaxy S22 | SM-S901B, SM-S901B/DS | `r0s` | Qualcomm QCA6490 (`wlan`) |
| Galaxy S22 Ultra | SM-S908B, SM-S908B/DS | `b0s` | Broadcom BCM4389 (`dhd`) |

Beide nutzen den Exynos 2200 (`s5e9925`) und einen gemeinsamen Kernel.
**Snapdragon-Modelle aus USA/Kanada (S901U/U1/W, S908U/U1/W) gehen nicht**: deren Bootloader lässt sich nicht entsperren.

> **Status: experimenteller Bring-up.** Es gibt keinen offiziellen oder Community-Port von
> Ubuntu Touch für diese Geräte. Das Kit baut einen ersten Port aus dem Kernel von LineageOS 23.2
> und den generischen Halium-Bausteinen von UBports. Die ersten Images brauchen sehr
> wahrscheinlich Debugging am Gerät. Siehe [Bekannte Lücken](#bekannte-lücken).

## Aufbau

```
 boot.img         LineageOS-s5e9925-Kernel (5.10 GKI) + Halium-Config  +  Halium-"dynparts"-Initramfs
 vendor_boot.img  First-Stage-Module (modules/<dev>.load) + GPU-/Touch-Firmware + dtb + cmdline
 dtbo.img         Overlays je Platinen-Revision (dts/<dev>.cfg)
 /data/ubuntu.img UT-24.04-2.x-Rootfs + Halium-16-GSI (LXC) + alle Kernel-Module + Geräte-Layer
 super            bleibt unangetastet: eigenes vendor / vendor_dlkm (Android 16, One UI 8 oder LineageOS 23.2)
```

Das Halium-Initramfs lädt die Module aus vendor_boot, bildet die `super`-Unterpartitionen ab,
mountet `/data`, hängt `ubuntu.img` per Loop ein und startet Ubuntu Touch; die Android-HALs
laufen im LXC-Container. Gleiches Prinzip wie der [Pixel-6a-Port](https://github.com/logicalangel/ubuntu-touch-bluejay).

Warum ein eigener Kernel: Dem Stock-/LineageOS-Kernel fehlt, was Ubuntu braucht (`SYSVIPC`,
`DEVTMPFS`, `VT`, `FHANDLE`, `USER_NS`, … siehe `kernel/halium-samsung.config`). Das ändert die
Modul-ABI, deshalb kommen **alle** Module aus unserem Build: die First-Stage-Module in
vendor_boot, die aus `/vendor_dlkm` (WLAN, Fingerabdruck) per `/etc/modules-load.d` im Rootfs.

## Vorher unbedingt lesen

- **Entsperren löst Knox dauerhaft aus** (Samsung Pay/Wallet, Sicherer Ordner, Samsung Pass sind
  für immer weg, auch nach erneutem Sperren) und **löscht das Gerät**.
- Vorher auf die **neueste Stock-Firmware (One UI 8 / Android 16)** aktualisieren. Halium 16 muss
  zur Android-Version der vendor-Partition passen. Wegen Samsungs Anti-Rollback ist ein späteres
  Downgrade nicht möglich.
- Akku > 60 %, USB-C-Datenkabel.
- Bis auf die einmalige Recovery-Installation läuft alles unter Linux mit `adb`.

## 1. Bootloader entsperren

1. Einstellungen → Telefoninfo → Softwareinformationen → 7× auf *Buildnummer* →
   Entwickleroptionen → **OEM-Entsperrung** an. (Fehlt der Schalter: online gehen und warten,
   bei neuen/aufbereiteten Geräten kann das Tage dauern.)
2. Ausschalten. **Lauter + Leiser** halten und USB einstecken → Download-Modus-Warnung →
   **Lauter lange drücken** → Entsperren bestätigen. Das Gerät wird gelöscht; Einrichtung
   überspringen, Entwickleroptionen wieder aktivieren und prüfen, dass *OEM-Entsperrung* an ist
   (ausgegraut = entsperrt).

## 2. LineageOS-Recovery installieren (am besten gleich LineageOS 23.2)

Offizielle Anleitung je Gerät: [S22 r0s](https://wiki.lineageos.org/devices/r0s/install/),
[S22 Ultra b0s](https://wiki.lineageos.org/devices/b0s/install/). Dabei werden `recovery.img`
und `vbmeta.img` im Download-Modus mit Odin (Windows) oder `odin4` / Heimdall (Linux) geflasht.

- **Weg A, empfohlen:** LineageOS 23.2 komplett installieren und einmal booten. Dann ist klar,
  dass Hardware und vendor zusammenpassen, und der Kernel hier stammt aus derselben Quelle.
- **Weg B:** auf Stock One UI 8 bleiben und nur LineageOS-Recovery + dessen vbmeta flashen.
  Dann in Schritt 5 `flash.sh --vbmeta` verwenden.

## 3. Vorlagen + Backup vom Gerät holen

In die Recovery booten (Gerät aus, USB verbunden, **Power + Lauter** halten),
*Advanced → Enable ADB* wählen, dann am PC:

```bash
scripts/pull-templates.sh r0s        # oder b0s
```

Das sichert `boot`, `vendor_boot`, `dtbo`, `recovery`, `vbmeta` des Geräts (**das ist dein
Backup, gut aufheben**), übernimmt die exakten Boot-Header-Werte (Patch-Level, Offsets,
cmdline, bootconfig) und extrahiert die First-Stage-Firmware aus vendor_boot (Xclipse-GPU
`sgpu`, Touchscreen, …). Diese Firmware darf nicht weiterverteilt werden, deshalb werden die
Boot-Images immer lokal gepackt. Offline-Alternative mit einer Stock-Firmware:
`scripts/pull-templates.sh r0s --from-ap AP_S901B....tar.md5`.

## 4. Bauen

### Variante 1: GitHub Actions (empfohlen, spart Platz auf dem Laptop)

Ordner in ein GitHub-Repo pushen, **Actions → Build kernel + ubuntu.img → Run workflow**
(beide Geräte, ca. 2 h). Artefakt `s22-ut-r0s` herunterladen, dann:

```bash
scripts/import-ci.sh r0s ~/Downloads/s22-ut-r0s
./build.sh r0s images pack
```

### Variante 2: lokal (Docker, ca. 25 GB frei pro Gerät)

```bash
./build-docker.sh r0s kernel           # 30–90 min (ThinLTO)
./build-docker.sh r0s images rootfs pack
```

Ohne Docker auf dem Host installieren: `bc bison flex libelf-dev libssl-dev lz4 cpio fakeroot
e2fsprogs zstd kmod clang lld llvm python3 git curl`, dann `./build.sh` genauso verwenden.

| Variable | Wirkung |
|---|---|
| `USE_SYSTEM_CLANG=1` | Host-clang/lld (Docker-Image: clang 18) statt AOSP-clang `r510928` |
| `JOBS=n` | parallele Compile-Jobs |
| `MENUCONFIG=1` | menuconfig nach dem Config-Merge öffnen |

Ergebnis ist das Flash-Kit in `work/out/<dev>/`: `boot.img vendor_boot.img dtbo.img
vbmeta-disabled.img ubuntu.img flash.sh deviceinfo.conf SHA256SUMS build-info.txt`.

## 5. Flashen

Gerät in der LineageOS-Recovery mit aktiviertem ADB:

```bash
cd work/out/r0s
./flash.sh              # Weg A (LineageOS installiert)
./flash.sh --vbmeta     # Weg B (Stock-Firmware + LineageOS-Recovery)
```

`flash.sh` prüft den Codenamen, **sichert** boot/vendor_boot/dtbo nach `backup-<dev>-<datum>/`,
formatiert `/data` als ext4, kopiert `ubuntu.img`, schreibt die Boot-Images per `dd` und startet
neu. Samsung hat kein Fastboot, daher läuft alles über die Root-adb-Shell der Recovery.

| Befehl | Zweck |
|---|---|
| `./flash.sh --boot-only` | nur neuer Kernel/Boot-Images, `/data` bleibt (Kernel-Iteration) |
| `./flash.sh --rootfs-only` | nur neues `ubuntu.img` |
| `./flash.sh --restore backup-…` | gesicherte Boot-Images zurückschreiben (LineageOS bootet wieder) |

## 6. Erster Start und Fehlersuche

Der erste Start kann einige Minuten dauern. Wenn er hängt oder in einer Schleife läuft:

- **Neustart erzwingen:** **Leiser + Power** ca. 7 s halten. **Recovery:** direkt danach
  **Power + Lauter** halten (USB verbunden).
- **Kernel-Log des fehlgeschlagenen Starts** (in der Recovery):
  `adb shell cat /proc/last_kmsg` (Samsung) oder `adb shell cat /sys/fs/pstore/console-ramoops*`.
  Auf Zeilen mit `initrd:` (Halium-Initramfs) sowie Modul-/Firmware-Fehler achten.
- **Initramfs-Panic:** das Halium-Initramfs bietet eine USB-Netzwerk-Shell: `telnet 192.168.2.15`.
- **Bootet, aber keine Oberfläche:** USB-Netzwerk + `ssh phablet@10.15.19.82`, dann
  `sudo journalctl -b`, `dmesg`, `/var/log/lxc/android.log`, `lxc-attach -n android -- logcat`.
- Jederzeit zurück zu Android: `./flash.sh --restore backup-<dev>-<datum>`.

Kernel-Schleife: `./build-docker.sh r0s kernel images pack && cd work/out/r0s && ./flash.sh --boot-only`.

## Bekannte Lücken

Was nach dem ersten Start voraussichtlich Arbeit braucht, grob nach Reihenfolge:

1. **Display / GPU:** Xclipse-920-Blobs (`sgpu`) über libhybris auf Halium 16. Der Pixel-6a-Port
   brauchte für Android 16 libhybris aus dem 26.04-Archiv; startet Lomiri nicht, ist das der
   erste Ansatzpunkt. `GridUnit` in `deviceinfo/<dev>.conf` ist geschätzt.
2. **WLAN:** S22 lädt `wlan` (QCA6490, Firmware aus `/vendor/firmware`), Ultra lädt `dhd` mit
   den Pfad-Overrides in `/etc/modprobe.d/bcmdhd.conf` und den Symlinks in `/etc/wifi/`.
3. **Telefonie:** Exynos-/Shannon-Modem mit Samsungs Radio-HAL. Ansatz wie beim vayu-Kit
   (`ofono-binder-plugin`); SMS/Anrufe werden anfangs eher nicht funktionieren.
4. **Audio:** Cirrus-CS35L41-Verstärker über Samsungs Audio-HAL (`pulseaudio-modules-droid`).
5. **Kamera, Fingerabdruck, NFC, UWB, S Pen (Ultra):** noch nicht angeschaut.
6. **OTA:** Es gibt keinen UBports-System-Image-Kanal für diese Geräte; Updates per Neu-Flashen.

## Dateien

```
build.sh                    Stufen: kernel | images | rootfs | pack
build-docker.sh             dasselbe im Ubuntu-24.04-Container
flash.sh                    Installer (wird in jedes Flash-Kit kopiert)
deviceinfo/r0s.conf b0s.conf  Geräte-Einstellungen
kernel/halium-samsung.config  Kernel-Config-Fragment (geprüft von scripts/check-config.sh)
modules/<dev>.load          First-Stage-Modulliste (von LineageOS)
dts/*.cfg                   dtb/dtbo-Tabellen (von LineageOS)
overlay/common, overlay/<dev>  zusätzliche Dateien fürs Rootfs (optional)
scripts/                    build-kernel, make-boot-images, make-rootfs, pull-templates, import-ci
.github/workflows/build.yml CI-Build von Kernel + ubuntu.img
templates/<dev>/            vom eigenen Gerät (git-ignoriert, enthält dein Backup)
work/                       Build-Ausgabe (git-ignoriert)
```

## Danksagung

LineageOS (s5e9925-Kernel und Device-Trees), UBports und Halium (Rootfs, Halium-GSI, Initramfs,
Porting-Werkzeuge) sowie der Pixel-6a-Port von logicalangel als Referenz für GKI + Halium 16.

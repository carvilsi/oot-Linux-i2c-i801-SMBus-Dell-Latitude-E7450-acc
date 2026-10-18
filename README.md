# ACCELEROMETER PATCH

Out-of-tree build of the Linux `i2c-i801` SMBus driver with a quirk for the
**Dell Latitude E7450**. It enables the on-board ST **lis3lv02d** accelerometer.

## The problem

The E7450 BIOS says the SMBus controller uses IRQ 18, but IRQ 18 belongs to
the accelerometer's freefall line (ACPI `SMO8810`, edge triggered). The kernel
can't route the SMBus PCI interrupt (level triggered) to that same pin, so the
stock driver fails on every boot:

```
i801_smbus 0000:00:1f.3: PCI INT C: failed to register GSI
i801_smbus 0000:00:1f.3: Failed to enable SMBus PCI device (-16)
i801_smbus 0000:00:1f.3: probe with driver i801_smbus failed with error -16
dell_lis3lv02d: accelerometer is present on SMBus but its address is unknown, skipping registration
```

There is no SMBus, so the accelerometer at I²C address `0x29` is unreachable.
Unloading `dell_smo8800` does not help: the IRQ is claimed during ACPI
enumeration, before any driver loads.

## The fix

`i2c-i801-e7450-noirq.patch` adds a DMI quirk. On a `Dell Inc.` /
`Latitude E7450` it sets the SMBus IRQ to `IRQ_NOTCONNECTED` before
`pci_enable_device()`. The device then enables fine and the driver falls back
to polling (`SMBus using polling` in dmesg), which is reportedly what the
Windows driver does.

It is patch 1/2 of Marius Hoch's 2023 series, rebased on the current
`i801_probe()`. The series was never merged (still absent in v7.2.10), so it
must be rebuilt for every kernel.

## Files

| File | What |
|------|------|
| `i2c-i801-e7450-noirq.patch` | the quirk, applied with `patch -p4` |
| `build.sh` | fetches upstream `i2c-i801.c` for a kernel, patches it, builds it |
| `Makefile` | kbuild out-of-tree makefile (`KVER`, `KDIR` overridable) |
| `99-lis3lv02d-e7450.rules` | udev rule that instantiates `lis3lv02d` at `0x29` on the SMBus |
| `LICENSE` | GPL-2.0 text (the repo is GPL-2.0-or-later) |

## Requirements

- `linux-headers` matching the target kernel (`/lib/modules/<kver>/build`)
- `base-devel` (`make`, `gcc`), `patch`, `curl`
- network access to `git.kernel.org`

## First install

```sh
sudo install -Dm644 99-lis3lv02d-e7450.rules /etc/udev/rules.d/99-lis3lv02d-e7450.rules
```

Then follow the next section.

## Run after kernel update

The built module only works for the kernel it was built against. After
`pacman -Syu` updates `linux`, the new kernel loads its stock `i2c-i801`
again.

Already rebooted into the new kernel:

```sh
./build.sh
sudo install -Dm644 i2c-i801.ko /lib/modules/$(uname -r)/updates/i2c-i801.ko
sudo depmod -a
sudo modprobe -r i2c_i801; sudo modprobe i2c_i801
```

Before rebooting (so the new kernel boots already patched), pass the new
kernel release explicitly:

```sh
KVER=$(ls /lib/modules | grep arch | sort -V | tail -1)   # e.g. 7.2.11-arch1-1
./build.sh "$KVER"
sudo install -Dm644 i2c-i801.ko /lib/modules/$KVER/updates/i2c-i801.ko
sudo depmod -a "$KVER"
```

The module goes to `updates/`, which `depmod` prefers over
`kernel/drivers/...`. The stock `.ko.zst` from the package is never touched,
and pacman doesn't own `updates/`.

## Check it works

```sh
modinfo -n i2c_i801                     # .../updates/i2c-i801.ko
sudo dmesg | grep -iE 'i801|lis3'       # "SMBus using polling", "8 bits 3DC sensor found"
cat /sys/devices/faux/lis3lv02d/position   # (x,y,z) in mg, ~1000 on Z when flat
grep -A4 'LIS3LV02DL' /proc/bus/input/devices
```

A `Failed to register i2c client lis3lv02d at 0x29 (-16)` line is harmless.
It means both the udev rule and `dell_lis3lv02d probe_i2c_addr=1` tried to
register the same device.

## Uninstall

```sh
sudo rm /lib/modules/$(uname -r)/updates/i2c-i801.ko
sudo rm /etc/udev/rules.d/99-lis3lv02d-e7450.rules
sudo depmod -a
```

## Troubleshooting

- **`build.sh` fails at "applying patch"**: upstream changed `i801_probe()`.
  Regenerate the patch against the new source. The quirk block must run
  before `pci_enable_device(dev)`.
- **`curl` 404**: the kernel version has no upstream tag (e.g. an `-rc` or a
  vendor kernel). Pass a matching upstream source manually.
- **Other kernels (`linux-lts`, `linux-zen`)**: they work if their headers are
  installed and their `i2c-i801.c` matches upstream stable; build with
  `./build.sh <their kver>`.

## Sources

- Original patch series, "i2c: i801: Force no IRQ for Dell Latitude E7450" (Marius Hoch, May 2023):
  - [cover letter, LKML](https://lkml.iu.edu/hypermail/linux/kernel/2306.0/03563.html)
  - [patch 1/2 on patchwork](https://patchwork-proxy.ozlabs.org/project/linux-i2c/patch/20230514103634.235917-2-mail@mariushoch.de/)
  - [patch 2/2 (further Dell Latitudes) on Linaro patches](https://patches.linaro.org/patch/681896)
- Review discussion:
  - [Jean Delvare's review, May 2023](https://lkml.rescloud.iu.edu/2305.2/09517.html)
  - [discussion on patch 1/2](https://lkml.rescloud.iu.edu/2306.0/03588.html)
  - [discussion, June 2023](https://lkml.rescloud.iu.edu/2306.2/03135.html)
  - [maintainer status ping (no reply), Oct 2023](https://lkml.iu.edu/2310.3/05992.html)
- [Kernel bugzilla 194141](https://bugzilla.kernel.org/show_bug.cgi?id=194141): same `i801_smbus` failure on Dell machines
- [i2c: i801: Register optional lis3lv02d i2c device on Dell machines](https://lkml.iu.edu/hypermail/linux/kernel/1701.0/01706.html): the origin of the `0x29` address
- Upstream driver: [`drivers/i2c/busses/i2c-i801.c` (stable tree)](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/drivers/i2c/busses/i2c-i801.c)
- Kernel docs: [lis3lv02d](https://docs.kernel.org/misc-devices/lis3lv02d.html), [i2c-i801](https://docs.kernel.org/i2c/busses/i2c-i801.html)

## License

[GPL-2.0-or-later](LICENSE), the same license as the upstream
`drivers/i2c/busses/i2c-i801.c` that the patch modifies.

The quirk in `i2c-i801-e7450-noirq.patch` is based on Marius Hoch's 2023
patch (see [Sources](#sources)).

---

## ⚠️ Disclaimer

This works on my computer: a Dell Latitude E7450 (BIOS A13) running Arch Linux.
It replaces a kernel driver and talks to hardware directly over SMBus. If you
do not know what you are doing, do not execute or run the content of this
repo. Use it at your own risk; there is no warranty of any kind.

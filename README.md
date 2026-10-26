# c5-usb-serial-modules

usb-serial kernel modules for the FlashForge Creator 5 / Creator 5 Pro on
FlashForge firmware 2.0.0 (kernel package 2.0.8).

Earlier kernels (2.0.7, firmware 1.9.9) build usb-serial into the kernel. The
2.0.8 kernel leaves out usb-serial, `cdc_acm` and the EHCI/OHCI host
drivers, so the OpenCreator tunnel can't bind its USB gadget to
`/dev/ttyUSB*`. Loading these modules puts usb-serial back without changing
the kernel or the read-only root filesystem.

| Module | Purpose |
|---|---|
| `usbserial.ko` | usb-serial core and its generic driver |
| `usb-serial-simple.ko` | `flashloader` and the other one-port bulk drivers the tunnel binds the gadget to; needs `usbserial.ko` |
| `ch341.ko`, `cdc-acm.ko` | not used by the tunnel; built for other USB serial adapters |

Load order: `insmod usbserial.ko`, then `insmod usb-serial-simple.ko`.
`opencreator-tunnel/printer-socat/c5_socat.py` does this itself when the
running kernel has no usb-serial.

## Why these load on a stock kernel

The 2.0.8 kernel checks only a module's vermagic: the X2600 kernel has
`MODVERSIONS` and `MODULE_SIG` off, and FlashForge's own `.ko` files have
neither symbol CRCs nor signatures. The build reproduces the stock vermagic,
`5.10.186+ SMP preempt mod_unload MIPS32_R5 32BIT`, from the same kernel
source FlashForge used:

- Ingenic SDK `ingenic-linux-kernel4.4.94-kernel5.10-x2600-v2.0-20230906`,
  `kernel/kernel-5.10` (Linux 5.10.186). The SDK archive's MD5 is
  `7c040a22c6a1978385d3f644d9d9a7b7`.
- Toolchain `mips-xburst2-linux-toolchain-r6.0.0` (GCC 12.1). Stock was built
  with R6.0.1, the same GCC.
- `x2600_module_base_linux_mmc0_defconfig` plus
  [`config/usb-serial.fragment`](config/usb-serial.fragment): `HIGHMEM`
  (stock exports `kmap_high`), `LOCALVERSION="+"`, and the four drivers as
  modules.

Checked against the decompressed 2.0.8 kernel image: every symbol the
modules import is in its export table. Of the 111 imported functions located
in it, all match this build's code, including every struct field offset.
Verified on a printer running 2.0.0: both modules load, `flashloader` binds
the gadget, and Klipper on the SBC reaches all four MCUs through
`/dev/ttyUSB*`.

## Building

On Linux (WSL2 works), with the SDK and toolchain unpacked:

```sh
./build.sh /path/to/ingenic-linux-kernel4.4.94-kernel5.10-x2600-v2.0-20230906/kernel/kernel-5.10 \
           /path/to/mips-xburst2-linux-toolchain-r6.0.0
```

The script configures and builds into `out/` and stops if a fragment option
is dropped or a module's vermagic differs from stock. It writes `dist/`: the
four modules, `SHA256SUMS`, and the `kernel.config` used. Building `vmlinux`
as well takes a couple of minutes, and lets modpost check the modules'
imports.

Ingenic's release note links the SDK (Baidu pan) at
<https://www.ingenic.com.cn/news-detail/nid-342.html>.

## License

The modules are built from unmodified Linux kernel source and are GPL-2.0,
as is this repository ([LICENSE](LICENSE)).

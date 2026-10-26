#!/bin/bash
# Build usb-serial kernel modules for the FlashForge Creator 5 kernel 2.0.8
# (firmware 2.0.0), which ships without usb-serial. See README.md.
#
#   ./build.sh KERNEL_SRC TOOLCHAIN_DIR
#
# KERNEL_SRC     kernel/kernel-5.10 from Ingenic's
#                ingenic-linux-kernel4.4.94-kernel5.10-x2600-v2.0-20230906 SDK
# TOOLCHAIN_DIR  mips-xburst2-linux-toolchain-r6.0.0 (contains bin/)
#
# Output: dist/*.ko, dist/SHA256SUMS, dist/kernel.config
set -euo pipefail

KSRC=$(realpath "${1:?kernel source dir}")
TC=$(realpath "${2:?toolchain dir}")
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out
DIST=$HERE/dist
DEFCONFIG=${DEFCONFIG:-x2600_module_base_linux_mmc0_defconfig}
VERMAGIC="5.10.186+ SMP preempt mod_unload MIPS32_R5 32BIT "
MODULES="drivers/usb/serial/usbserial.ko drivers/usb/serial/usb-serial-simple.ko
drivers/usb/serial/ch341.ko drivers/usb/class/cdc-acm.ko"

die() { echo "build: $*" >&2; exit 1; }

grep -q '^SUBLEVEL = 186$' "$KSRC/Makefile" || die "$KSRC is not Linux 5.10.186"
[ -f "$KSRC/arch/mips/configs/$DEFCONFIG" ] || die "no $DEFCONFIG in $KSRC"
[ -x "$TC/bin/mips-xburst2-linux-gnu-gcc" ] || die "no mips-xburst2-linux-gnu-gcc in $TC/bin"

export PATH=$TC/bin:$PATH ARCH=mips CROSS_COMPILE=mips-xburst2-linux-gnu-
mkdir -p "$OUT"
make -C "$KSRC" O="$OUT" "$DEFCONFIG" >/dev/null
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" \
    "$HERE/config/usb-serial.fragment" >/dev/null
make -C "$KSRC" O="$OUT" olddefconfig >/dev/null

# olddefconfig silently drops options whose dependencies are unmet.
while IFS= read -r line; do
    case $line in CONFIG_*) grep -qxF "$line" "$OUT/.config" || die "config lost: $line" ;; esac
done < "$HERE/config/usb-serial.fragment"

# vmlinux too, so modpost checks the modules' imports against it.
make -C "$KSRC" O="$OUT" -j"$(nproc)" vmlinux modules

rm -rf "$DIST"
mkdir -p "$DIST"
for m in $MODULES; do
    "${CROSS_COMPILE}objcopy" -O binary -j .modinfo "$OUT/$m" "$OUT/modinfo.bin"
    got=$(tr '\0' '\n' < "$OUT/modinfo.bin" | sed -n 's/^vermagic=//p')
    [ "$got" = "$VERMAGIC" ] || die "$m vermagic '$got', want '$VERMAGIC'"
    cp "$OUT/$m" "$DIST/"
done
cp "$OUT/.config" "$DIST/kernel.config"
(cd "$DIST" && sha256sum ./*.ko | sed 's# \./# #' > SHA256SUMS)
cat "$DIST/SHA256SUMS"

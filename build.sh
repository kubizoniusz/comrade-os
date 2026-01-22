#!/bin/bash
set -e

WORK="/tmp/comrade-build"
ISO_OUT="ComradeOS-1.0.iso"

# Funkcja sprzątająca
cleanup() {
    echo "Czyszczenie..."
    umount "$WORK/rootfs/dev/pts" 2>/dev/null || true
    umount "$WORK/rootfs/dev/shm" 2>/dev/null || true
    umount "$WORK/rootfs/dev" 2>/dev/null || true
    umount "$WORK/rootfs/sys" 2>/dev/null || true
    umount "$WORK/rootfs/proc" 2>/dev/null || true
    # Usuwamy blokady i fałszywki
    rm -f "$WORK/rootfs/usr/sbin/policy-rc.d" 2>/dev/null || true
    rm -f "$WORK/rootfs/usr/sbin/update-grub" 2>/dev/null || true
}
trap cleanup EXIT

echo "★ COMRADE OS BUILDER (BYPASS METHOD) ★"

echo "[1/8] Instalacja pakietów hosta..."
apk update
apk add wget xorriso squashfs-tools grub grub-bios mtools debootstrap

echo "[2/8] Przygotowanie katalogów..."
umount "$WORK/rootfs/proc" 2>/dev/null || true
rm -rf "$WORK"
mkdir -p "$WORK"/{rootfs,staging/live,staging/boot/grub}

echo "[3/8] Pobieranie systemu..."
debootstrap --variant=minbase --arch=amd64 --include=python3,systemd,udev,nano bookworm "$WORK/rootfs" http://deb.debian.org/debian

echo "[4/8] Skrypty Comrade OS..."
if [ -f comrade_os.py ]; then
    cp comrade_os.py "$WORK/rootfs/usr/bin/comrade_os.py"
else
    echo "print('System ComradeOS OK')" > "$WORK/rootfs/usr/bin/comrade_os.py"
fi
chmod +x "$WORK/rootfs/usr/bin/comrade_os.py"

cat << 'STARTSCRIPT' > "$WORK/rootfs/usr/bin/comrade-shell"
#!/bin/bash
clear
echo "Startowanie Comrade OS..."
sleep 1
exec /usr/bin/python3 /usr/bin/comrade_os.py
STARTSCRIPT
chmod +x "$WORK/rootfs/usr/bin/comrade-shell"

# Autologin setup
mkdir -p "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d"
printf "[Service]\nExecStart=\nExecStart=-/usr/bin/comrade-shell\nStandardInput=tty\nStandardOutput=tty\n" > "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d/override.conf"
echo "comrade-os" > "$WORK/rootfs/etc/hostname"

echo "[5/8] Montowanie zasobów..."
mount --bind /proc "$WORK/rootfs/proc"
mount --bind /sys "$WORK/rootfs/sys"
mount --bind /dev "$WORK/rootfs/dev"
mount --bind /dev/pts "$WORK/rootfs/dev/pts"
[ -d /dev/shm ] && mount --bind /dev/shm "$WORK/rootfs/dev/shm"

# FIX 1: Blokada usług
printf "#!/bin/sh\nexit 101\n" > "$WORK/rootfs/usr/sbin/policy-rc.d"
chmod +x "$WORK/rootfs/usr/sbin/policy-rc.d"

echo "[6/8] INSTALACJA KERNELA (METODA OSZUSTWA)..."

# FIX 2: Oszukujemy instalator, że update-grub działa
# Jeśli tego nie zrobimy, dpkg wywali błąd 1
mv "$WORK/rootfs/usr/sbin/update-grub" "$WORK/rootfs/usr/sbin/update-grub.bak" 2>/dev/null || true
ln -s /bin/true "$WORK/rootfs/usr/sbin/update-grub"

# Instalacja podstaw (bez kernela)
chroot "$WORK/rootfs" apt-get update
DEBIAN_FRONTEND=noninteractive chroot "$WORK/rootfs" apt-get install -y --no-install-recommends \
    initramfs-tools live-boot systemd-sysv

# Instalacja kernela (teraz update-grub zwróci "true" i dpkg nie zgłupieje)
echo ">>> Instalowanie linux-image..."
DEBIAN_FRONTEND=noninteractive chroot "$WORK/rootfs" apt-get install -y --no-install-recommends linux-image-amd64

# Przywracanie prawdziwego update-grub (jeśli istniał)
rm "$WORK/rootfs/usr/sbin/update-grub"
if [ -f "$WORK/rootfs/usr/sbin/update-grub.bak" ]; then
    mv "$WORK/rootfs/usr/sbin/update-grub.bak" "$WORK/rootfs/usr/sbin/update-grub"
fi

echo "[7/8] Ręczne generowanie Initrd..."
# Ponieważ oszukaliśmy system przy instalacji, teraz musimy wymusić utworzenie pliku initrd
KERNEL_VER=$(ls "$WORK/rootfs/lib/modules" | sort -V | tail -n 1)
echo "Wykryta wersja kernela: $KERNEL_VER"

if [ -z "$KERNEL_VER" ]; then
    echo "BŁĄD: Nie znaleziono modułów kernela!"
    exit 1
fi

chroot "$WORK/rootfs" update-initramfs -c -k "$KERNEL_VER"

# Sprzątanie blokady usług
rm "$WORK/rootfs/usr/sbin/policy-rc.d"
cleanup

echo "[8/8] Pakowanie ISO..."
# Kopiowanie vmlinuz i initrd
cp "$WORK/rootfs/boot/vmlinuz-$KERNEL_VER" "$WORK/staging/live/vmlinuz"
cp "$WORK/rootfs/boot/initrd.img-$KERNEL_VER" "$WORK/staging/live/initrd"

mksquashfs "$WORK/rootfs" "$WORK/staging/live/filesystem.squashfs" -comp xz -no-recovery

cat << 'GRUBCFG' > "$WORK/staging/boot/grub/grub.cfg"
set default=0
set timeout=3
menuentry "ComradeOS 1.0" {
    linux /live/vmlinuz boot=live quiet
    initrd /live/initrd
}
GRUBCFG

grub-mkrescue -o "$ISO_OUT" "$WORK/staging"

echo ""
echo "★★★ SUKCES! ★★★"
echo "Plik gotowy: $ISO_OUT"

#!/bin/bash
set -e

WORK="/tmp/comrade-build"
ISO_OUT="ComradeOS-1.0.iso"

# Funkcja czyszcząca w razie błędu
cleanup() {
    echo "Czyszczenie montowania..."
    umount "$WORK/rootfs/dev/pts" 2>/dev/null || true
    umount "$WORK/rootfs/dev/shm" 2>/dev/null || true
    umount "$WORK/rootfs/dev" 2>/dev/null || true
    umount "$WORK/rootfs/sys" 2>/dev/null || true
    umount "$WORK/rootfs/proc" 2>/dev/null || true
    rm -f "$WORK/rootfs/usr/sbin/policy-rc.d" 2>/dev/null || true
}
trap cleanup EXIT

echo "★ COMRADE OS BUILDER (FINAL FIX) ★"

echo "[1/8] Instalacja pakietów hosta..."
apk update
apk add wget xorriso squashfs-tools grub grub-bios mtools debootstrap

echo "[2/8] Przygotowanie katalogów..."
umount "$WORK/rootfs/proc" 2>/dev/null || true
rm -rf "$WORK"
mkdir -p "$WORK"/{rootfs,staging/live,staging/boot/grub}

echo "[3/8] Pobieranie Debian minimal..."
debootstrap --variant=minbase --arch=amd64 --include=python3,systemd,udev,nano,locales bookworm "$WORK/rootfs" http://deb.debian.org/debian

echo "[4/8] Instalacja skryptów Comrade OS..."
# Tworzenie atrapy pliku python jeśli nie masz go pod ręką
if [ -f comrade_os.py ]; then
    cp comrade_os.py "$WORK/rootfs/usr/bin/comrade_os.py"
else
    echo "print('System ComradeOS uruchomiony pomyślnie.')" > "$WORK/rootfs/usr/bin/comrade_os.py"
fi
chmod +x "$WORK/rootfs/usr/bin/comrade_os.py"

cat << 'STARTSCRIPT' > "$WORK/rootfs/usr/bin/comrade-shell"
#!/bin/bash
clear
echo "★ Uruchamianie Comrade OS... ★"
sleep 1
exec /usr/bin/python3 /usr/bin/comrade_os.py
STARTSCRIPT
chmod +x "$WORK/rootfs/usr/bin/comrade-shell"

echo "[5/8] Konfiguracja autologowania..."
mkdir -p "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d"
cat << 'AUTOLOGIN' > "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d/override.conf"
[Service]
ExecStart=
ExecStart=-/usr/bin/comrade-shell
StandardInput=tty
StandardOutput=tty
AUTOLOGIN

echo "comrade-os" > "$WORK/rootfs/etc/hostname"

echo "[6/8] Przygotowanie środowiska CHROOT..."

# Montowanie
mount --bind /proc "$WORK/rootfs/proc"
mount --bind /sys "$WORK/rootfs/sys"
mount --bind /dev "$WORK/rootfs/dev"
mount --bind /dev/pts "$WORK/rootfs/dev/pts" 2>/dev/null || true
if [ -d /dev/shm ]; then mount --bind /dev/shm "$WORK/rootfs/dev/shm"; fi

# FIX 1: Blokada usług (policy-rc.d)
cat << 'POLICY' > "$WORK/rootfs/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
POLICY
chmod +x "$WORK/rootfs/usr/sbin/policy-rc.d"

# FIX 2: Naprawa /dev/fd (Kluczowe dla skryptów instalacyjnych kernela w chroot!)
if [ ! -L "$WORK/rootfs/dev/fd" ]; then
    ln -s /proc/self/fd "$WORK/rootfs/dev/fd" 2>/dev/null || true
fi

echo "[7/8] Instalacja systemu (Dwuetapowa)..."

# Etap A: Aktualizacja i narzędzia podstawowe
echo ">>> Etap A: Podstawowe narzędzia..."
chroot "$WORK/rootfs" apt-get update
DEBIAN_FRONTEND=noninteractive chroot "$WORK/rootfs" apt-get install -y --no-install-recommends \
    initramfs-tools \
    live-boot \
    systemd-sysv \
    kmod

# Etap B: Instalacja kernela (osobno, aby uniknąć dependency loop)
echo ">>> Etap B: Instalacja Jądra Linux..."
DEBIAN_FRONTEND=noninteractive chroot "$WORK/rootfs" apt-get install -y --no-install-recommends \
    linux-image-amd64

# Etap C: Naprawa ewentualnych błędów
echo ">>> Etap C: Weryfikacja..."
chroot "$WORK/rootfs" apt-get install -f -y

# Sprzątanie blokady
rm "$WORK/rootfs/usr/sbin/policy-rc.d"

# Odmontowanie
cleanup

echo "[8/8] Tworzenie ISO..."
VMLINUZ=$(find "$WORK/rootfs/boot" -name "vmlinuz-*" | sort | tail -n 1)
INITRD=$(find "$WORK/rootfs/boot" -name "initrd.img-*" | sort | tail -n 1)

if [ -z "$VMLINUZ" ] || [ -z "$INITRD" ]; then
    echo "BŁĄD KRYTYCZNY: Kernel nie został zainstalowany poprawnie. Sprawdź logi wyżej."
    exit 1
fi

cp "$VMLINUZ" "$WORK/staging/live/vmlinuz"
cp "$INITRD" "$WORK/staging/live/initrd"

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
echo "Gotowy plik: $ISO_OUT"

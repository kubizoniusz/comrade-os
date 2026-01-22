#!/bin/bash
set -e

WORK="/tmp/comrade-build"
ISO_OUT="ComradeOS-1.0.iso"

# Funkcja czyszcząca w razie błędu
cleanup() {
    echo "Czyszczenie montowania..."
    # Odmontowujemy w odwrotnej kolejności
    umount "$WORK/rootfs/dev/pts" 2>/dev/null || true
    umount "$WORK/rootfs/dev/shm" 2>/dev/null || true
    umount "$WORK/rootfs/dev" 2>/dev/null || true
    umount "$WORK/rootfs/sys" 2>/dev/null || true
    umount "$WORK/rootfs/proc" 2>/dev/null || true
    
    # Usuwamy blokadę usług jeśli została
    rm -f "$WORK/rootfs/usr/sbin/policy-rc.d" 2>/dev/null || true
}
trap cleanup EXIT

echo "★ COMRADE OS BUILDER (FIXED) ★"

echo "[1/7] Instalacja pakietów hosta..."
apk update
apk add wget xorriso squashfs-tools grub grub-bios mtools debootstrap

echo "[2/7] Przygotowanie katalogów..."
# Ręczne czyszczenie przed startem (bez wywoływania trap)
umount "$WORK/rootfs/proc" 2>/dev/null || true
rm -rf "$WORK"
mkdir -p "$WORK"/{rootfs,staging/live,staging/boot/grub}

echo "[3/7] Pobieranie Debian minimal..."
# --no-check-gpg może być potrzebne w niektórych środowiskach Alpine
debootstrap --variant=minbase --arch=amd64 --include=python3,systemd,udev,nano bookworm "$WORK/rootfs" http://deb.debian.org/debian

echo "[4/7] Instalacja skryptów Comrade OS..."
cp comrade_os.py "$WORK/rootfs/usr/bin/comrade_os.py" 2>/dev/null || echo "print('Witaj w ComradeOS')" > "$WORK/rootfs/usr/bin/comrade_os.py"
chmod +x "$WORK/rootfs/usr/bin/comrade_os.py"

cat << 'STARTSCRIPT' > "$WORK/rootfs/usr/bin/comrade-shell"
#!/bin/bash
clear
echo "★ Uruchamianie Comrade OS... ★"
sleep 1
if [ -f /usr/bin/comrade_os.py ]; then
    exec /usr/bin/python3 /usr/bin/comrade_os.py
else
    echo "Brak pliku comrade_os.py, uruchamiam bash."
    exec /bin/bash
fi
STARTSCRIPT
chmod +x "$WORK/rootfs/usr/bin/comrade-shell"

echo "[5/7] Konfiguracja autologowania..."
mkdir -p "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d"
cat << 'AUTOLOGIN' > "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d/override.conf"
[Service]
ExecStart=
ExecStart=-/usr/bin/comrade-shell
StandardInput=tty
StandardOutput=tty
AUTOLOGIN

echo "comrade-os" > "$WORK/rootfs/etc/hostname"

echo "[6/7] Instalacja kernela (NAPRAWIONA)..."

# 1. Montowanie zasobów (ważne: shm i pts)
mount --bind /proc "$WORK/rootfs/proc"
mount --bind /sys "$WORK/rootfs/sys"
mount --bind /dev "$WORK/rootfs/dev"
mount --bind /dev/pts "$WORK/rootfs/dev/pts" 2>/dev/null || true
# Czasami brak /dev/shm powoduje błędy w python/apt
if [ -d /dev/shm ]; then mount --bind /dev/shm "$WORK/rootfs/dev/shm"; fi

# 2. FIX: Blokada uruchamiania usług podczas instalacji (To naprawia błąd dpkg!)
cat << 'POLICY' > "$WORK/rootfs/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
POLICY
chmod +x "$WORK/rootfs/usr/sbin/policy-rc.d"

# 3. Instalacja w chroot
echo "Aktualizacja repozytoriów..."
chroot "$WORK/rootfs" apt-get update

echo "Instalacja jądra i narzędzi..."
# Używamy --no-install-recommends, aby uniknąć instalowania zbędnych pakietów które mogą psuć (np. grub-pc wewnątrz chroot)
DEBIAN_FRONTEND=noninteractive chroot "$WORK/rootfs" apt-get install -y --no-install-recommends \
    linux-image-amd64 \
    live-boot \
    systemd-sysv \
    initramfs-tools

# 4. Sprzątanie blokady (bardzo ważne, inaczej system nie wstanie!)
rm "$WORK/rootfs/usr/sbin/policy-rc.d"

# Odmontowanie
cleanup

echo "[7/7] Tworzenie ISO..."
# Znajdź najnowszy kernel
VMLINUZ=$(find "$WORK/rootfs/boot" -name "vmlinuz-*" | sort | tail -n 1)
INITRD=$(find "$WORK/rootfs/boot" -name "initrd.img-*" | sort | tail -n 1)

if [ -z "$VMLINUZ" ] || [ -z "$INITRD" ]; then
    echo "BŁĄD: Nie znaleziono kernela lub initrd w /boot!"
    exit 1
fi

cp "$VMLINUZ" "$WORK/staging/live/vmlinuz"
cp "$INITRD" "$WORK/staging/live/initrd"

echo "Pakowanie filesystem.squashfs..."
mksquashfs "$WORK/rootfs" "$WORK/staging/live/filesystem.squashfs" -comp xz -no-recovery

echo "Generowanie GRUB..."
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
echo "★★★ GOTOWE! ★★★"
echo "Plik: $ISO_OUT"

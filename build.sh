#!/bin/bash
set -e

WORK="/tmp/comrade-build"
ISO_OUT="ComradeOS-1.0.iso"

echo "★ COMRADE OS BUILDER ★"

echo "[1/7] Instalacja pakietów..."
apk update
apk add wget xorriso squashfs-tools grub grub-bios mtools debootstrap

echo "[2/7] Przygotowanie..."
rm -rf "$WORK"
mkdir -p "$WORK"/{rootfs,staging/live,staging/boot/grub}

echo "[3/7] Pobieranie Debian minimal..."
debootstrap --variant=minbase --include=python3,systemd,udev bookworm "$WORK/rootfs" http://deb.debian.org/debian

echo "[4/7] Instalacja Comrade OS..."

cp comrade_os.py "$WORK/rootfs/usr/bin/comrade_os.py"
chmod +x "$WORK/rootfs/usr/bin/comrade_os.py"

cat << 'STARTSCRIPT' > "$WORK/rootfs/usr/bin/comrade-shell"
#!/bin/bash
clear
echo "★ Uruchamianie Comrade OS... ★"
sleep 1
exec /usr/bin/python3 /usr/bin/comrade_os.py
STARTSCRIPT

chmod +x "$WORK/rootfs/usr/bin/comrade-shell"

echo "[5/7] Konfiguracja systemu..."

mkdir -p "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d"
cat << 'AUTOLOGIN' > "$WORK/rootfs/etc/systemd/system/getty@tty1.service.d/override.conf"
[Service]
ExecStart=
ExecStart=-/usr/bin/comrade-shell
StandardInput=tty
StandardOutput=tty
AUTOLOGIN

echo "comrade-os" > "$WORK/rootfs/etc/hostname"

echo "[6/7] Instalacja kernela..."
chroot "$WORK/rootfs" apt-get update
chroot "$WORK/rootfs" apt-get install -y linux-image-amd64 live-boot

echo "[7/7] Tworzenie ISO..."

cp "$WORK/rootfs/boot/vmlinuz-"* "$WORK/staging/live/vmlinuz"
cp "$WORK/rootfs/boot/initrd.img-"* "$WORK/staging/live/initrd"

mksquashfs "$WORK/rootfs" "$WORK/staging/live/filesystem.squashfs" -comp xz

cat << 'GRUBCFG' > "$WORK/staging/boot/grub/grub.cfg"
set default=0
set timeout=3

menuentry "ComradeOS 1.0" {
    linux /live/vmlinuz boot=live quiet
    initrd /live/initrd
}
GRUBCFG

grub-mkrescue -o "$ISO_OUT" "$WORK/staging"

rm -rf "$WORK"

echo ""
echo "★★★ GOTOWE! ★★★"
echo "Plik: $ISO_OUT"

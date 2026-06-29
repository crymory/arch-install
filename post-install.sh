#!/bin/bash
set -e

echo "========================================================"
echo "   🚀 ARCH LINUX PERF INSTALLER (PART 2: CHROOT) 🚀  "
echo "========================================================"

# Настройка pacman (10 потоков загрузки + multilib для 32-bit/Steam приложений)
sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/\[multilib\]/,+1 s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm

# Часовой пояс и локали
ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "uk_UA.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "arch-perf" > /etc/hostname

# Настройка паролей (переменные переданы из основного скрипта)
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/wheel

# Автоопределение видеокарты и подбор пакетов
echo "Определение GPU..."
GPU_PKGS=""
if lspci | grep -iq "nvidia"; then
    GPU_PKGS="nvidia-zen-dkms nvidia-utils lib32-nvidia-utils nvidia-settings"
elif lspci | grep -iq "amd"; then
    GPU_PKGS="xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon"
else
    GPU_PKGS="xf86-video-intel vulkan-intel lib32-vulkan-intel"
fi
pacman -S --noconfirm $GPU_PKGS

# Установка KDE Plasma, терминала, аудиосервера (Pipewire)
pacman -S --noconfirm plasma-desktop sddm konsole dolphin kate network-manager-applet pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

# Включение системных служб
systemctl enable NetworkManager
systemctl enable sddm

# --- ТВЕКИ МАКСИМАЛЬНОЙ ПРОИЗВОДИТЕЛЬНОСТИ ---

# 1. Сетевой стек BBR (низкий пинг, быстрая пропускная способность)
cat << 'NET' > /etc/sysctl.d/99-performance.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
NET

# 2. ZRAM вместо swap на диске (сжатие в ОЗУ)
pacman -S --noconfirm zram-generator
cat << 'ZRM' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRM

# 3. Утилиты оптимизации планировщика для игр
pacman -S --noconfirm gamemode lib32-gamemode gamescope

# Установка и настройка GRUB
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Конфигурация внутри chroot успешно выполнена!"

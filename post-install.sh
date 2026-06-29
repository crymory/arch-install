#!/bin/bash
set -e

echo "========================================================"
echo "   🚀 ARCH LINUX PERF INSTALLER (PART 2: CHROOT) 🚀  "
echo "========================================================"

# Настройка pacman (10 потоков + multilib для игр/Steam)
sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/\[multilib\]/,+1 s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm

# --- НАСТРОЙКА ВРЕМЕНИ, ЛОКАЛИЗАЦИИ И ЯЗЫКА ---
ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
hwclock --systohc

# Генерируем локали
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Русский язык — основной для интерфейса
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "arch-perf" > /etc/hostname

# Настройка раскладки и шрифта для TTY-консоли (чтобы не было квадратов)
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

# Глобальная настройка раскладки для Wayland/X11 через systemd
localectl set-x11-keymap us,ru pc105 "" grp:alt_shift_toggle


# --- НАСТРОЙКА ПОЛЬЗОВАТЕЛЕЙ ---
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/wheel


# --- ПРЕДНАСТРОЙКА КЛАВИАТУРЫ ДЛЯ KDE PLASMA (WAYLAND) ---
USER_HOME="/home/$USERNAME"
mkdir -p "$USER_HOME/.config"

cat << 'KDEKEY' > "$USER_HOME/.config/kxkbrc"
[Layout]
DisplayNames=,
LayoutList=us,ru
LayoutLoopCount=-1
Model=pc105
Options=grp:alt_shift_toggle
ResetOldOptions=true
SwitchMode=Global
Use=true
VariantList=,
KDEKEY

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config"


# --- АВТООПРЕДЕЛЕНИЕ ВИДЕОКАРТЫ ---
echo "Определение GPU..."
GPU_PKGS=""
if lspci | grep -iq "nvidia"; then
    GPU_PKGS="nvidia-zen-dkms nvidia-utils lib32-nvidia-utils nvidia-settings egl-wayland"
elif lspci | grep -iq "amd"; then
    GPU_PKGS="xf86-video-amdgpu vulkan-radeon lib32-vulkan-radeon"
else
    GPU_PKGS="xf86-video-intel vulkan-intel lib32-vulkan-intel"
fi
pacman -S --noconfirm $GPU_PKGS


# --- УСТАНОВКА ОКРУЖЕНИЯ ---
# Базовый пакет Plasma, SDDM, терминал, проводник и Pipewire для звука
pacman -S --noconfirm plasma-desktop sddm konsole dolphin kate network-manager-applet pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

# Включение системных служб
systemctl enable NetworkManager
systemctl enable sddm


# --- ТВЕКИ МАКСИМАЛЬНОЙ ПРОИЗВОДИТЕЛЬНОСТИ ---

# 1. Сетевой стек BBR (низкий пинг, быстрая обработка пакетов)
cat << 'NET' > /etc/sysctl.d/99-performance.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
NET

# 2. ZRAM вместо медленного swap на диске (сжатие памяти в ОЗУ)
pacman -S --noconfirm zram-generator
cat << 'ZRM' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
ZRM

# 3. Инструменты оптимизации планировщика для игр (Gamemode + Gamescope для Wayland)
pacman -S --noconfirm gamemode lib32-gamemode gamescope


# --- УСТАНОВКА ЗАГРУЗЧИКА ---
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Конфигурация внутри chroot успешно выполнена!"

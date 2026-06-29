#!/bin/bash
set -e

echo "========================================================"
echo "   🚀 ARCH LINUX PERF INSTALLER (PART 2: CHROOT) 🚀  "
echo "========================================================"

# Настройка pacman (10 потоков загрузки + multilib для 32-bit/Steam приложений)
sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/\[multilib\]/,+1 s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm

# --- НАСТРОЙКА ВРЕМЕНИ, ЛОКАЛИЗАЦИИ И ЯЗЫКА ---
ln -sf /usr/share/zoneinfo/Europe/Kyiv /etc/localtime
hwclock --systohc

# Генерируем локали (и английскую, и русскую)
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Устанавливаем русский язык основным для системы
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "arch-perf" > /etc/hostname

# Настройка раскладки клавиатуры в консоли (до запуска графики)
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

# Настройка раскладки клавиатуры для X11/Wayland (KDE Plasma подхватит автоматически)
# Задает раскладки en(us) и ru, переключение по Alt+Shift
mkdir -p /etc/X11/xorg.conf.d
cat << 'KEYBOARD' > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "us,ru"
        Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
KEYBOARD


# --- НАСТРОЙКА ПОЛЬЗОВАТЕЛЕЙ ---
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/wheel


# --- АВТООПРЕДЕЛЕНИЕ ВИДЕОКАРТЫ ---
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


# --- УСТАНОВКА ОКРУЖЕНИЯ ---
# Ставим KDE Plasma, терминал, файловый менеджер и аудиосервер
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


# --- УСТАНОВКА ЗАГРУЗЧИКА ---
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Конфигурация внутри chroot успешно выполнена!"

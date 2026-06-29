#!/bin/bash

# Выход при ошибке
set -e

clear
echo "========================================================"
echo "   🚀 ARCH LINUX PERF INSTALLER (PART 1: BASE) 🚀   "
echo "========================================================"
echo ""

# 1. СИНХРОНИЗАЦИЯ ВРЕМЕНИ
echo "=== [1/5] Синхронизация времени ==="
sed -i 's/^#\?NTP=.*/NTP=time.google.com/' /etc/systemd/timesyncd.conf
sed -i 's/^#\?FallbackNTP=/FallbackNTP=/' /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd
timedatectl set-ntp true
echo "Синхронизация времени запущена..."
sleep 2

# 2. ВЫБОР НАКОПИТЕЛЯ
echo ""
echo "=== [2/5] Выбор накопителя ==="
lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Введите имя диска для установки (например, sda или nvme0n1): " DISK_NAME
DISK="/dev/$DISK_NAME"

if [ ! -b "$DISK" ]; then
    echo "❌ Ошибка: Диск $DISK не найден!"
    exit 1
fi

echo ""
echo "🔥 ВНИМАНИЕ! Все данные на $DISK будут полностью УНИЧТОЖЕНЫ! 🔥"
read -p "Вы уверены? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Отмена установки."
    exit 1
fi

# Именование разделов
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_EFI="${DISK}p1"
    PART_ROOT="${DISK}p2"
else
    PART_EFI="${DISK}1"
    PART_ROOT="${DISK}2"
fi

# 3. НАСТРОЙКА ПОЛЬЗОВАТЕЛЯ И ЭКСПОРТ ДЛЯ CHROOT
echo ""
echo "=== [3/5] Настройка учетных записей ==="
read -p "Введите имя нового пользователя: " USERNAME
read -s -p "Введите пароль для $USERNAME: " USER_PASSWORD
echo ""
read -s -p "Введите пароль для root: " ROOT_PASSWORD
echo ""

# 4. ПОДГОТОВКА BTRFS С ОПТИМИЗАЦИЯМИ
echo ""
echo "=== [4/5] Подготовка файловой системы ==="
sgdisk --zap-all "$DISK"
sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:EFI "$DISK"
sgdisk --new=2:0:0     --typecode=2:8300 --change-name=2:ROOT "$DISK"

partprobe "$DISK"
sleep 1

mkfs.fat -F 32 "$PART_EFI"
mkfs.btrfs -f "$PART_ROOT"

mount "$PART_ROOT" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
umount /mnt

MOUNT_OPTS="noatime,compress=zstd:1,space_cache=v2,discard=async"
mount -o $MOUNT_OPTS,subvol=@ "$PART_ROOT" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache}
mount -o $MOUNT_OPTS,subvol=@home "$PART_ROOT" /mnt/home
mount -o $MOUNT_OPTS,subvol=@log "$PART_ROOT" /mnt/var/log
mount -o $MOUNT_OPTS,subvol=@cache "$PART_ROOT" /mnt/var/cache
mount "$PART_EFI" /mnt/boot

# 5. УСТАНОВКА ЯДРА И БАЗЫ
echo ""
echo "=== [5/5] Установка базы Arch Linux ==="
sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 10/' /etc/pacman.conf

pacstrap -K /mnt base base-devel linux-zen linux-zen-headers linux-firmware networkmanager git nano sudo
genfstab -U /mnt >> /mnt/etc/fstab

# Скачивание отдельного скрипта post-install с GitHub внутрь /mnt
echo "Скачивание post-install.sh..."
# НАПРИМЕР: https://raw.githubusercontent.com/username/repo/main/post-install.sh
URL_POST_INSTALL="https://raw.githubusercontent.com/crymory/arch-install/main/post-install.sh"

curl -L "$URL_POST_INSTALL" -o /mnt/post-install.sh
chmod +x /mnt/post-install.sh

echo "Запуск второй части установки внутри chroot..."
# Передаем переменные окружения внутрь chroot, чтобы post-install их знал
arch-chroot /mnt /bin/bash -c "USERNAME='$USERNAME' USER_PASSWORD='$USER_PASSWORD' ROOT_PASSWORD='$ROOT_PASSWORD' /post-install.sh"

# Чистим за собой скрипт внутри установленной системы
rm -f /mnt/post-install.sh

clear
echo "========================================================"
echo " 🎉 БАЗОВАЯ УСТАНОВКА И НАСТРОЙКА ЗАВЕРШЕНЫ! 🎉"
echo "========================================================"
echo "Вводи 'reboot' и загружайся в готовую систему."

#!/usr/bin/env bash
set -euo pipefail

read -r -p "Имя хоста, будет применяться как в hostname, так и в названиях public-ключей. HOST_LOCATION: " HOST_LOCATION
echo "HOST_LOCATION: $HOST_LOCATION"
echo ""
read -r -p "Публичный ключ для доступа с удаленного компьютера. MacOS auth key: $MACOS_AUTH_KEY: " MACOS_AUTH_KEY
echo "MACOS_AUTH_KEY: $MACOS_AUTH_KEY"
echo ""

# Регистрация пользователя dim
useradd -m -c "${HOST_LOCATION}" dim
echo "Придумайте пароль для USER:dim: "
passwd dim
usermod -aG sudo dim
echo "Пользователь dim создан."

if [[ -n "${HOST_LOCATION:-}" ]]; then
  sudo cp -a /etc/passwd "/etc/passwd.bak.$(date +%Y%m%d)"
  awk -v host_location="$HOST_LOCATION" -F: '
  $1 == "root" {
    print "root:x:0:0:root:/root:/sbin/nologin"
    next
  }
  $1 == "dim" {
    print "dim:x:1000:1000:" host_location ":/home/dim:/bin/bash"
    next
  }
  { print }
  ' /etc/passwd | sudo tee /etc/passwd.new >/dev/null
  sudo mv /etc/passwd.new /etc/passwd

else
  echo "Параметр HOST_LOCATION не найден в .env"

fi

# Настройка ssh
cp -a "/etc/ssh/sshd_config" "/etc/ssh/sshd_config.bak.$(date +%Y%m%d)"
cp "data/sshd_config" "/etc/ssh/"
systemctl restart ssh
echo "auth required pam_listfile.so onerr=succeed item=user sense=deny file=/etc/ssh/deniedusers" >> /etc/pam.d/login
echo "root" > "/etc/ssh/deniedusers" && chmod 600 "/etc/ssh/deniedusers"

# Настройка hostname
hostnamectl set-hostname ${HOST_LOCATION}

# Настройка timezone
timedatectl set-timezone "Europe/Moscow"

#Настройка ufw
ufw allow from 62.113.113.93 proto tcp to any port 32755 comment "ssh from Moscow VDSina" &&
ufw allow from 93.183.92.89 proto tcp to any port 32755 comment "ssh from Moscow VDSina" &&
ufw allow from 91.201.112.87 proto tcp to any port 32755 comment "ssh from Amsterdam VDSina" &&
ufw allow from 194.156.102.107 proto tcp to any port 32755 comment "ssh from Zurich"
ufw allow 443/tcp comment "Xray" && ufw allow 443/udp comment "Xray"
ufw enable && ufw reload && ufw status

# Настройка journalctl
journalctl --vacuum-time=1d

# Настройка sysctl
cp "/etc/sysctl.conf" "/etc/sysctl.conf.back.$(date +%Y%m%d%H%M%S)"
cp "data/sysctl.conf" "/etc/sysctl.conf"
echo "sudo sysctl -p:"
echo ""
sysctl -p

# Автозагрузка Crontab
( crontab -l 2>/dev/null | sed '/^# MYJOBS-BEGIN$/,/^# MYJOBS-END$/d' || true
  cat <<'CRON'
# MYJOBS-BEGIN
0 0,12 * * * reboot
0 2,8,14,20 * * * systemctl restart xray
59 23 * * * truncate -s 0 /var/log/xray/access.log && truncate -s 0 /var/log/xray/error.log
59 23 * * * truncate -s 0 /var/log/syslog && rm /var/log/*.gz && rm /var/log/*.1
59 23 * * * journalctl --vacuum-time=1d
# MYJOBS-END
CRON
) | crontab -

# Обновление пакетов
apt update && apt upgrade -y && apt autoremove -y
apt install file vim ufw cron git gh socat nginx python3.12-venv vnstat iftop -y

# Копирование monitoring/ -> /home/dim/
cp -r monitoring/ /home/dim/
chown -R dim:dim /home/dim/monitoring

# Переключение пользователя на dim
echo "Переключение пользователя -> USER:dim"
echo ""
su dim
cd ~
sudo ls

# Настройка SSH пользователя dim
mkdir "/home/dim/.ssh" && chmod 700 "/home/dim/.ssh"
echo "${MACOS_AUTH_KEY}" >> "/home/dim/.ssh/authorized_keys" && chmod 600 "/home/dim/.ssh/authorized_keys"

# Выбор редактора: VIM
echo 'export EDITOR=vim' >> "/home/dim/.bashrc" && echo 'export VISUAL=vim' >> "/home/dim/.bashrc"
source "/home/dim/.bashrc"
sudo update-alternatives --config editor

# Настройка доступа к github.com
echo "Настройка доступа к github.com."
echo "Регистрация id_ed25519.pub"
echo ""
ssh-keygen -t ed25519 -C "${HOST_LOCATION}@bonifazy" -f "/home/dim/.ssh/id_ed25519"
chmod 700 "/home/dim/.ssh" && chmod 600 "/home/dim/.ssh/id_ed25519" && chmod 644 "/home/dim/.ssh/id_ed25519.pub"
cat >> "/home/dim/.bashrc" <<'EOF'
eval "$(ssh-agent -s)" >/dev/null
ssh-add ~/.ssh/id_ed25519 2>/dev/null
EOF
source "/home/dim/.bashrc"
echo "cat ~/.ssh/id_ed25519.pub:"
cat "/home/dim/.ssh/id_ed25519.pub"

#!/usr/bin/env bash
set -euo pipefail

source ".env"

echo "HOST_LOCATION: $HOST_LOCATION"

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

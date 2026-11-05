#!/usr/bin/env bash
# Applies the RHEL 9 STIG remediations that make sense inside a container
# image to the root filesystem at $1. Rules that only apply to a booted host
# (kernel, boot loader, auditd, sshd, PAM login, partitions, services) are
# not applicable to a container and are reported as such by the SCAP scan.
set -euo pipefail
R=${1:?rootfs path}
APP_UID=${APP_UID:-1001}

# --- Non-root runtime user (uid/gid 1001, no shell, no password) -------------
grep -q "^nginx:" "$R/etc/group" || echo "nginx:x:${APP_UID}:" >> "$R/etc/group"
if grep -q '^nginx:' "$R/etc/passwd"; then
  sed -i -E "s|^nginx:[^:]*:[0-9]+:[0-9]+:|nginx:x:${APP_UID}:${APP_UID}:|" "$R/etc/passwd"
  sed -i -E "s|^(nginx:.*:)[^:]*$|\1/sbin/nologin|" "$R/etc/passwd"
  sed -i -E "s|^nginx:[0-9]+:|nginx:${APP_UID}:|; s|^nginx:x:[0-9]+:|nginx:x:${APP_UID}:|" "$R/etc/group"
else
  echo "nginx:x:${APP_UID}:${APP_UID}:nginx:/var/lib/nginx:/sbin/nologin" >> "$R/etc/passwd"
fi
grep -q '^nginx:' "$R/etc/shadow" || echo 'nginx:!!:20000::::::' >> "$R/etc/shadow"
# Lock every account's password (no interactive logins in the image).
sed -i -E 's/^([^:]+):[^:!*][^:]*:/\1:!!:/' "$R/etc/shadow"

# --- Default umask 077 (accounts_umask_etc_bashrc / _etc_profile) -----------
sed -i -E 's/^([^#]*\bumask)[[:space:]]+[0-7]+/\1 077/' "$R/etc/bashrc"
grep -qE '^[^#]*umask' "$R/etc/bashrc" || echo 'umask 077' >> "$R/etc/bashrc"
grep -qrE '^[^#]*umask' "$R"/etc/profile* || echo 'umask 077' >> "$R/etc/profile"
if [ -f "$R/etc/login.defs" ]; then
  sed -i -E 's/^UMASK.*/UMASK 077/' "$R/etc/login.defs"
fi

# --- Writable paths for a non-root, read-only-root-capable nginx -------------
install -d -m 0750 -o "$APP_UID" -g "$APP_UID" "$R/var/lib/nginx" "$R/var/lib/nginx/tmp" "$R/run/nginx"
install -d -m 0755 "$R/var/log/nginx"
ln -sf /dev/stdout "$R/var/log/nginx/access.log"
ln -sf /dev/stderr "$R/var/log/nginx/error.log"
rm -f "$R/etc/nginx/"*.default "$R/etc/nginx/conf.d/"* "$R/etc/nginx/default.d/"*
rm -f "$R/usr/share/nginx/html/50x.html.orig"

# --- Content: read-only for the runtime user ---------------------------------
chown -R root:root "$R/usr/share/nginx/html" "$R/etc/nginx"
find "$R/usr/share/nginx/html" "$R/etc/nginx" -type d -exec chmod 0755 {} +
find "$R/usr/share/nginx/html" "$R/etc/nginx" -type f -exec chmod 0644 {} +

# --- Strip setuid/setgid bits ------------------------------------------------
find "$R" -xdev -type f \( -perm -4000 -o -perm -2000 \) -print -exec chmod ug-s {} + || true

# --- Remove anything that could install or fetch software -------------------
rm -rf "$R/etc/yum.repos.d/"* "$R/var/cache/"* "$R/tmp/"* "$R/var/tmp/"*
for b in dnf yum microdnf rpm curl wget; do rm -f "$R/usr/bin/$b"; done

# --- World-writable files (other than sticky tmp dirs) -----------------------
find "$R" -xdev -type f -perm -0002 -exec chmod o-w {} + || true

echo "STIG remediation applied to $R"

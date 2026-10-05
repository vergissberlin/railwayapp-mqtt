#!/bin/sh
set -eu

CONFIG_FILE="/mosquitto/config/mosquitto.conf"
PASSWORD_FILE="/mosquitto/config/passwordfile"

ensure_line() {
    line="$1"
    if ! grep -Eq "^${line}$" "$CONFIG_FILE"; then
        printf "\n%s\n" "$line" >> "$CONFIG_FILE"
    fi
}

if [ -n "${MQTT_USER:-}" ] && [ -n "${MQTT_PASS:-}" ]; then
    # Mosquitto 2.1 refuses to overwrite an existing password file with -c.
    # Generate a new file and replace our generated credentials atomically.
    password_dir="$(mktemp -d /mosquitto/config/.password.XXXXXX)"
    trap 'rm -rf "$password_dir"' EXIT HUP INT TERM
    mosquitto_passwd -b -c "$password_dir/passwordfile" "$MQTT_USER" "$MQTT_PASS"
    # mosquitto_passwd creates a root-owned 0600 file, but the broker drops to
    # the mosquitto user before reading it.
    chown mosquitto:mosquitto "$password_dir/passwordfile"
    chmod 600 "$password_dir/passwordfile"
    mv -f "$password_dir/passwordfile" "$PASSWORD_FILE"
    rmdir "$password_dir"
    trap - EXIT HUP INT TERM
    sed -i '/^allow_anonymous /d' "$CONFIG_FILE"
    ensure_line "allow_anonymous false"
    ensure_line "password_file ${PASSWORD_FILE}"
    echo "Configured MQTT password authentication for user: ${MQTT_USER}"
else
    echo "MQTT_USER or MQTT_PASS not set; broker allows anonymous access"
fi

# Railway creates fresh volume mounts as root. The broker must be able to
# persist its database after dropping privileges.
if [ "$(id -u)" -eq 0 ]; then
    mkdir -p /mosquitto/data
    chown -R mosquitto:mosquitto /mosquitto/data
fi

exec "$@"

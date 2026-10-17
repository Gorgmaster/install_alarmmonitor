
#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Alamos Alarm Monitor - automatische Installation
# Zielsystem: Raspberry Pi OS mit Desktop
# Benutzer:   pi
# ============================================================

START_SCRIPT="/usr/local/bin/start_chromium.sh"
SERVICE_DIR="/home/pi/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/alarmmonitor.service"

log() {
    if [[ -t 1 && -n "${TERM:-}" && -z "${NO_COLOR:-}" ]]; then
        printf '\033[1;36m[INFO]\033[0m %s\n' "$*"
    else
        printf '[INFO] %s\n' "$*"
    fi
}

section() {
    if [[ -t 1 && -n "${TERM:-}" && -z "${NO_COLOR:-}" ]]; then
        printf '\n\033[1;34m========== %s ==========\033[0m\n' "$*"
    else
        printf '\n========== %s ==========\n' "$*"
    fi
}

die() {
    if [[ -t 2 && -n "${TERM:-}" && -z "${NO_COLOR:-}" ]]; then
        printf '\033[1;31m[FEHLER]\033[0m %s\n' "$*" >&2
    else
        printf '[FEHLER] %s\n' "$*" >&2
    fi
    exit 1
}

# Das Installationsskript benötigt Root-Rechte.
[[ $EUID -eq 0 ]] || die "Bitte mit sudo ausführen: sudo bash install-alarmmonitor.sh"

# Benutzer prüfen.
id pi >/dev/null 2>&1 || die "Der Benutzer pi existiert nicht."

# ============================================================
# 1. System aktualisieren
# ============================================================

section "1/9 System aktualisieren"
log "Aktualisiere das System."
apt update
apt upgrade -y

# ============================================================
# 2. Benötigte Pakete installieren
# ============================================================

section "2/9 Benötigte Pakete installieren"
log "Installiere benötigte Pakete."
apt install -y \
    chromium \
    unclutter \
    x11-xserver-utils \
    locales \
    raspi-config

CHROMIUM_BIN="$(command -v chromium)" \
    || die "Chromium wurde nicht gefunden."

# ============================================================
# 3. Deutsche Locale konfigurieren
# ============================================================

section "3/9 Deutsche Locale konfigurieren"
log "Konfiguriere de_DE.UTF-8."

if ! grep -qE '^[[:space:]]*de_DE.UTF-8 UTF-8' /etc/locale.gen; then
    if grep -qE '^[[:space:]#]*de_DE.UTF-8 UTF-8' /etc/locale.gen; then
        sed -i -E \
            's/^[[:space:]#]*de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' \
            /etc/locale.gen
    else
        echo 'de_DE.UTF-8 UTF-8' >> /etc/locale.gen
    fi
fi

locale-gen de_DE.UTF-8
update-locale --reset LANG=de_DE.UTF-8
raspi-config nonint do_change_locale de_DE.UTF-8

# ============================================================
# 4. Automatischen Desktop-Login und VNC aktivieren
# ============================================================

section "4/9 Desktop-Login und VNC aktivieren"
log "Aktiviere automatischen Desktop-Login."
raspi-config nonint do_boot_behaviour B4

log "Aktiviere den VNC-Server über raspi-config."
raspi-config nonint do_vnc 0

# ============================================================
# 5. AMWEB-Adresse abfragen
# ============================================================

section "5/9 AMWEB-Adresse eingeben"
while true; do
    read -r -p "AMWEB-Link aus FE2 eingeben: " AMWEB_URL

    if [[ "$AMWEB_URL" =~ ^https?://[^[:space:]]+$ ]]; then
        break
    fi

    echo "Ungültige Adresse. Bitte eine vollständige URL mit http:// oder https:// eingeben."
done

# URL sicher für die spätere Shell-Datei maskieren.
printf -v AMWEB_URL_SHELL '%q' "$AMWEB_URL"

# ============================================================
# 6. Chromium-Startskript erstellen
# ============================================================

section "6/9 Chromium-Startskript erstellen"
log "Erstelle $START_SCRIPT."

cat > "$START_SCRIPT" <<EOF
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/pi/.Xauthority
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

AMWEB_URL=$AMWEB_URL_SHELL

unclutter -idle 0 -pi &

exec "$CHROMIUM_BIN" \\
    --noerrdialogs \\
    --disable-infobars \\
    --password-store=basic \\
    --disable-session-crashed-bubble \\
    --disable-features=TranslateUI \\
    --kiosk \\
    --lang=de-DE \\
    --accept-lang=de-DE,de \
    "\$AMWEB_URL"
EOF

chmod +x "$START_SCRIPT"
chown root:root "$START_SCRIPT"

# ============================================================
# 7. systemd-User-Service erstellen
# ============================================================

section "7/9 systemd-User-Service erstellen"
log "Erstelle $SERVICE_FILE."

install -d -o pi -g pi -m 0755 "$SERVICE_DIR"

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Starte Chromium im Kiosk-Modus
After=graphical-session.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/start_chromium.sh
Restart=always
RestartSec=5
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/pi/.Xauthority

[Install]
WantedBy=default.target
EOF

chown pi:pi "$SERVICE_FILE"
chmod 644 "$SERVICE_FILE"

# ============================================================
# 8. User-Service aktivieren und starten
# ============================================================

section "8/9 User-Service aktivieren"
log "Aktiviere den systemd-User-Service."

loginctl enable-linger pi

PI_UID="$(id -u pi)"
PI_RUNTIME_DIR="/run/user/$PI_UID"
PI_BUS="$PI_RUNTIME_DIR/bus"

# User-Manager starten, falls er noch nicht läuft.
systemctl start "user@${PI_UID}.service" || true

# Auf den User-Bus warten.
for _ in {1..10}; do
    [[ -S "$PI_BUS" ]] && break
    sleep 1
done

if [[ -S "$PI_BUS" ]]; then
    runuser -u pi -- env \
        XDG_RUNTIME_DIR="$PI_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$PI_BUS" \
        systemctl --user daemon-reload

    runuser -u pi -- env \
        XDG_RUNTIME_DIR="$PI_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$PI_BUS" \
        systemctl --user enable --now alarmmonitor.service

    log "Service wurde aktiviert und gestartet."
else
    # Aktivierung für die nächste User-Session sicherstellen.
    install -d -o pi -g pi -m 0755 "$SERVICE_DIR/default.target.wants"

    ln -sfn "$SERVICE_FILE" \
        "$SERVICE_DIR/default.target.wants/alarmmonitor.service"

    chown -h pi:pi "$SERVICE_DIR/default.target.wants/alarmmonitor.service"

    log "User-Bus noch nicht verfügbar."
    log "Der Service ist für die nächste User-Session aktiviert."
fi

# ============================================================
# 9. Abschluss
# ============================================================

section "9/9 Installation abgeschlossen"
log "Installation abgeschlossen."
echo "Locale:       de_DE.UTF-8"
echo "Chromium:     $CHROMIUM_BIN"
echo "Startskript:  $START_SCRIPT"
echo "Service:      $SERVICE_FILE"
echo
echo "Neustart empfohlen: sudo reboot"
echo "Status: systemctl --user status alarmmonitor.service"
echo "Logs:   journalctl --user -u alarmmonitor.service -b"

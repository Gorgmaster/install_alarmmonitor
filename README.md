# Alamos Alarm Monitor installieren

Dieses Skript richtet auf einem Raspberry Pi mit Raspberry Pi OS und Desktop einen automatischen Chromium-Aufruf im Kiosk-Modus ein. Es konfiguriert die deutsche Locale, aktiviert den automatischen Desktop-Login und VNC und richtet den Chromium-Start als systemd-User-Service für den Benutzer `pi` ein.

## Voraussetzungen

- Raspberry Pi 4 mit Raspberry Pi OS und Desktop
- Internetverbindung
- Benutzerkonto `pi`
- Zugriff auf ein Terminal

## Installation

1. Öffne ein Terminal auf dem Raspberry Pi.
2. Lade nur das Installationsskript von GitHub herunter:

   ```bash
   curl -fL https://raw.githubusercontent.com/Gorgmaster/install_alarmmonitor/main/installskript.sh -o installskript.sh
   ```

3. Starte das Skript mit Root-Rechten:

   ```bash
   sudo bash installskript.sh
   ```

4. Folge der Eingabeaufforderung und gib den vollständigen AMWEB-Link aus FE2 ein.
5. Nach Abschluss starte den Raspberry Pi neu:

   ```bash
   sudo reboot
   ```

Das Skript aktualisiert das System und installiert benötigte Pakete. Je nach Internetverbindung kann das einige Zeit dauern.

## Nach der Installation

Der Chromium-Service läuft im Benutzerkontext von `pi`. Status und Protokoll lassen sich nach der Anmeldung als `pi` prüfen:

```bash
systemctl --user status alarmmonitor.service
journalctl --user -u alarmmonitor.service -b
```

VNC ist während der Installation aktiviert. Verbinde dich mit der VNC-Software deiner Wahl zur IP-Adresse des Raspberry Pi. Stelle sicher, dass der Pi im Netzwerk erreichbar ist.

## Hinweise

- Das Skript setzt voraus, dass der Benutzer `pi` existiert.
- Der AMWEB-Link wird während der Installation abgefragt und im Chromium-Startskript gespeichert.
- Die Locale wird auf `de_DE.UTF-8` gesetzt.
- Das Skript benötigt eine Installation von Raspberry Pi OS mit grafischer Desktop-Umgebung.

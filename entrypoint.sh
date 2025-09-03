#!/bin/bash

# Stelle sicher, dass die Verzeichnisstruktur existiert
mkdir -p /app/kontoauszuge/Logs

# Stelle sicher, dass die Skripte ausführbar sind
chmod +x /app/scripts/*.rb

# Setze Berechtigungen für das gemountete Volumen
chown -R 1000:1000 /app/excel-files

# Erstelle eine Datei mit Umgebungsvariablen für cron
env | grep -v "PATH" > /etc/environment
echo "GEM_PATH=$(gem env gempath)" >> /etc/environment
echo "GEM_HOME=$(gem env home)" >> /etc/environment
echo "PATH=/usr/local/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> /etc/environment
chmod 0644 /etc/environment

# Erstelle Log-Datei
touch /var/log/cron.log

# Starte den Cron-Dienst
service cron start

# Halte den Container am Laufen
tail -f /var/log/cron.log
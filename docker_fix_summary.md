# docker_cron_fix.md

## Problem
```
cannot load such file -- nokogiri (LoadError)
```

## Ursache
Cron-Jobs haben eine minimale Umgebung ohne Ruby-Gem-Pfade.

## Lösung
**Dockerfile ändern:**

1. Environment-Variablen für Cron exportieren:
```dockerfile
RUN printenv | grep -v "no_proxy" >> /etc/environment
```

2. PATH explizit im Cron-Job setzen:
```dockerfile
RUN echo "*/5 * * * * cd /app/scripts && PATH=/usr/local/bin:/usr/bin:/bin && /usr/local/bin/ruby doit.rb >> /var/log/cron.log 2>&1" | crontab -
```

## Ergebnis
Ruby findet jetzt die installierten Gems im Docker-Container.
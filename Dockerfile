# Dockerfile
FROM ruby:3.1-slim

# Installiere notwendige Abhängigkeiten für Excel-Verarbeitung und Cron
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    libxml2-dev \
    libxslt-dev \
    cron \
    tzdata \
    tree \
    nano \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Zeitzone auf Europe/Berlin setzen
ENV TZ=Europe/Berlin
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Installiere benötigte Gems für Excel-Verarbeitung
RUN gem install nokogiri rubyzip:2.3.2 roo

# Arbeitsverzeichnis erstellen
WORKDIR /app

# Log-Datei erstellen
RUN touch /var/log/cron.log

# Environment-Variablen für Cron setzen
RUN printenv | grep -v "no_proxy" >> /etc/environment

# Erstelle den Cron-Job mit korrektem PATH
RUN echo "*/4 * * * * cd /app/scripts && PATH=/usr/local/bin:/usr/bin:/bin && /usr/local/bin/ruby doit.rb >> /var/log/cron.log 2>&1" | crontab -

# Führe cron im Vordergrund aus UND gib die Logs aus
CMD cron && tail -f /var/log/cron.log
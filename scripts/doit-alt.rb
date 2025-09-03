require_relative 'ta_sp_gutschriften'
require_relative 'nicht_vorhandene_gutschriften'

verarbeiter = KontoauszugVerarbeiter.new(PATH)
verarbeiter.dateien_verarbeiten
processor = TransaktionenProcessor.new(
    PATH, # Aktuelles Verzeichnis nach Excel-Dateien durchsuchen
    File.join(PATH,"transaktionen.html"),
    File.join(PATH,"nicht_vorhandene_transaktionen.html")
  )
processor.create_filtered_html_file
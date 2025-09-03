# bericht_ersteller.rb

#require_relative 'ta_sp_gutschriften'
#require_relative 'html_generator'
#require_relative 'transactions_filter'

require 'fileutils'
require_relative 'html_generator'      # für HTMLGenerator
require_relative 'transactions_filter' # für TransactionsFilter

#PATH = '../kontoauszuge' #ist in ta_sp_gutschriftem definiert

class BerichtErsteller
  def initialize(verzeichnis = PATH)
    @verzeichnis = verzeichnis
  end
  
  def erstelle_alle_berichte
    # Prüfe einmal ob neue Dateien vorhanden sind
    test_verarbeiter = KontoauszugVerarbeiter.new(@verzeichnis)
    return unless test_verarbeiter.neue_dateien_vorhanden?
    
    # 1. Neue Zugänge (aktuelles Jahr)
    erstelle_neue_zugange_bericht
    
    # 2. Gesamtliste (6 Monate mit select_minimal_recent_files)
    erstelle_gesamt_bericht
    
    # 3. Nicht in Poppy erfasste Gutschriften (Dummy)
    erstelle_poppy_bericht
    
    # Zeitstempel erst am Ende aktualisieren
    FileUtils.touch(File.join(@verzeichnis, '.last_zip'))
  end
  
  #private
  
  def erstelle_neue_zugange_bericht
    # Verarbeiter für neue Zugänge (aktuelles Jahr mit select_minimal_recent_files)
    verarbeiter = NeueZugaengeVerarbeiter.new(@verzeichnis)
    
    verarbeiter.dateien_verarbeiten
    
    alle_transaktionen = verarbeiter.transaktionen
    neue_transaktionen, juengste_zip = TransactionsFilter.ermittle_juengste_transaktionen(alle_transaktionen)
    
    # DUPLIKATE ENTFERNEN
    neue_transaktionen = TransactionsFilter.entferne_duplikate(neue_transaktionen)
    
    # HTML-Bericht erstellen
    html = HTMLGenerator.erstelle_bericht(neue_transaktionen, "Neue Zugänge")
    HTMLGenerator.speichere_bericht(html, @verzeichnis, "neue_zugange.html")
  end
  
  def erstelle_gesamt_bericht
    puts "=== DEBUG: Starte Gesamtbericht ==="
    # Neuer Verarbeiter für Gesamtliste (6 Monate)
    verarbeiter_gesamt = GesamtVerarbeiter.new(@verzeichnis)
    verarbeiter_gesamt.dateien_verarbeiten
    
    alle_transaktionen = verarbeiter_gesamt.transaktionen
    puts "=== DEBUG: #{alle_transaktionen.length} Transaktionen vor Duplikat-Entfernung ==="
    
    # DUPLIKATE ENTFERNEN
    alle_transaktionen = TransactionsFilter.entferne_duplikate(alle_transaktionen)
    puts "=== DEBUG: #{alle_transaktionen.length} Transaktionen nach Duplikat-Entfernung ==="
    
    if alle_transaktionen.length > 0
      # HTML-Bericht erstellen
      html = HTMLGenerator.erstelle_bericht(alle_transaktionen, "Gesamtliste (6 Monate)")
      HTMLGenerator.speichere_bericht(html, @verzeichnis, "transaktionen.html")
      puts "=== DEBUG: transaktionen.html erstellt ==="
    else
      puts "=== DEBUG: KEINE Transaktionen - Bericht wird NICHT erstellt ==="
    end
  end
  
  def erstelle_poppy_bericht
    # Lade alle Transaktionen (könnte auch aus vorherigen Berichten kommen)
    verarbeiter = KontoauszugVerarbeiter.new(@verzeichnis)
    verarbeiter.dateien_verarbeiten
    alle_transaktionen = verarbeiter.transaktionen
    
    # DUPLIKATE ENTFERNEN
    alle_transaktionen = TransactionsFilter.entferne_duplikate(alle_transaktionen)
    
    # Dummy: Filtere Transaktionen die nicht in Poppy sind
    nicht_in_poppy = TransactionsFilter.filtere_nicht_in_poppy(alle_transaktionen)
    
    # HTML-Bericht erstellen
    html = HTMLGenerator.erstelle_bericht(nicht_in_poppy, "Nicht in Poppy erfasste Gutschriften")
    HTMLGenerator.speichere_bericht(html, @verzeichnis, "nicht_in_poppy.html")
  end
end

# Klasse für Neue Zugänge mit select_minimal_recent_files für aktuelles Jahr
class NeueZugaengeVerarbeiter < KontoauszugVerarbeiter
  def select_recent_2_files(verzeichnis = PATH)
    # Alle ZIP-Dateien im Verzeichnis finden
    zip_dateien = Dir.glob(File.join(verzeichnis, "*.ZIP"))
    
    return [] if zip_dateien.empty?
    
    # Sortiere nach End-Datum (zweites Datum im Dateinamen) absteigend
    sortierte_dateien = zip_dateien.sort_by do |zip_datei|
      basename = File.basename(zip_datei)
      # Extrahiere End-Datum aus ZIP-Dateiname "20250807-20250821-4619086-camt52v8Booked.ZIP"
      dates = basename.match(/(\d{8})-(\d{8})/)
      if dates
        Date.parse(dates[2])  # End-Datum
      else
        Date.new(1900, 1, 1)  # Fallback für ungültige Dateinamen
      end
    end.reverse  # Neueste zuerst
    
    # Nimm die ersten 2 (neuesten) Dateien
    return sortierte_dateien.first(2)
  end
  def dateien_verarbeiten
    # Nutze select_minimal_recent_files für aktuelles Jahr (12 Monate)
    selected_zip_files = select_recent_2_files
    
    # ZIP-Dateien verarbeiten
    selected_zip_files.each do |zip_datei|
      puts zip_datei
      zip_datei_verarbeiten(zip_datei)
    end
    
    # Auch XML-Dateien direkt im Verzeichnis verarbeiten
    Dir.glob(File.join(@verzeichnis, "*.xml")).each do |xml_datei|
      xml_datei_verarbeiten(xml_datei)
    end
    
    # Sortiere Transaktionen nach Datum absteigend
    @transaktionen.sort_by! { |t| t[:buchungsdatum] }.reverse!
  end
end

# Klasse für Gesamtbericht mit select_minimal_recent_files
class GesamtVerarbeiter < KontoauszugVerarbeiter
  def dateien_verarbeiten
    # Nutze select_minimal_recent_files für 6 Monate (mehr als 3)
    selected_zip_files = select_minimal_recent_files(6)
    puts "=== DEBUG: Gesamtbericht #{selected_zip_files.length} Dateien gefunden ==="
    
    # ZIP-Dateien verarbeiten
    selected_zip_files.each do |zip_datei|
      puts zip_datei
      zip_datei_verarbeiten(zip_datei)
    end
    
    # Auch XML-Dateien direkt im Verzeichnis verarbeiten
    Dir.glob(File.join(@verzeichnis, "*.xml")).each do |xml_datei|
      xml_datei_verarbeiten(xml_datei)
    end
    
    # Sortiere Transaktionen nach Datum absteigend
    @transaktionen.sort_by! { |t| t[:buchungsdatum] }.reverse!
    puts "=== DEBUG: Gesamtbericht #{@transaktionen.length} Transaktionen nach Verarbeitung ==="
  end
end

# Erweitere HTMLGenerator um die ermittle_juengste_transaktionen Funktion


# Script ausführen
if __FILE__ == $0
  ersteller = BerichtErsteller.new
  ersteller.erstelle_alle_berichte
end
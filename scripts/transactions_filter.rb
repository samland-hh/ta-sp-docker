# transactions_filter.rb

class TransactionsFilter
  
  # Ermittelt Transaktionen die nur in der jüngsten ZIP-Datei sind
  def self.ermittle_juengste_transaktionen(transaktionen)
    # Ermittle die 2 jüngsten ZIP-Dateien
    zip_dateien = transaktionen.map { |t| t[:zip_datei] }.compact.uniq
    
    # KORREKTUR: Sortiere nach End-Datum absteigend und nimm die ersten 2
    juengste_zip_dateien = zip_dateien.sort_by do |zip_datei|
      # Extrahiere End-Datum aus ZIP-Dateiname "20250717-20250731-4619086-camt52v8Booked.ZIP"
      dates = zip_datei.match(/(\d{8})-(\d{8})/)
      dates ? Date.parse(dates[2]) : Date.new(1900, 1, 1)
    end.reverse.first(2)  # ÄNDERUNG: .first(2) statt [0, 2]
    
    return [], nil if juengste_zip_dateien.empty?
    
    # Transaktionen aus jüngster ZIP-Datei
    juengste_zip = juengste_zip_dateien.first
    transaktionen_juengste_zip = transaktionen.select { |t| t[:zip_datei] == juengste_zip }
    
    # Falls es eine zweite ZIP-Datei gibt, entferne überschneidende Transaktionen
    if juengste_zip_dateien.length > 1
      zweitjuengste_zip = juengste_zip_dateien[1]
 
      transaktionen_zweitjuengste_zip = transaktionen.select { |t| t[:zip_datei] == zweitjuengste_zip }
      
      # VERBESSERTE DUPLIKAT-ERKENNUNG: Verwende mehr Felder für eindeutige Identifikation
      zweitjuengste_schluessel = transaktionen_zweitjuengste_zip.map do |t|
        # Erweitere Schlüssel um Überweisungsinformationen für bessere Eindeutigkeit
        [
          t[:buchungsdatum], 
          t[:betrag], 
          t[:zahler_empfaenger],
          t[:ueberweisungsinformationen]&.strip,
          t[:kdnr]
        ].join('|')
      end.to_set
 
      File.open('/tmp/x-alt.txt', 'w') {|f| f.puts zweitjuengste_schluessel.count
        zweitjuengste_schluessel.each{|el| f.puts el}
      }
      File.open('/tmp/x-neu.txt', 'w') {|f| 
        schluessel = transaktionen_juengste_zip.map do |t|
          [
            t[:buchungsdatum], 
            t[:betrag], 
            t[:zahler_empfaenger],
            t[:ueberweisungsinformationen]&.strip,
            t[:kdnr]
          ].join('|')
        end
        f.puts schluessel.count
        schluessel.each{|el| f.puts el}
      }
      
      
      # Filtere nur Transaktionen, die nicht in der zweitjüngsten ZIP sind
      neue_transaktionen = transaktionen_juengste_zip.select do |t|
        schluessel = [
          t[:buchungsdatum], 
          t[:betrag], 
          t[:zahler_empfaenger],
          t[:ueberweisungsinformationen]&.strip,
          t[:kdnr]
        ].join('|')
        !zweitjuengste_schluessel.include?(schluessel)
      end
      
      return neue_transaktionen, juengste_zip
    else
      # Nur eine ZIP-Datei vorhanden
      return transaktionen_juengste_zip, juengste_zip
    end
  end
  
  # NEUE METHODE: Entferne Duplikate aus einer Transaktionsliste
  def self.entferne_duplikate(transaktionen)
    gesehen = Set.new
    eindeutige_transaktionen = []
    
    transaktionen.each do |t|
      # Erstelle eindeutigen Schlüssel
      schluessel = [
        t[:buchungsdatum], 
        t[:betrag], 
        t[:zahler_empfaenger],
        t[:ueberweisungsinformationen]&.strip,
        t[:kdnr]
      ].join('|')
      
      # Füge nur hinzu, wenn noch nicht gesehen
      unless gesehen.include?(schluessel)
        gesehen.add(schluessel)
        eindeutige_transaktionen << t
      end
    end
    
    eindeutige_transaktionen
  end
  
  # Filtert Transaktionen die nicht in Poppy erfasst sind (Dummy)
  def self.filtere_nicht_in_poppy(transaktionen)
    # DUMMY IMPLEMENTIERUNG
    # In echter Version: Excel-Datei laden, Belegnummern extrahieren, vergleichen
    
    puts "DUMMY: Filtere Transaktionen ohne Rechnungsnummer oder mit unbekannter Rechnungsnummer"
    
    # Dummy-Logic: Nimm Transaktionen die keine Rechnungsnummer haben
    # oder deren Rechnungsnummer nicht in einer (dummy) Poppy-Liste steht
    poppy_rechnungsnummern = ["202500466", "202500472", "202500507"].to_set # Dummy-Daten
    
    nicht_erfasst = transaktionen.select do |t|
      # Extrahiere Rechnungsnummer aus Überweisungsinformationen
      rechnungsnummer = t[:ueberweisungsinformationen].match(/(202\d{6})/)
      
      if rechnungsnummer
        # Hat Rechnungsnummer - prüfe ob in Poppy
        !poppy_rechnungsnummern.include?(rechnungsnummer[1])
      else
        # Keine Rechnungsnummer - immer als "nicht erfasst" markieren
        true
      end
    end
    
    return nicht_erfasst
  end
  
  # Filtert Transaktionen nach Zeitraum
  def self.filtere_nach_zeitraum(transaktionen, von_datum, bis_datum)
    transaktionen.select do |t|
      buchungsdatum = Date.parse(t[:buchungsdatum]) rescue nil
      buchungsdatum && buchungsdatum >= von_datum && buchungsdatum <= bis_datum
    end
  end
  
  # Filtert Transaktionen nach Betrag (Mindestbetrag)
  def self.filtere_nach_mindestbetrag(transaktionen, mindestbetrag)
    transaktionen.select do |t|
      betrag = t[:betrag].to_f rescue 0
      betrag >= mindestbetrag
    end
  end
  
  # Filtert Transaktionen nach Kundennummer
  def self.filtere_nach_kunde(transaktionen, kdnr)
    transaktionen.select do |t|
      t[:kdnr] == kdnr
    end
  end
  
end
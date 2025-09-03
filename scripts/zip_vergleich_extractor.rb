# zip_vergleich_extractor.rb
# Extrahiert Transaktionsdaten aus den letzten 2 ZIP-Dateien für Vergleichszwecke

require 'nokogiri'
require 'zip'
require 'date'

PATH = '../kontoauszuge'
NAMESPACE = 'urn:iso:std:iso:20022:tech:xsd:camt.052.001.08'

class ZipVergleichExtractor
  def initialize(verzeichnis)
    @verzeichnis = verzeichnis
  end
  
  def finde_neueste_zip_dateien(anzahl = 2)
    # Finde alle ZIP-Dateien mit dem passenden Pattern
    pattern = File.join(@verzeichnis, "*-*-*-camt52v8Booked.ZIP")
    filenames = Dir.glob(pattern)
    
    return [] if filenames.empty?
    
    # Parse filenames zu Datumsbereichen und sortiere nach End-Datum (neueste zuerst)
    files = filenames.map do |filepath|
      filename = File.basename(filepath)
      dates = filename.match(/(\d{8})-(\d{8})/)
      next nil unless dates
      
      {
        filepath: filepath,
        filename: filename,
        start_date: Date.parse(dates[1]),
        end_date: Date.parse(dates[2])
      }
    end.compact
    
    # Sortiere nach End-Datum absteigend (neueste zuerst)
    files.sort_by! { |f| -f[:end_date].to_time.to_i }
    
    # Nimm die ersten 'anzahl' Dateien
    selected = files.first(anzahl)
    
    puts "Gefundene ZIP-Dateien (sortiert nach End-Datum):"
    files.each_with_index do |file, index|
      marker = index < anzahl ? "-> " : "   "
      puts "#{marker}#{file[:filename]} (#{file[:start_date]} bis #{file[:end_date]})"
    end
    
    selected
  end
  
  def extrahiere_transaktionen_aus_zip(zip_info)
    transaktionen = []
    
    Zip::File.open(zip_info[:filepath]) do |zip|
      zip.each do |eintrag|
        next unless eintrag.name.end_with?('.xml')
        
        xml_inhalt = eintrag.get_input_stream.read
        doc = Nokogiri::XML(xml_inhalt)
        
        transaktionen.concat(extrahiere_gutschriften(doc))
      end
    end
    
    transaktionen
  end
  
  def extrahiere_gutschriften(doc)
    ns = { 'camt' => NAMESPACE }
    transaktionen = []
    
    # Alle Transaktionseinträge finden
    entries = doc.xpath('//camt:Ntry', ns)
    
    entries.each do |entry|
      # Nur Gutschriften berücksichtigen (CdtDbtInd = 'CRDT')
      credit_debit_indicator = entry.at_xpath('./camt:CdtDbtInd', ns)&.text
      next unless credit_debit_indicator == 'CRDT'
      
      # Basis-Informationen extrahieren
      betrag = entry.at_xpath('./camt:Amt', ns)&.text
      buchungsdatum = entry.at_xpath('./camt:BookgDt/camt:Dt', ns)&.text
      
      # Transaktionsdetails
      tx_details = entry.xpath('./camt:NtryDtls/camt:TxDtls', ns)
      
      if tx_details.any?
        tx_details.each do |tx|
          # Zahler/Empfänger ermitteln
          zahler_empfaenger = tx.at_xpath('.//camt:UltmtDbtr/camt:Pty/camt:Nm', ns)&.text
          
          # Falls UltmtDbtr nicht gefunden, versuche Dbtr als Fallback
          if zahler_empfaenger.nil? || zahler_empfaenger.empty?
            zahler_empfaenger = tx.at_xpath('.//camt:Dbtr/camt:Pty/camt:Nm', ns)&.text
          end
          
          zahler_empfaenger ||= 'Unbekannt'
          
          # Adressinformationen hinzufügen
          addr_info = []
          pstl_code = tx.at_xpath(".//camt:UltmtDbtr/camt:PstlAdr/camt:PstCd", ns)&.text
          town = tx.at_xpath(".//camt:UltmtDbtr/camt:PstlAdr/camt:TwnNm", ns)&.text
          
          if pstl_code && town
            addr_info << "#{pstl_code} #{town}"
          elsif pstl_code
            addr_info << pstl_code
          elsif town
            addr_info << town
          end
          
          if addr_info.any?
            zahler_empfaenger = "#{zahler_empfaenger} #{addr_info.join(' ')}"
          end
          
          transaktionen << {
            buchungsdatum: buchungsdatum,
            betrag: betrag,
            zahler_empfaenger: zahler_empfaenger
          }
        end
      else
        # Fallback wenn keine Transaktionsdetails vorhanden
        zahler_empfaenger = entry.at_xpath('.//camt:UltmtDbtr/camt:Nm', ns)&.text || 'Unbekannt'
        
        transaktionen << {
          buchungsdatum: buchungsdatum,
          betrag: betrag,
          zahler_empfaenger: zahler_empfaenger
        }
      end
    end
    
    transaktionen
  end
  
  def erstelle_vergleichsdateien
    zip_dateien = finde_neueste_zip_dateien(2)
    
    if zip_dateien.length < 2
      puts "Nicht genügend ZIP-Dateien gefunden (benötigt: 2, gefunden: #{zip_dateien.length})"
      return
    end
    
    zip_dateien.each_with_index do |zip_info, index|
      puts "\nVerarbeite #{zip_info[:filename]}..."
      
      transaktionen = extrahiere_transaktionen_aus_zip(zip_info)
      
      # Dateiname für Ausgabe
      output_filename = "vergleich_#{index + 1}_#{zip_info[:filename].gsub('.ZIP', '.txt')}"
      output_path = File.join(@verzeichnis, output_filename)
      
      # Schreibe Transaktionen in Textdatei
      File.open(output_path, 'w') do |file|
        file.puts "# Transaktionen aus: #{zip_info[:filename]}"
        file.puts "# Zeitraum: #{zip_info[:start_date]} bis #{zip_info[:end_date]}"
        file.puts "# Anzahl Transaktionen: #{transaktionen.length}"
        file.puts "# Format: Buchungsdatum | Betrag | Zahler"
        file.puts "#" + "=" * 60
        
        transaktionen.sort_by { |t| t[:buchungsdatum] }.reverse.each do |trans|
          file.puts "#{trans[:buchungsdatum]} | #{trans[:betrag]} | #{trans[:zahler_empfaenger]}"
        end
      end
      
      puts "  -> #{transaktionen.length} Transaktionen geschrieben nach: #{output_filename}"
    end
    
    puts "\nVergleichsdateien erstellt!"
    puts "Du kannst sie jetzt mit einem Text-Editor oder diff-Tool vergleichen."
  end
end

if __FILE__ == $0
  extractor = ZipVergleichExtractor.new(PATH)
  extractor.erstelle_vergleichsdateien
end
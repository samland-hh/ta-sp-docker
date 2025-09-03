# -*- coding: utf-8 -*-
# Deutsches Encoding für Umlaute

require 'roo'
require 'nokogiri'
require 'open-uri'
require 'time'
require 'set'

# Deutsches Encoding explizit setzen
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

NBT = "Gutschriften die nicht als bezahlt markiert sind. "
NEG = "In Poppy nicht erfasste Gutschriften"

class TransaktionenProcessor
  def initialize(excel_directory = '.', html_file_path = nil, output_file_path = "nicht_vorhandene_transaktionen.html")
    #p "#{__method__}"
    @excel_directory = excel_directory
    @html_file_path = html_file_path
    @output_file_path = output_file_path
    @latest_excel_file = find_latest_excel_file
    @zeitstempel_datei = File.join(@excel_directory, '.last_excel')
    FileUtils.touch(@zeitstempel_datei) unless File.exist?(@zeitstempel_datei)
    begin
    @nix_neues = File.mtime(@zeitstempel_datei) <  File.mtime(@latest_excel_file)  ||
                 File.mtime(@zeitstempel_datei) < File.mtime(@html_file_path)  ? false : true
    rescue
      system("touch #{@html_file_path}")
      raise "\n#{'#'*80}\Leere #{@html_file_path} erzeugt\nBITTE NOCHMAL STARTEN!!!\n#{'#'*80}"
    end
  end

  # Findet die aktuellste Excel-Datei im angegebenen Verzeichnis
  def find_latest_excel_file
    excel_files = Dir.glob(File.join(@excel_directory, "OPList*.xlsx"))
    return raise("\nOPList...xlsx nicht vorhanden!!! Bitte von Poppy holen!!!\n#{'#'*80}") if excel_files.empty?

    # Sortiere Dateien nach Änderungsdatum (neueste zuerst)
    latest_file = excel_files.max_by do |file|
      # Extrahiere das Datum aus dem Dateinamen
      date_str = file.match(/(\d{4}-\d{2}-\d{2} \d{2}_\d{2})\.xlsx/)
      date_str ? date_str[1] : "0000-00-00 00_00"
    end

    puts "Verwende aktuellste Excel-Datei: #{latest_file}"
    return latest_file
  end

  # Extrahiert das Zeitstempel aus dem Excel-Dateinamen
  def extract_timestamp_from_filename(filename)
    if match = filename.match(/(\d{4}-\d{2}-\d{2} \d{2}_\d{2})/)
      return match[1]
    end
    return "Unbekanntes Datum"
  end

  # Extrahiert Belegnummern aus einer Excel-Datei
  def extract_belegnummer(file_path = @latest_excel_file)
    #puts "__method__ #{file_path}"
    return [] unless file_path
    
    excel = Roo::Spreadsheet.open(file_path)
    sheet = excel.sheet(0)
    
    header_row = sheet.row(1)
    belegnummer_index = header_row.find_index("Belegnummer")
    
    unless belegnummer_index
      puts "Spalte 'Belegnummer' wurde nicht gefunden!"
      return []
    end
    
    belegnummern = []
    (2..sheet.last_row).each do |row_index|
      belegnummern << sheet.cell(row_index, belegnummer_index + 1)
    end
    
    return belegnummern
  end

  # Extrahiert den numerischen Teil aus den Belegnummern
  def extract_numeric_parts(belegnummern)
    belegnummern.map do |beleg|
      beleg.to_s.gsub(/\D/, '')
    end
  end

  # Deutsche HTML-Datei robust lesen
  def robust_read_german_html(file_path)
    #puts "=== DEUTSCHES ENCODING DEBUG ==="
    #puts "System Locale: #{ENV['LANG'] || ENV['LC_ALL'] || 'unbekannt'}"
    #puts "Ruby Default External: #{Encoding.default_external}"
    #puts "Ruby Default Internal: #{Encoding.default_internal}"
    #puts "Dateigröße: #{File.size(file_path)} Bytes"
    #puts "Umlaut-Test: äöüÄÖÜß"
    
    begin
      # Versuche zuerst native UTF-8 Lesen
      content = File.read(file_path, encoding: 'UTF-8:UTF-8')
     # puts "UTF-8 Lesen erfolgreich: #{content.length} Zeichen"
      
      # Prüfe Validität
      unless content.valid_encoding?
        raise Encoding::InvalidByteSequenceError, "Ungültiges UTF-8"
      end
      
      return content
      
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError => e
      puts "UTF-8 Problem: #{e.message} - Versuche Reparatur..."
      
      # Binär lesen und deutsche Encodings testen
      binary_content = File.binread(file_path)
     # puts "Binär gelesen: #{binary_content.size} Bytes"
      
      # Deutsche/Europäische Encodings der Reihe nach testen
      encodings_to_try = [
        'UTF-8',
        'Windows-1252',  # Deutsche Windows-Systeme
        'ISO-8859-1',    # Latin-1
        'ISO-8859-15',   # Latin-9 (mit Euro-Symbol)
        'CP850'          # Deutsche DOS-Codepage
      ]
      
      encodings_to_try.each do |source_encoding|
        begin
          test_content = binary_content.dup.force_encoding(source_encoding)
          
          if source_encoding == 'UTF-8'
            next unless test_content.valid_encoding?
            return test_content
          else
            # Konvertiere zu UTF-8
            converted = test_content.encode('UTF-8', 
              invalid: :replace, 
              undef: :replace, 
              replace: '?'
            )
            
            # Teste ob deutsche Umlaute korrekt konvertiert wurden
            if converted.include?('Transaktionsübersicht') || 
               (converted.include?('Transaktions') && !converted.include?('Transaktions?'))
              puts "Erfolgreiche Konvertierung mit #{source_encoding}"
              return converted
            end
          end
          
        rescue => conversion_error
          puts "#{source_encoding} fehlgeschlagen: #{conversion_error.message}"
        end
      end
      
      # Letzter Fallback: Aggressive UTF-8 Reparatur
      #puts "Verwende aggressive UTF-8 Reparatur..."
      repaired = binary_content.force_encoding('UTF-8').scrub('?')
      return repaired
      
    rescue => e
      puts "Kritischer Fehler beim Dateileesen: #{e.message}"
      raise e
    end
  end

  # Erstellt eine neue HTML-Datei mit Transaktionen, die nicht in Excel vorkommen
  def create_filtered_html_file
    return nil if @latest_excel_file.nil? || @html_file_path.nil? || @nix_neues
    FileUtils.touch(@zeitstempel_datei)
    
    # Extrahiere Zeitstempel aus Excel-Dateinamen
    timestamp = extract_timestamp_from_filename(@latest_excel_file).gsub('_',':')
    
    # Belegnummern aus Excel extrahieren und zu numerischen Teilen konvertieren
    belegnummern = extract_belegnummer
    numeric_belegnummern = extract_numeric_parts(belegnummern)
    
    # HTML-Datei mit deutschem Encoding robust lesen
    #p @html_file_path
    #p system("ls -l #{@html_file_path}")
    
    html_content = robust_read_german_html(@html_file_path)
    #p html_content.length
    
    # Debug: Prüfe deutschen Titel
    #if title_match = html_content.match(/(Transaktions[^<]*)/i)
     # puts "Deutscher Titel gefunden: '#{title_match[1]}'"
     # puts "Titel-Encoding: #{title_match[1].encoding}"
    #end
    
    # Nokogiri mit deutschem UTF-8
    original_doc = Nokogiri::HTML(html_content, nil, 'UTF-8')
    
    # Erstelle ein neues HTML-Dokument mit UTF-8
    new_doc = Nokogiri::HTML::Document.new
    new_doc.encoding = 'UTF-8'
    
    html = Nokogiri::XML::Node.new('html', new_doc)
    head = Nokogiri::XML::Node.new('head', new_doc)
    body = Nokogiri::XML::Node.new('body', new_doc)
    new_doc.add_child(html)
    
    # Kopiere den Head-Inhalt
    original_doc.css('head > *').each do |node|
      head.add_child(node.dup)
    end
    
    # Debug: Zeige Head-Inhalt
    #puts "Head-Elemente gefunden: #{original_doc.css('head > *').length}"
    #original_doc.css('head > *').each_with_index do |node, index|
     # content_sample = node.content.length > 50 ? "#{node.content[0..50]}..." : node.content
     # puts "#{index}: #{node.name} - Content: #{content_sample}"
    #end
    
    # Setze den deutschen Titel
    if head.at('title')
      head.at('title').content = NEG
    else
      title = Nokogiri::XML::Node.new('title', new_doc)
      title.content = NEG
      head.add_child(title)
    end
    
    # Füge deutsche h3-Überschrift hinzu
    heading = Nokogiri::XML::Node.new('h3', new_doc)
    heading.content = "#{NBT}(Stand: #{timestamp})"
    body.add_child(Nokogiri::XML::Node.new('span', new_doc) do |node| 
      node.content = Time.now.strftime("%d.%m %H:%M")
      node['class'] = 'crtime'
    end)
    body.add_child(heading)
    
    # Alle Tabellenzeilen aus der Originaltabelle finden
    rows = original_doc.css('table > tbody > tr, table > tr').uniq
    puts "Tabellenzeilen gefunden: #{rows.count}"
    
    # Erstelle die neue Tabelle
    new_table = Nokogiri::XML::Node.new('table', new_doc)
    body.add_child(new_table)
    
    # Erstelle den benutzerdefinierten Tabellenkopf (deutsch)
    thead = Nokogiri::XML::Node.new('thead', new_doc)
    new_table.add_child(thead)
    
    header_row = Nokogiri::XML::Node.new('tr', new_doc)
    thead.add_child(header_row)
    
    # Deutsche Spaltenüberschriften
    ["Buchungsdatum", "Betrag", "Währung", "Zusatzinformationen", "Überweisungsinformationen", "Kd Nr", "Zahler/Empfänger"].each do |header|
      th = Nokogiri::XML::Node.new('th', new_doc)
      th.content = header
      header_row.add_child(th)
    end
    
    # Erstelle einen neuen Tabellenkörper
    tbody = Nokogiri::XML::Node.new('tbody', new_doc)
    new_table.add_child(tbody)
    
    # Zähle gefilterte Zeilen und verfolge bereits hinzugefügte Zeilen
    filtered_count = 0
    added_rows = Set.new
    
    # Durchlaufe alle Tabellenzeilen
    rows.each do |row|
      # Überspringe Kopfzeilen mit th-Elementen
      next if row.css('th').any?
      
      # Erzeuge einen eindeutigen Fingerabdruck für diese Zeile
      row_text = row.text.strip
      next if added_rows.include?(row_text)
      
      # Suche nach einer Rechnungsnummer in der Zeile
      rechnung_span = row.at('span.rechnung.copy')
      
      if rechnung_span.nil?
        # Zeile hat keine Rechnungsnummer -> aufnehmen
        tbody.add_child(row.dup)
        added_rows.add(row_text)
        filtered_count += 1
      else
        # Zeile hat eine Rechnungsnummer -> prüfen, ob sie in Excel vorkommt
        rnr = rechnung_span.text.gsub(/\D/, '')
        unless numeric_belegnummern.include?(rnr)
          # Rechnungsnummer ist nicht in Excel -> aufnehmen
          tbody.add_child(row.dup)
          added_rows.add(row_text)
          filtered_count += 1
        end
      end
    end
    
    # Aktualisiere die deutsche Überschrift
    heading.content = "#{NBT}(Stand: #{timestamp}) - #{filtered_count} Einträge"
    
    # Füge einen Trenner hinzu
    separator = Nokogiri::XML::Node.new('hr', new_doc)
    body.add_child(separator)
    
    # Erstelle eine zweite deutsche Überschrift für den originalen Inhalt
    original_heading = Nokogiri::XML::Node.new('h3', new_doc)
    original_heading.content = "Vollständige Gutschriftenliste (Original)"
    body.add_child(original_heading)
    
    # Füge den gesamten Inhalt des Body der originalen Datei am Ende hinzu
    original_doc.css('body > *').each do |node|
      body.add_child(node.dup)
    end
    html.add_child(head)
    html.add_child(body)
    
    # Speichere die neue HTML-Datei mit deutschem UTF-8 Encoding
    File.write(@output_file_path, new_doc.to_html, encoding: 'UTF-8')
    
    puts "Neue HTML-Datei erstellt: #{@output_file_path}"
    puts "Anzahl der gefilterten Zeilen: #{filtered_count}"
   # puts "Basierend auf Excel-Datei mit Zeitstempel: #{timestamp}"
   # puts "Originaler HTML-Inhalt wurde am Ende hinzugefügt"
    
    return @output_file_path
  end
end

# Beispielverwendung
if __FILE__ == $0
  processor = TransaktionenProcessor.new(
    PATH, # Aktuelles Verzeichnis nach Excel-Dateien durchsuchen
    "ka/transaktionen.html"
  )
  processor.create_filtered_html_file
end
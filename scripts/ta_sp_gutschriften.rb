# ta_sp_gutschriften.rb

require 'nokogiri'
require 'zip'
require 'date'
require 'set'
require_relative 'html_generator'
require_relative 'kunden_sucher'

PATH = '../kontoauszuge'
#FN = 'Kundenliste.csv'

class KontoauszugVerarbeiter
  attr_reader :transaktionen, :erste_xml_datei
  NAMESPACE = 'urn:iso:std:iso:20022:tech:xsd:camt.052.001.08'
  
  def initialize(verzeichnis)
    @verzeichnis = verzeichnis
    @transaktionen = []
    @erste_xml_datei = nil
    @juengster_zeitpunkt = nil
    @zeitstempel_datei = File.join(@verzeichnis, '.last_zip')
    @verarbeitete_transaktionen = Set.new # Zur Erkennung von Duplikaten
    @ks = CustomerSearcher.new(FN)
  end
  
  def neue_dateien_vorhanden?
    # Alle relevanten Dateien prüfen
    dateien = Dir.glob(File.join(@verzeichnis, "*.ZIP")) #+ 
              #Dir.glob(File.join(@verzeichnis, "*.xml"))
    
    if dateien.empty?
      puts "Keine Dateien zum Verarbeiten gefunden"
      return false
    end

    # Zeitstempel-Datei erstellen falls sie nicht existiert
    FileUtils.touch(@zeitstempel_datei) unless File.exist?(@zeitstempel_datei)
    
    p zeitstempel_mtime = File.mtime(@zeitstempel_datei)

    # Prüfe, ob es Dateien gibt, die neuer sind als die Zeitstempel-Datei
    neue_dateien = dateien.select do |datei|
      File.mtime(datei) > zeitstempel_mtime
    end

    if neue_dateien.any?
      puts "Neue Dateien gefunden:"
      # neue_dateien.each { |datei| puts "  - #{File.basename(datei)} (#{File.mtime(datei)})" }
      #puts "Letzte Verarbeitung: #{zeitstempel_mtime}"
      return true
    else
      puts "Keine neuen Dateien seit letzter Verarbeitung (#{zeitstempel_mtime})"
      return false
    end
  end

  def select_last_two_zip_files
    # Finde alle ZIP-Dateien mit dem passenden Pattern
    pattern = File.join(@verzeichnis, "*-*-*-camt52v8Booked.ZIP")
    filenames = Dir.glob(pattern).map { |path| File.basename(path) }
    
    return [] if filenames.empty?
    
    # Parse filenames zu Datumsbereichen
    files = filenames.map do |filename|
      dates = filename.match(/(\d{8})-(\d{8})/)
      next nil unless dates
      
      {
        filename: filename,
        start_date: Date.parse(dates[1]),
        end_date: Date.parse(dates[2])
      }
    end.compact
    
    return [] if files.empty?
    
    # Sortiere nach End-Datum (neueste zuerst)
    sorted_files = files.sort_by { |f| f[:end_date] }.reverse
    
    # Nimm die ersten 2 (jüngsten)
    selected_files = sorted_files.first(2)
    
    puts "Ausgewählte ZIP-Dateien (2 jüngste):"
    selected_files.each_with_index do |f, index|
      puts "  #{index + 1}. #{f[:filename]} (#{f[:start_date]} bis #{f[:end_date]})"
    end
    
    # Rückgabe der vollständigen Pfade
    selected_files.map { |f| File.join(@verzeichnis, f[:filename]) }
  end

  def dateien_verarbeiten
    return unless neue_dateien_vorhanden?
    # Zeitstempel aktualisieren
    FileUtils.touch(@zeitstempel_datei)

    # Die 2 jüngsten ZIP-Dateien auswählen
    selected_zip_files = select_last_two_zip_files
    
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

    
    # HTML-Bericht erstellen mit der neuen Klasse
    html = HTMLGenerator.erstelle_bericht(@transaktionen, @juengster_zeitpunkt)
    HTMLGenerator.speichere_bericht(html, @verzeichnis)
  end
  
  def zip_datei_verarbeiten(zip_datei)
    zip_dateiname = File.basename(zip_datei)
    
    Zip::File.open(zip_datei) do |zip|
      zip.each do |eintrag|
        next unless eintrag.name.end_with?('.xml')
        xml_inhalt = eintrag.get_input_stream.read
        doc = Nokogiri::XML(xml_inhalt)
        
        # Speichere die erste XML-Datei
        if @erste_xml_datei.nil?
          @erste_xml_datei = doc
        end
        
        # Extrahiere CreDtTm aus dem Dokument
        extrahiere_cre_dt_tm(doc)
        
        # Gutschriften mit XML-Dateiname und ZIP-Dateiname verarbeiten
        gutschriften_verarbeiten(doc, eintrag.name, zip_dateiname)
      end
    end
  end
  
  def xml_datei_verarbeiten(xml_datei)
    xml_inhalt = File.read(xml_datei)
    doc = Nokogiri::XML(xml_inhalt)
    
    # Speichere die erste XML-Datei
    if @erste_xml_datei.nil?
      @erste_xml_datei = doc
    end
    
    # Extrahiere CreDtTm aus dem Dokument
    extrahiere_cre_dt_tm(doc)
    
    # Gutschriften mit XML-Dateiname verarbeiten (kein ZIP)
    gutschriften_verarbeiten(doc, File.basename(xml_datei), nil)
  end
  
  def extrahiere_cre_dt_tm(doc)
    ns = { 'camt' => NAMESPACE }
    
    # CreDtTm aus dem Report-Element extrahieren
    cre_dt_tm_node = doc.at_xpath('//camt:Rpt/camt:CreDtTm', ns)
    
    if cre_dt_tm_node
      # ISO-Datumsformat in YYYY-MM-DD HH:MM umwandeln
      iso_time = cre_dt_tm_node.text
      
      # Einfache Umformung mit Regex
      if iso_time =~ /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}):\d{2}/
        formatted_time = "#{$1} #{$2}"
        
        # Prüfen, ob dieser Zeitpunkt jünger ist als der bisherige
        if @juengster_zeitpunkt.nil? || formatted_time > @juengster_zeitpunkt
          @juengster_zeitpunkt = formatted_time
        end
      end
    end
  end

  def ks_kdnr(str)
    results = @ks.search_by_words(str)
    results.any? ? results.first[:kdnr] : ' - - - '
  end
  
  def select_minimal_recent_files(months_back = 3)
    # Finde alle ZIP-Dateien mit dem passenden Pattern
    pattern = File.join(@verzeichnis, "*-*-*-camt52v8Booked.ZIP")
    filenames = Dir.glob(pattern).map { |path| File.basename(path) }
    
    return [] if filenames.empty?
    
    # Parse filenames zu Datumsbereichen
    files = filenames.map do |filename|
      dates = filename.match(/(\d{8})-(\d{8})/)
      next nil unless dates
      
      {
        filename: filename,
        start_date: Date.parse(dates[1]),
        end_date: Date.parse(dates[2])
      }
    end.compact
    
    return [] if files.empty?
    
    # Bestimme Stichtag (3 Monate zurück)
    cutoff_date = Date.today << months_back
    
    # Filtere Dateien: nur die, deren End-Datum nicht älter als cutoff_date ist
    recent_files = files.select { |f| f[:end_date] >= cutoff_date }
    
    return [] if recent_files.empty?
    
    # Bestimme den relevanten Zeitraum (ab cutoff_date bis zum spätesten Datum)
    start_range = [cutoff_date, recent_files.map { |f| f[:start_date] }.min].max
    end_range = recent_files.map { |f| f[:end_date] }.max
    
    puts "Relevanter Zeitraum: #{start_range} bis #{end_range}"
    
    # Sortiere nach Start-Datum, dann nach End-Datum (absteigend)
    recent_files.sort_by! { |f| [f[:start_date], -f[:end_date].to_time.to_i] }
    
    # Greedy-Algorithmus für minimale Abdeckung
    selected = []
    current_end = start_range
    
    i = 0
    while current_end < end_range && i < recent_files.length
      best_file = nil
      best_end = current_end
      
      # Finde die Datei die am weitesten reicht
      while i < recent_files.length && recent_files[i][:start_date] <= current_end
        if recent_files[i][:end_date] > best_end
          best_file = recent_files[i]
          best_end = recent_files[i][:end_date]
        end
        i += 1
      end
      
      break unless best_file
      
      selected << best_file[:filename]
      current_end = best_end
      
      # Setze i zurück um von der besten Datei weiterzumachen
      i = recent_files.index(best_file) + 1
    end
    
    puts "Ausgewählte Dateien (#{selected.length} von #{filenames.length}):"
    selected.each { |f| puts "  #{f}" }
    
    selected.map { |filename| File.join(@verzeichnis, filename) }
  end

# gutschriften_verarbeiten_clean.rb

def gutschriften_verarbeiten(doc, xml_dateiname = nil, zip_dateiname = nil)
  ns = { 'camt' => NAMESPACE }
  
  # Alle Transaktionseinträge finden
  entries = doc.xpath('//camt:Ntry', ns)
  
  entries.each do |entry|
    # Nur Gutschriften berücksichtigen (CdtDbtInd = 'CRDT')
    credit_debit_indicator = entry.at_xpath('./camt:CdtDbtInd', ns)&.text
    next unless credit_debit_indicator == 'CRDT'
    
    # Basis-Informationen extrahieren
    betrag = entry.at_xpath('./camt:Amt', ns)&.text
    waehrung = entry.at_xpath('./camt:Amt/@Ccy', ns)&.value || 'EUR'
    buchungsdatum = entry.at_xpath('./camt:BookgDt/camt:Dt', ns)&.text
    
    # Zusatzinformationen
    zusatzinfo = entry.at_xpath('./camt:AddtlNtryInf', ns)&.text || 'GUTSCHRIFT ÜBERWEISUNG'
    
    # Transaktionsdetails
    tx_details = entry.xpath('./camt:NtryDtls/camt:TxDtls', ns)
    
    if tx_details.any?
      tx_details.each do |tx|
        # Überweisungsinformationen
        ref_info = []
        
        # Verschiedene mögliche Referenzfelder sammeln
        refs = tx.xpath('.//camt:Refs/*', ns)
        refs.each do |ref|
          ref_text = ref.text.strip
          ref_info << ref_text unless ref_text.empty?
        end
        
        # Remittance Information (Zahlungsreferenz, Verwendungszweck)
        rmt_info = tx.xpath('.//camt:RmtInf//camt:Ustrd', ns).map(&:text).join(' ')
        ref_info << rmt_info unless rmt_info.empty?
        
        # Zahler/Empfänger - Angepasster Pfad
        zahler_empfaenger = tx.at_xpath('.//camt:UltmtDbtr/camt:Pty/camt:Nm', ns)&.text
        
        # Falls UltmtDbtr nicht gefunden, versuche Dbtr als Fallback
        if zahler_empfaenger.nil? || zahler_empfaenger.empty?
          zahler_empfaenger = tx.at_xpath('.//camt:Dbtr/camt:Pty/camt:Nm', ns)&.text
        end
        
        zahler_empfaenger ||= 'Unbekannt'
        # Adressinformationen - Angepasst
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
        
        # Vollständiger Zahler/Empfänger mit Adresse
        if addr_info.any?
          zahler_empfaenger = "#{zahler_empfaenger} #{addr_info.join(' ')}"
        end
        rueck_ueberweisung_info = tx.at_xpath('.//camt:Cdtr/camt:Pty/camt:Nm', ns)&.text
        rui = rueck_ueberweisung_info.match(/Transact/i) ? nil : rueck_ueberweisung_info

        transaktion = {
          buchungsdatum: buchungsdatum,
          betrag: betrag,
          waehrung: waehrung,
          zusatzinformationen: zusatzinfo,
          ueberweisungsinformationen: ref_info.join(' '),
          kdnr: ks_kdnr(zahler_empfaenger),
          zahler_empfaenger: zahler_empfaenger,
          rui: rui,
          xml_datei: xml_dateiname,
          zip_datei: zip_dateiname
        }
        
        # Transaktion direkt hinzufügen ohne Duplikatsprüfung
        @transaktionen << transaktion
      end
    else
      # Wenn keine Transaktionsdetails vorhanden sind
      zahler_empfaenger = entry.at_xpath('.//camt:UltmtDbtr/camt:Nm', ns)&.text || 'Unbekannt'
      
      # Adressinformationen
      addr_info = []
      pstl_code = entry.at_xpath(".//camt:UltmtDbtr/camt:PstlAdr/camt:PstCd", ns)&.text
      town = entry.at_xpath(".//camt:UltmtDbtr/camt:PstlAdr/camt:TwnNm", ns)&.text
      
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
      
      transaktion = {
        buchungsdatum: buchungsdatum,
        betrag: betrag,
        waehrung: waehrung,
        zusatzinformationen: zusatzinfo,
        ueberweisungsinformationen: '',
        kdnr: ks_kdnr(zahler_empfaenger),
        zahler_empfaenger: zahler_empfaenger,
        xml_datei: xml_dateiname,
        zip_datei: zip_dateiname
      }
      
      # Transaktion direkt hinzufügen ohne Duplikatsprüfung
      @transaktionen << transaktion
    end
   end
end

  def erstelle_datenfelder_tree(doc)
    ns = { 'camt' => NAMESPACE }
    
    # Ausgabedatei für den Datenfeld-Tree
    output_path = File.join(@verzeichnis, 'xml_struktur.txt')
    
    File.open(output_path, 'w') do |file|
      # Root-Element finden
      root = doc.root
      file.puts "XML-Struktur der ersten Datei:"
      file.puts "========================================="
      file.puts "Namespace: #{NAMESPACE}"
      file.puts "Root-Element: #{root.name}"
      file.puts "========================================="
      
      # Datenfeld-Tree rekursiv erstellen und in die Datei schreiben
      traverse_node(root, file, 0)
    end
    
    puts "Datenfeld-Tree erstellt: xml_struktur.txt"
  end
  
  def traverse_node(node, file, level)
    # Einrückung basierend auf der Verschachtelungsebene
    indent = "  " * level
    
    # Element-Name ausgeben
    element_info = "#{indent}+ #{node.name}"
    
    # Attribute ausgeben, falls vorhanden
    unless node.attributes.empty?
      attrs = node.attributes.map { |name, attr| "#{name}=\"#{attr.value}\"" }.join(", ")
      element_info += " [#{attrs}]"
    end
    
    # Text-Inhalt, falls vorhanden und nicht nur Leerzeichen
    if node.text? || (node.children.size == 1 && node.children.first.text?)
      text = node.text.strip
      element_info += " = \"#{text}\"" unless text.empty?
    end
    
    file.puts element_info
    
    # Unterelemente rekursiv durchlaufen
    node.element_children.each do |child|
      traverse_node(child, file, level + 1)
    end
  end
end

if __FILE__ == $0
 verarbeiter = KontoauszugVerarbeiter.new(PATH)
 verarbeiter.dateien_verarbeiten
end
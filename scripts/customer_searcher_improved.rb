require 'csv'

FN = 'Kundenliste.csv'

class CustomerSearcher
  def initialize(csv_file_path)
    @csv_file_path = csv_file_path
    @customers = []
    @kdnr_column = nil
    load_customers
  end

  # Sucht Kunden nach teilweiser Übereinstimmung in Name1 (case-insensitive)
  def search(partial_name)
    matches = @customers.select { |row| 
      row['Name1'] && name_matches?(row['Name1'], partial_name)
    }
    matches.map { |customer| 
      { 
        kdnr: customer[@kdnr_column], 
        name: customer['Name1'],
        kurzname: customer['Kurzname'],
        status: customer['Status']
      } 
    }
  end

  # Erweiterte Suche mit verschiedenen Strategien
  def search_flexible(partial_name)
    strategies = [
      method(:exact_substring_match),
      method(:normalized_match),
      method(:word_based_match),
      method(:abbreviation_match)
    ]
    
    strategies.each do |strategy|
      matches = @customers.select { |row| 
        row['Name1'] && strategy.call(row['Name1'], partial_name)
      }
      
      unless matches.empty?
        puts "Gefunden mit: #{strategy.name.to_s.gsub('_', ' ')}"
        return matches.map { |customer| 
          { 
            kdnr: customer[@kdnr_column], 
            name: customer['Name1'],
            kurzname: customer['Kurzname'],
            status: customer['Status']
          } 
        }
      end
    end
    
    []  # Nichts gefunden
  end

  # Gibt alle geladenen Kunden zurück
  def all_customers
    @customers
  end

  # Gibt die Anzahl der geladenen Kunden zurück
  def customer_count
    @customers.length
  end

  # Debug-Methode: Zeigt alle verfügbaren Spalten an
  def show_headers
    return [] if @customers.empty?
    @customers.first.headers
  end

  # Debug-Methode: Zeigt ersten Kunden mit allen Feldern an
  def show_sample_customer
    return {} if @customers.empty?
    @customers.first.to_h
  end

  private

  def load_customers
    begin
      # CSV-Inhalt einlesen und BOM entfernen
      content = File.read(@csv_file_path, encoding: 'UTF-8')
      content = content.gsub(/\A\uFEFF/, '') # UTF-8 BOM entfernen
      
      @customers = CSV.parse(content,
                           headers: true, 
                           col_sep: ';', 
                           quote_char: '"',
                           skip_blanks: true)
      
      # Automatische Erkennung der KdNr-Spalte
      #detect_kdnr_column
      
      #puts "#{@customers.length} Kunden erfolgreich geladen."
      #puts "Verfügbare Spalten: #{show_headers.join(', ')}"
      #puts "KdNr-Spalte erkannt als: '#{@kdnr_column}'"
    rescue => e
      puts "Fehler beim Laden der CSV-Datei: #{e.message}"
      @customers = []
    end
  end

  def detect_kdnr_column
    return if @customers.empty?
    
    headers = @customers.first.headers
    
    # Suche nach verschiedenen möglichen Schreibweisen der Kundennummer
    possible_kdnr_columns = ['KdNr', 'Kdnr', 'KDNR', 'Kundennummer', 'KundenNr', 
                             'Kunden-Nr', 'Customer-Nr', 'CustomerNr', 'ID', 'Nr']
    
    @kdnr_column = possible_kdnr_columns.find { |col| headers.include?(col) }
    
    # Falls nichts gefunden wurde, nimm die erste Spalte die "nr" oder "id" enthält
    if @kdnr_column.nil?
      @kdnr_column = headers.find { |header| 
        header.downcase.include?('nr') || header.downcase.include?('id') 
      }
    end
    
    # Falls immer noch nichts gefunden wurde, nimm die erste Spalte
    @kdnr_column ||= headers.first
  end

  # Einfache Teilstring-Suche (original)
  def name_matches?(customer_name, search_term)
    customer_name.downcase.include?(search_term.downcase)
  end

  # Verschiedene Suchstrategien
  def exact_substring_match(customer_name, search_term)
    customer_name.downcase.include?(search_term.downcase)
  end

  def normalized_match(customer_name, search_term)
    normalize_string(customer_name).include?(normalize_string(search_term))
  end

  def word_based_match(customer_name, search_term)
    customer_words = normalize_string(customer_name).split(/\s+/)
    search_words = normalize_string(search_term).split(/\s+/)
    
    # Mindestens 70% der Suchworte müssen gefunden werden
    matches = search_words.count { |search_word|
      customer_words.any? { |customer_word| 
        customer_word.include?(search_word) || search_word.include?(customer_word)
      }
    }
    
    matches.to_f / search_words.length >= 0.7
  end

  def abbreviation_match(customer_name, search_term)
    # Häufige Abkürzungen
    abbreviations = {
      'gmbh' => ['gemeinnutzige gmbh', 'gesellschaft mit beschrankter haftung'],
      'ggmbh' => ['gemeinnutzige gmbh'],
      'ag' => ['aktiengesellschaft'],
      'kg' => ['kommanditgesellschaft'],
      'ohg' => ['offene handelsgesellschaft'],
      'ev' => ['eingetragener verein'],
      'eg' => ['eingetragene genossenschaft']
    }
    
    norm_customer = normalize_string(customer_name)
    norm_search = normalize_string(search_term)
    
    # Abkürzungen in beide Richtungen ersetzen
    abbreviations.each do |abbr, expansions|
      expansions.each do |expansion|
        norm_customer_expanded = norm_customer.gsub(abbr, expansion)
        norm_search_expanded = norm_search.gsub(abbr, expansion)
        
        return true if norm_customer_expanded.include?(norm_search) ||
                      norm_customer.include?(norm_search_expanded) ||
                      norm_customer_expanded.include?(norm_search_expanded)
      end
    end
    
    false
  end

  def normalize_string(str)
    str.downcase
       .gsub(/[äöüß]/, 'ä' => 'ae', 'ö' => 'oe', 'ü' => 'ue', 'ß' => 'ss')
       .gsub(/[^\w\s]/, ' ')  # Sonderzeichen durch Leerzeichen ersetzen
       .squeeze(' ')          # Mehrfache Leerzeichen reduzieren
       .strip
  end
end

# Beispiel für die Verwendung:
if __FILE__ == $0
  exit unless ARGV.count >= 1
  
  searcher = CustomerSearcher.new(FN)
  search_term = ARGV[0]
  flexible = ARGV[1] == '--flexible' || ARGV[1] == '-f'
  
  # Debug-Information ausgeben (nur wenn -v flag gesetzt)
  if ARGV.include?('-v') || ARGV.include?('--verbose')
    puts "\nDebug-Information:"
    puts "Verfügbare Spalten: #{searcher.show_headers}"
    puts "Beispiel-Kunde: #{searcher.show_sample_customer}"
  end
  
  # Suche durchführen
  results = if flexible
             puts "Verwende flexible Suche..."
             searcher.search_flexible(search_term)
           else
             searcher.search(search_term)
           end
  
  if results.any?
    puts "\nGefundene Kunden:"
    results.each do |customer|
      puts "  KdNr: #{customer[:kdnr]} - #{customer[:name]} (#{customer[:status]})"
    end
    
    # Zeige auch Details des ersten Ergebnisses
    puts "\nDetails des ersten Ergebnisses:"
    puts results.first
  else
    puts "\nKeine Kunden gefunden."
    unless flexible
      puts "Tipp: Versuche es mit flexibler Suche: ruby #{$0} '#{search_term}' --flexible"
    end
  end
  
  puts "\nVerwendung:"
  puts "  ruby #{$0} 'suchbegriff'              # Normale Suche"
  puts "  ruby #{$0} 'suchbegriff' --flexible   # Flexible Suche"
  puts "  ruby #{$0} 'suchbegriff' -v           # Mit Debug-Info"
end
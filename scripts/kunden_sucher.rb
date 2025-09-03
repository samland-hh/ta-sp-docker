require 'csv'

FN = 'Kundenliste.csv'

class CustomerSearcher
  def initialize(csv_file_path)
    @csv_file_path = csv_file_path
    @customers = []
    load_customers
  end

  # Sucht Kunden nach teilweiser Übereinstimmung in Name1 (case-insensitive)
  def search(partial_name)
    matches = @customers.select { |row| 
      row['Name1'] && row['Name1'].downcase.include?(partial_name.downcase) 
    }
    matches.map { |customer| 
      { 
        kdnr: customer['KdNr'], 
        name: customer['Name1'],
        kurzname: customer['Kurzname'],
        status: customer['Status']
      } 
    }
  end

  # Erweiterte Suche mit Wort-basiertem Scoring
  def search_by_words(search_string, min_score: 1)
    return [] if search_string.nil? || search_string.strip.empty?
    
    # Suchworte aufteilen und normalisieren
    search_words = normalize_words(search_string)
    return [] if search_words.empty?
    
    # Alle Kunden durchsuchen und bewerten
    scored_customers = @customers.map do |customer|
      next nil unless customer['Name1']
      
      customer_words = normalize_words(customer['Name1'])
      score = calculate_word_score(search_words, customer_words)
      #p customer['Status']
      score += customer['Status'] == 'aktiv' ? 20 : 0
      
      if score >= min_score
        {
          kdnr: customer['KdNr'],
          name: customer['Name1'],
          kurzname: customer['Kurzname'],
          status: customer['Status'],
          score: score,
          matched_words: find_matched_words(search_words, customer_words)
        }
      end
    end.compact
    
    # Nach Score sortieren (höchster zuerst)
    scored_customers.sort_by { |customer| -customer[:score] }
  end

  # Gibt alle geladenen Kunden zurück
  def all_customers
    @customers
  end

  # Gibt die Anzahl der geladenen Kunden zurück
  def customer_count
    @customers.length
  end

  private

  def load_customers
    begin
      content = File.read(@csv_file_path, encoding: 'UTF-8')
      content = content.gsub(/\A\uFEFF/, '') # UTF-8 BOM entfernen
      
      @customers = CSV.parse(content,
                           headers: true, 
                           col_sep: ';', 
                           quote_char: '"',
                           skip_blanks: true)
    rescue => e
      puts "Fehler beim Laden der CSV-Datei: #{e.message}"
      @customers = []
    end
  end

  # Normalisiert Wörter: lowercase, Umlaute ersetzen, Sonderzeichen entfernen
  def normalize_words(text)
    return [] unless text
    
    # Umlaute und Sonderzeichen normalisieren
    normalized = text.downcase
                     .gsub('ä', 'ae')
                     .gsub('ö', 'oe') 
                     .gsub('ü', 'ue')
                     .gsub('ß', 'ss')
                     .gsub(/[^\w\s]/, ' ')  # Sonderzeichen durch Leerzeichen ersetzen
    
    # In Wörter aufteilen und leere entfernen
    normalized.split(/\s+/).reject(&:empty?)
  end

  # Berechnet Score basierend auf gefundenen Wörtern
  def calculate_word_score(search_words, customer_words)
    return 0 if search_words.empty? || customer_words.empty?
    
    score = 0
    matched_search_words = 0
    
    search_words.each do |search_word|
      best_match_score = 0
      
      customer_words.each do |customer_word|
        match_score = calculate_match_score(search_word, customer_word)
        best_match_score = [best_match_score, match_score].max
      end
      
      if best_match_score > 0
        score += best_match_score
        matched_search_words += 1
      end
    end
    
    # Bonus für mehr gefundene Suchworte (Vollständigkeit)
    completeness_bonus = (matched_search_words.to_f / search_words.length * 5).round
    score += completeness_bonus
    
    score
  end

  # Berechnet den Score für ein einzelnes Wortpaar
  def calculate_match_score(search_word, customer_word)
    return 0 if search_word.length < 2 || customer_word.length < 2
    
    # Exakte Übereinstimmung
    if search_word == customer_word
      return 10
    end
    
    # Einer ist im anderen enthalten
    if customer_word.include?(search_word)
      length_ratio = search_word.length.to_f / customer_word.length
      return (6 * length_ratio).round + 2
    elsif search_word.include?(customer_word)
      length_ratio = customer_word.length.to_f / search_word.length  
      return (6 * length_ratio).round + 2
    end
    
    # Ähnlichkeit mit einfacher Levenshtein-ähnlicher Bewertung
    similarity_score = calculate_similarity(search_word, customer_word)
    if similarity_score >= 0.8
      return 8  # Sehr ähnlich (z.B. "munchen" vs "muenchen")
    elsif similarity_score >= 0.6
      return 6  # Ziemlich ähnlich
    elsif similarity_score >= 0.4
      return 4  # Etwas ähnlich
    end
    
    # Gemeinsamer Anfang (für kürzere Wörter)
    min_length = [search_word.length, customer_word.length].min
    if min_length >= 3
      common_start = 0
      min_length.times do |i|
        if search_word[i] == customer_word[i]
          common_start += 1
        else
          break
        end
      end
      
      if common_start >= 3
        ratio = common_start.to_f / min_length
        return (4 * ratio).round
      end
    end
    
    0
  end

  # Berechnet Ähnlichkeit zwischen zwei Wörtern (0.0 - 1.0)
  def calculate_similarity(word1, word2)
    return 1.0 if word1 == word2
    return 0.0 if word1.empty? || word2.empty?
    
    # Zu große Längenunterschiede = keine Ähnlichkeit
    length_diff = (word1.length - word2.length).abs
    max_length = [word1.length, word2.length].max
    
    return 0.0 if length_diff > max_length * 0.4  # Mehr als 40% Längenunterschied
    
    # Levenshtein-ähnliche Distanz mit strikteren Regeln
    distance = levenshtein_distance(word1, word2)
    max_distance = [word1.length, word2.length].max
    
    # Ähnlichkeit basierend auf Editier-Distanz
    similarity = 1.0 - (distance.to_f / max_distance)
    
    # Mindest-Ähnlichkeit: 60% für kurze Wörter, 70% für längere
    min_similarity = word1.length <= 4 ? 0.7 : 0.6
    
    similarity >= min_similarity ? similarity : 0.0
  end

  # Einfache Levenshtein-Distanz Implementierung
  def levenshtein_distance(str1, str2)
    return str2.length if str1.empty?
    return str1.length if str2.empty?
    
    # Matrix für dynamische Programmierung
    matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1, 0) }
    
    # Initialisierung der ersten Zeile und Spalte
    (0..str1.length).each { |i| matrix[i][0] = i }
    (0..str2.length).each { |j| matrix[0][j] = j }
    
    # Matrix füllen
    (1..str1.length).each do |i|
      (1..str2.length).each do |j|
        cost = str1[i-1] == str2[j-1] ? 0 : 1
        
        matrix[i][j] = [
          matrix[i-1][j] + 1,     # Löschung
          matrix[i][j-1] + 1,     # Einfügung
          matrix[i-1][j-1] + cost # Ersetzung
        ].min
      end
    end
    
    matrix[str1.length][str2.length]
  end

  # Zählt die Anzahl der übereinstimmenden Wörter
  def count_matched_words(search_words, customer_words)
    matched = 0
    search_words.each do |search_word|
      customer_words.each do |customer_word|
        if customer_word.include?(search_word) || search_word.include?(customer_word)
          matched += 1
          break  # Jedes Suchwort nur einmal zählen
        end
      end
    end
    matched
  end

  # Findet die übereinstimmenden Wörter für die Anzeige
  def find_matched_words(search_words, customer_words)
    matched = []
    search_words.each do |search_word|
      best_match = nil
      best_score = 0
      
      customer_words.each do |customer_word|
        score = calculate_match_score(search_word, customer_word)
        if score > best_score
          best_score = score
          best_match = customer_word
        end
      end
      
      if best_match && best_score > 0
        match_type = case best_score
                    when 10
                      "="
                    when 8..9
                      "≈≈"
                    when 6..7
                      "≈"
                    when 4..5
                      "~"
                    else
                      "?"
                    end
        matched << "#{search_word} #{match_type} #{best_match} (#{best_score})"
      end
    end
    matched
  end
end

# Beispiel für die Verwendung:
if __FILE__ == $0
  exit unless ARGV.count >= 1
  
  searcher = CustomerSearcher.new(FN)
  search_term = ARGV.join(' ')
  
  puts "=== Erweiterte Suche nach: '#{search_term}' ==="
  
  # Erweiterte Suche mit Wort-basiertem Scoring
  results = searcher.search_by_words(search_term)
  
  if results.any?
    puts "Gefundene Kunden (sortiert nach Relevanz):"
    results.each_with_index do |customer, index|
      break if index > 5
      puts "\n#{index + 1}. Score: #{customer[:score]}"
      puts "   KdNr: #{customer[:kdnr]} - #{customer[:name]} (#{customer[:status]})"
      puts "   Kurzname: #{customer[:kurzname]}"
      puts "   Matches: #{customer[:matched_words].join(', ')}" if customer[:matched_words].any?
    end
  else
    puts "Keine Kunden gefunden."
    
    # Fallback: Originale Suche probieren
    puts "\n=== Fallback: Originale Suche ==="
    original_results = searcher.search(search_term)
    if original_results.any?
      puts "Gefundene Kunden (originale Suche):"
      original_results.each do |customer|
        puts "  KdNr: #{customer[:kdnr]} - #{customer[:name]} (#{customer[:status]})"
      end
    else
      puts "Auch mit originaler Suche keine Kunden gefunden."
    end
  end
  
  puts "\nGesamt #{searcher.customer_count} Kunden geladen."
end
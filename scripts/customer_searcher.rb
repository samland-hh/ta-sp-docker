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
end

# Beispiel für die Verwendung:
if __FILE__ == $0
  exit unless ARGV.count == 1
  # Beispiel-Verwendung
  searcher = CustomerSearcher.new(FN)
  
  # Suche nach 'patio'
  results = searcher.search(ARGV[0])
  
  if results.any?
    puts "Gefundene Kunden:"
    results.each do |customer|
      puts "  KdNr: #{customer[:kdnr]} - #{customer[:name]} (#{customer[:status]})"
      p customer
    end
  else
    puts "Keine Kunden gefunden."
  end
  
end
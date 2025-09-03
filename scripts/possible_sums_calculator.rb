#!/usr/bin/env ruby

class SummenFinder
  attr_reader :betraege, :moegliche_summen
  
  def initialize(betraege)
    @betraege = betraege.dup
    @moegliche_summen = []
    berechne_alle_summen
  end
  
  # Berechnet alle möglichen Summen mit mindestens 2 Summanden
  def berechne_alle_summen
    @moegliche_summen = []
    
    # Für jede mögliche Kombination (ohne einzelne Summanden)
    (1...(2**@betraege.length)).each do |i|
      kombination = []
      summe = 0.0
      
      # Prüfen, welche Zahlen in dieser Kombination enthalten sind
      @betraege.each_with_index do |betrag, index|
        if (i & (1 << index)) != 0
          kombination << betrag
          summe += betrag
        end
      end
      
      # Nur Kombinationen mit 2 oder mehr Summanden hinzufügen
      if kombination.length >= 2
        @moegliche_summen << {
          kombination: kombination.dup,
          summe: summe,
          anzahl: kombination.length
        }
      end
    end
    
    # Nach Summe sortieren
    @moegliche_summen.sort_by! { |k| k[:summe] }
  end
  
  # Findet die Summe, die der Zielsumme am nächsten liegt
  def finde_naechste_summe(zielsumme)
    return nil if @moegliche_summen.empty?
    
    naechste = @moegliche_summen.min_by do |summen_info|
      (summen_info[:summe] - zielsumme).abs
    end
    
    {
      summe: naechste[:summe],
      kombination: naechste[:kombination],
      anzahl_summanden: naechste[:anzahl],
      differenz: zielsumme - naechste[:summe] ,
      abs_differenz: (zielsumme - naechste[:summe]).abs
    }
  end
  
  # Zeigt Details über die gefundene nächste Summe
  def zeige_naechste_summe(zielsumme)
    ergebnis = finde_naechste_summe(zielsumme)
    
    if ergebnis.nil?
      puts "Keine Summen verfügbar!"
      return
    end
    
    puts "Zielsumme: #{sprintf('%.2f', zielsumme)}"
    puts "Nächstliegende Summe: #{sprintf('%.2f', ergebnis[:summe])}"
    puts "Kombination: #{ergebnis[:kombination].map { |b| sprintf('%.2f', b) }.join(' + ')}"
    puts "Anzahl Summanden: #{ergebnis[:anzahl_summanden]}"
    puts "Differenz: #{sprintf('%.2f', ergebnis[:differenz])}"
    #puts "Absolute Differenz: #{sprintf('%.2f', ergebnis[:abs_differenz])}"
  end
  
  # Zeigt alle verfügbaren Summen
  def zeige_alle_summen
    puts "Alle möglichen Summen (#{@moegliche_summen.length} Kombinationen):"
    puts "="*60
    
    @moegliche_summen.each_with_index do |summen_info, index|
      puts sprintf("%2d. %s = %.2f", 
                   index + 1,
                   summen_info[:kombination].map { |b| sprintf('%.2f', b) }.join(' + '),
                   summen_info[:summe])
    end
  end
  
  # Statistiken über die Summen
  def statistiken
    return if @moegliche_summen.empty?
    
    puts "STATISTIKEN:"
    puts "="*30
    puts "Anzahl möglicher Summen: #{@moegliche_summen.length}"
    puts "Kleinste Summe: #{sprintf('%.2f', @moegliche_summen.first[:summe])}"
    puts "Größte Summe: #{sprintf('%.2f', @moegliche_summen.last[:summe])}"
    puts "Gesamtsumme aller Beträge: #{sprintf('%.2f', @betraege.sum)}"
    
    # Summen nach Anzahl Summanden
    puts "\nSummen nach Anzahl der Summanden:"
    (2..@betraege.length).each do |anzahl|
      summen = @moegliche_summen.select { |k| k[:anzahl] == anzahl }
                              .map { |k| k[:summe] }
      
      if summen.any?
        puts "#{anzahl} Summanden: #{summen.length} Kombinationen"
      end
    end
  end
end

# Beispiel-Verwendung:
if __FILE__ == $0
  # Deine ursprünglichen Beträge
  betraege = [4278.94, 18926.65, 401.63, 3564.05, 3564.05]
  
  # SummenFinder erstellen
  finder = SummenFinder.new(betraege)
  finder.zeige_naechste_summe(ARGV[0].to_f)
  return
  puts "Ursprüngliche Beträge:"
  betraege.each_with_index do |betrag, index|
    puts "#{index + 1}. #{sprintf('%.2f', betrag)}"
  end
  
  puts "\n"
  finder.statistiken
  
  puts "\n" + "="*60
  puts "BEISPIELE FÜR NÄCHSTE SUMMEN:"
  puts "="*60
  
  # Beispiele für verschiedene Zielsummen
  zielsummen = [5000, 10000, 15000, 20000, 25000]
  
  zielsummen.each do |ziel|
    puts "\n"
    finder.zeige_naechste_summe(ziel)
    puts "-" * 40
  end
  
  puts "\nUm alle Summen zu sehen, rufe finder.zeige_alle_summen auf"
end
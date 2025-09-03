require_relative 'ta_sp_gutschriften'    # KontoauszugVerarbeiter laden
require_relative 'bericht_ersteller'     # Dann BerichtErsteller laden
require_relative 'nicht_vorhandene_gutschriften'

cmd = "touch #{PATH}/.alive"  # 
system cmd
# Alle Berichte erstellen
ersteller = BerichtErsteller.new(PATH)
ersteller.erstelle_alle_berichte
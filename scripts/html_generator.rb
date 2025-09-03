# html_generator.rb
# Klasse zur Erstellung von HTML-Berichten aus Transaktionsdaten

class HTMLGenerator
  def self.format_german_date(date_string)
    # Von "2025-05-07" zu "07.05.2025"
    date = Date.parse(date_string)
    date.strftime("%d.%m.%Y")
  rescue
    date_string # Fallback bei ungültigem Datum
  end
  
  def self.erstelle_bericht(transaktionen, titel)
    # Suchfunktion nur für transaktionen.html hinzufügen
    search_functionality = titel.include?("Gesamtliste") || titel.downcase.include?("transaktionen")
    
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>#{titel}</title>
        <style>
          body { 
            font-family: Arial, sans-serif; font-size: .85em;
            margin: 20px; 
            background-color: #b2e2b2; /* Hellgrauer Hintergrund statt weiß */
          }
          h3 { margin-bottom: 20px; color: darkblue; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
          td:nth-child(2), td:nth-child(6) { text-align: right; } /* Betragsspalte (2. Spalte) rechtsbündig */
          th { background-color: #f2f2f2; cursor: pointer; }
          th:hover { background-color: #e2e2e2; }
          tr:nth-child(even) { background-color: #a7d688; }

          .rechnung { background-color: #FFEB3B; font-weight: bold; padding: 2px 4px; border-radius: 3px; cursor: pointer; }
          .betrag { background-color: #347237; color: white; font-weight: bold; padding: 2px 4px; border-radius: 3px; cursor: pointer; }
          .highlighted-row { background-color: #9da6c9 !important; } /* Hervorgehobene Zeile */
          .crtime {font-size: .7em;} 
          .rui {font-size: .8em; background: #D771B9; padding: .3em; }
          .header-row {
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 10px;
          }
          
          .poppy-link { color: white; background-color: #007bff; text-decoration: none; font-weight: bold;
            padding: 8px 16px; border-radius: 5px; font-size: 14px; }
        
          .poppy-link:hover { background-color: #0056b3; text-decoration: underline; }
          
          #{search_functionality ? search_css : ''}
        </style>
      </head>
      <body>
        <div class="header-row">
          <span class="crtime">#{Time.now.strftime("%d.%m %H:%M")}</span>
          <a target='_blank' href="http://192.168.73.10/letsrock/pages/opos.php" class="poppy-link">Poppy</a>
        </div>
        <h3>#{titel} (#{transaktionen.length} Einträge)</h3>
        #{search_functionality ? search_html : ''}
        <table>
          <thead>
            <tr>
              <th>Buchungsdatum</th>
              <th>Betrag</th>
              <th>Währung</th>
              <th>Zusatzinformationen</th>
              <th>Überweisungsinformationen</th>
              <th>Kd Nr</th>
              <th>Zahler</th>
            </tr>
          </thead>
          <tbody>
    HTML
    
    transaktionen.each do |transaktion|
      # Prüfe, ob "erstattung" in Überweisungsinformationen vorkommt (case-insensitive)
      if transaktion[:ueberweisungsinformationen].downcase.include?('erstatt')
        next  # Überspringe diese Transaktion
      end
      #überweisunginfo bereinigen, nur  die rechnungs infos alles was vor FI-UMSATZ und direkt danach kann weg  
      mtch = transaktion[:ueberweisungsinformationen].match(/FI-UMSATZ.*?\s(.*)/)
      uinfo_pur = mtch ? mtch[1] :  transaktion[:ueberweisungsinformationen]
      
      # Rechnungsnummern im Format 2XXXXXXXX hervorheben (z.B. 202500219)
      ueberweisungsinformationen = uinfo_pur.gsub(/(202\d{6})/) do |rechnungsnr|
        "<span class=\"rechnung copy\">#{rechnungsnr}</span>"
      end
      
      # Beträge in Überweisungsinformationen hervorheben
      ueberweisungsinformationen = ueberweisungsinformationen.gsub(/(?<!\d\.)(?<!\d-)(?<!\d:)(?<!\d\/)\b(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}|\d+\.\d{2})(?!\.\d|\-\d|\:\d|\/\d)\b/) do |betrag|
        "<span class=\"betrag copy\">#{betrag}</span>"
      end
      
      # Betrag in der Betragsspalte auch mit der Klasse "betrag copy" formatieren
      formatierter_betrag = "<span class=\"betrag copy\">#{transaktion[:betrag]}</span>"
      zahler = transaktion[:zahler_empfaenger]
      zahler += "<br><span class=\"rui\">#{transaktion[:rui]}</span>" unless transaktion[:rui].nil?
      zusatzinfos = transaktion[:zusatzinformationen]
      zusatzinfos = "<span class=\"rui\">#{zusatzinfos}</span>" if zusatzinfos.match(/RÜCKÜBERWEISUNG/i)

      html += <<~HTML
        <tr class="transaction-row">
          <td class='copy'>#{format_german_date(transaktion[:buchungsdatum])}</td>
          <td>#{formatierter_betrag}</td>
          <td>#{transaktion[:waehrung]}</td>
          <td>#{zusatzinfos}</td>
          <td>#{ueberweisungsinformationen}</td>
          <td class='copy'>#{transaktion[:kdnr]}</td>
          <td>#{zahler}</td>
        </tr>
      HTML
    end
    
    html += <<~HTML
          </tbody>
        </table>
      
      <script>
      #{search_functionality ? search_javascript : ''}
      
      function fallbackCopyTextToClipboard(text) {
        var textArea = document.createElement("textarea");
        textArea.value = text;
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();

        try {
          var successful = document.execCommand('copy');
          var msg = successful ? 'successful' : 'unsuccessful';
          console.log('Fallback: Copying text command was ' + msg);
        } catch (err) {
          console.error('Fallback: Oops, unable to copy', err);
        }

        document.body.removeChild(textArea);
      }

      function copyTextToClipboard(text) {
        if (!navigator.clipboard) {
          fallbackCopyTextToClipboard(text);
          return;
        }
        navigator.clipboard.writeText(text).then(function() {
          console.log('Async: Copying to clipboard was successful!');
        }, function(err) {
          console.error('Async: Could not copy text: ', err);
        });
      }

      // Header-Klick für sichtbare Tabellen-Zeilen kopieren
      document.querySelector('table thead').addEventListener('click', function(event) {
        const table = this.closest('table');
        
        // Kopiere nur sichtbare Zeilen
        const visibleTableHtml = createVisibleTableHtml(table);
        copyTextToClipboard(visibleTableHtml);
        
        // Feedback
        this.style.backgroundColor = '#a2297e';
        setTimeout(() => {
          this.style.backgroundColor = '';
        }, 400);
        
        event.stopPropagation();
      });
      
      // Erstelle HTML nur mit sichtbaren Zeilen
      function createVisibleTableHtml(originalTable) {
        const newTable = originalTable.cloneNode(false); // Nur table-Element, ohne Inhalt
        const thead = originalTable.querySelector('thead').cloneNode(true);
        const tbody = document.createElement('tbody');
        
        // Füge Kopfzeile hinzu
        newTable.appendChild(thead);
        
        // Füge nur sichtbare Zeilen hinzu
        const visibleRows = originalTable.querySelectorAll('tbody .transaction-row:not(.hidden-row)');
        visibleRows.forEach(row => {
          tbody.appendChild(row.cloneNode(true));
        });
        
        newTable.appendChild(tbody);
        
        // Erstelle komplette HTML-Struktur mit Styles
        const html = `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="UTF-8">
          <style>
            body { font-family: Arial, sans-serif; font-size: .85em; margin: 20px; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            td:nth-child(2), td:nth-child(6) { text-align: right; }
            th { background-color: #f2f2f2; }
            tr:nth-child(even) { background-color: #f9f9f9; }
            .rechnung { background-color: #FFEB3B; font-weight: bold; padding: 2px 4px; border-radius: 3px; }
            .betrag { background-color: #347237; color: white; font-weight: bold; padding: 2px 4px; border-radius: 3px; }
            .rui { font-size: .8em; background: #D771B9; padding: .3em; }
          </style>
        </head>
        <body>
          <h3>Gefilterte Transaktionen (${visibleRows.length} Einträge)</h3>
          ${newTable.outerHTML}
        </body>
        </html>`;
        
        return html;
      }

      document.querySelectorAll('.copy').forEach(codeBlock => {
        codeBlock.addEventListener('click', function(event) {
          const codeText = this.innerText;
          copyTextToClipboard(codeText);
          
          // Farbänderung für Klick-Feedback
          this.style.backgroundColor = '#a2297e';  // Lila Farbe als Feedback
          setTimeout(() => {
            this.style.backgroundColor = '';
          }, 400);
          
          // Finde übergeordnete Zeile und markiere sie
          const parentRow = this.closest('tr');
          if (parentRow) {
            // Entferne Hervorhebung von allen Zeilen
            document.querySelectorAll('tr').forEach(row => {
              row.classList.remove('highlighted-row');
            });
            
            // Hebe die aktuelle Zeile hervor
            parentRow.classList.add('highlighted-row');
          }
          
          // Verhindern, dass das Event zum Elternelement weitergeleitet wird
          event.stopPropagation();
        });
      });
      </script>
      </body>
      </html>
    HTML
    
    return html
  end
  
  def self.search_css
    <<~CSS
      .search-container {
        background-color: #f8f9fa;
        border: 1px solid #ddd;
        border-radius: 5px;
        padding: 15px;
        margin-bottom: 20px;
      }
      
      .search-row {
        display: flex;
        gap: 10px;
        align-items: center;
        margin-bottom: 10px;
        flex-wrap: wrap;
      }
      
      .search-field {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }
      
      .search-field label {
        font-size: 0.8em;
        font-weight: bold;
        color: #555;
      }
      
      .search-field input {
        padding: 6px 8px;
        border: 1px solid #ccc;
        border-radius: 3px;
        font-size: 0.9em;
        width: 120px;
      }
      
      .search-buttons {
        display: flex;
        gap: 5px;
        align-items: flex-end;
      }
      
      .search-btn {
        background-color: #007bff;
        color: white;
        border: none;
        padding: 8px 12px;
        border-radius: 3px;
        cursor: pointer;
        font-size: 0.9em;
      }
      
      .search-btn:hover {
        background-color: #0056b3;
      }
      
      .clear-btn {
        background-color: #6c757d;
      }
      
      .clear-btn:hover {
        background-color: #545b62;
      }
      
      .search-stats {
        font-size: 0.8em;
        color: #666;
        margin-top: 8px;
      }
      
      .hidden-row {
        display: none !important;
      }
      
      .match-highlight {
        background-color: #ffeb3b !important;
        font-weight: bold;
      }
    CSS
  end
  
  def self.search_html
    <<~HTML
      <div class="search-container">
        <div class="search-row">
          <div class="search-field">
            <label>KdNr:</label>
            <input type="text" id="search-kdnr" placeholder="12345">
          </div>
          <div class="search-field">
            <label>Zahler:</label>
            <input type="text" id="search-zahler" placeholder="Name">
          </div>
          <div class="search-field">
            <label>Datum:</label>
            <input type="text" id="search-datum" placeholder="dd.mm.yyyy">
          </div>
          <div class="search-field">
            <label>Betrag:</label>
            <input type="text" id="search-betrag" placeholder="123,45">
          </div>
          <div class="search-buttons">
            <button class="search-btn" onclick="performSearch()">Suchen</button>
            <button class="search-btn clear-btn" onclick="clearSearch()">Zurücksetzen</button>
          </div>
        </div>
        <div class="search-stats" id="search-stats">
          Alle Transaktionen werden angezeigt
        </div>
      </div>
    HTML
  end
  
  def self.search_javascript
    <<~JAVASCRIPT
      function performSearch() {
        const searchKdnr = document.getElementById('search-kdnr').value.trim().toLowerCase();
        const searchZahler = document.getElementById('search-zahler').value.trim().toLowerCase();
        const searchDatum = document.getElementById('search-datum').value.trim();
        const searchBetrag = document.getElementById('search-betrag').value.trim().toLowerCase();
        
        const rows = document.querySelectorAll('tbody .transaction-row');
        let visibleCount = 0;
        let totalCount = rows.length;
        
        rows.forEach(row => {
          const cells = row.querySelectorAll('td');
          if (cells.length < 7) return;
          
          const buchungsdatum = cells[0].textContent.trim();
          const betrag = cells[1].textContent.trim().toLowerCase();
          const kdnr = cells[5].textContent.trim().toLowerCase();
          const zahler = cells[6].textContent.trim().toLowerCase();
          
          let matches = true;
          
          // KdNr Suche
          if (searchKdnr && !kdnr.includes(searchKdnr)) {
            matches = false;
          }
          
          // Zahler Suche
          if (searchZahler && !zahler.includes(searchZahler)) {
            matches = false;
          }
          
          // Datum Suche
          if (searchDatum && !buchungsdatum.includes(searchDatum)) {
            matches = false;
          }
          
          // Betrag Suche
          if (searchBetrag && !betrag.includes(searchBetrag)) {
            matches = false;
          }
          
          if (matches) {
            row.classList.remove('hidden-row');
            visibleCount++;
            
            // Highlight matching terms
            highlightMatches(cells[0], searchDatum);
            highlightMatches(cells[1], searchBetrag);
            highlightMatches(cells[5], searchKdnr);
            highlightMatches(cells[6], searchZahler);
          } else {
            row.classList.add('hidden-row');
            
            // Remove highlights
            removeHighlights(cells[0]);
            removeHighlights(cells[1]);
            removeHighlights(cells[5]);
            removeHighlights(cells[6]);
          }
        });
        
        // Update stats
        const statsElement = document.getElementById('search-stats');
        if (visibleCount === totalCount) {
          statsElement.textContent = `Alle ${totalCount} Transaktionen werden angezeigt`;
        } else {
          statsElement.textContent = `${visibleCount} von ${totalCount} Transaktionen werden angezeigt`;
        }
      }
      
      function highlightMatches(cell, searchTerm) {
        if (!searchTerm || searchTerm === '') return;
        
        const originalHTML = cell.getAttribute('data-original-html') || cell.innerHTML;
        cell.setAttribute('data-original-html', originalHTML);
        
        const text = cell.textContent.toLowerCase();
        const searchLower = searchTerm.toLowerCase();
        
        if (text.includes(searchLower)) {
          cell.classList.add('match-highlight');
        }
      }
      
      function removeHighlights(cell) {
        const originalHTML = cell.getAttribute('data-original-html');
        if (originalHTML) {
          cell.innerHTML = originalHTML;
          cell.removeAttribute('data-original-html');
        }
        cell.classList.remove('match-highlight');
      }
      
      function clearSearch() {
        document.getElementById('search-kdnr').value = '';
        document.getElementById('search-zahler').value = '';
        document.getElementById('search-datum').value = '';
        document.getElementById('search-betrag').value = '';
        
        const rows = document.querySelectorAll('tbody .transaction-row');
        rows.forEach(row => {
          row.classList.remove('hidden-row');
          const cells = row.querySelectorAll('td');
          cells.forEach(cell => {
            removeHighlights(cell);
          });
        });
        
        document.getElementById('search-stats').textContent = `Alle ${rows.length} Transaktionen werden angezeigt`;
      }
      
      // Enable search on Enter key
      ['search-kdnr', 'search-zahler', 'search-datum', 'search-betrag'].forEach(id => {
        document.getElementById(id).addEventListener('keypress', function(e) {
          if (e.key === 'Enter') {
            performSearch();
          }
        });
      });
      
      // Enable real-time search
      ['search-kdnr', 'search-zahler', 'search-datum', 'search-betrag'].forEach(id => {
        document.getElementById(id).addEventListener('input', function() {
          performSearch();
        });
      });
    JAVASCRIPT
  end
  
  def self.speichere_bericht(html, verzeichnis, dateiname = 'bericht.html')
    output_path = File.join(verzeichnis, dateiname)
    File.write(output_path, html)
    puts "Bericht erstellt: #{output_path}"
  end
end
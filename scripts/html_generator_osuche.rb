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
        </style>
      </head>
      <body>
        <div class="header-row">
          <span class="crtime">#{Time.now.strftime("%d.%m %H:%M")}</span>
          <a target='_blank' href="http://192.168.73.10/letsrock/pages/opos.php" class="poppy-link">Poppy</a>
        </div>
        <h3>#{titel} (#{transaktionen.length} Einträge)</h3>
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
        <tr>
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

      // Header-Klick für Tabellen-HTML kopieren
      document.querySelector('table thead').addEventListener('click', function(event) {
        const table = this.closest('table');
        const tableHtml = table.outerHTML;
        copyTextToClipboard(tableHtml);
        
        // Feedback
        this.style.backgroundColor = '#a2297e';
        setTimeout(() => {
          this.style.backgroundColor = '';
        }, 400);
        
        event.stopPropagation();
      });

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
  
  def self.speichere_bericht(html, verzeichnis, dateiname = 'bericht.html')
    output_path = File.join(verzeichnis, dateiname)
    File.write(output_path, html)
    puts "Bericht erstellt: #{output_path}"
  end
end
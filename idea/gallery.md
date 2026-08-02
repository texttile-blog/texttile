# Interface-Anforderungen für den CMS-Prototyp

## 1. Galerie-Seitenleiste

- Responsive Kachelraster.
- Überschrift zeigt die Anzahl der Bilder.
- Jede Kachel zeigt:
    - Vorschaubild
    - laufende Positionsnummer
    - Aufnahmedatum
    - optional Dateiname
- Eine `Add`-Kachel öffnet die Mehrfachauswahl.
- Desktop unterstützt Datei-Drop auf die Galerie.
- Neue Dateien erscheinen sofort als lokale Upload-Kacheln.
- Die sichtbare Reihenfolge entspricht der später veröffentlichten Galerie.

## 2. Upload-Zustände

Eine Upload-Kachel zeigt:

- lokale Vorschau
- Dateiname
- Fortschrittsbalken
- Fortschritt in Prozent
- aktuellen Status
- verfügbare Aktionen

Darzustellende Zustände:

- `queued`
- `uploading`
- `processing`
- `complete`
- `failed`
- `cancelled`

Verfügbare Aktionen:

- `cancel` während des Uploads
- `retry` bei einem Fehler
- `remove` bei einem Fehler

Mehrere Uploads stehen sichtbar in einer Queue. Ein fehlerhafter Upload darf die folgenden Uploads nicht blockieren.

Für den Prototyp können Upload, Fortschritt, Processing und Fehler per Timer simuliert werden.

## 3. Sortierung über ein gespeichertes Datum

Jedes Bild besitzt ein Feld `gallery_date`.

Initialwert:

- EXIF-Aufnahmedatum, falls vorhanden
- ansonsten Upload-Zeitpunkt

Anforderungen:

- `gallery_date` wird separat in der CMS-Datenbank gespeichert.
- Die Originaldatei und ihre EXIF-Daten werden nicht verändert.
- Die Galerie sortiert aufsteigend nach `gallery_date`.
- Bei identischem Datum wird zusätzlich nach einer stabilen Asset-ID sortiert.
- Das gespeicherte Datum ist in der Kachel sichtbar.
- Das Datum ist auch in der Lightbox sichtbar.
- Das Datum kann über einen Date-Time-Picker bearbeitet werden.
- Änderungen aktualisieren die Reihenfolge sofort.
- Die neue Reihenfolge wird zunächst optimistisch angezeigt.
- Bei einem simulierten Speicherfehler wird die vorherige Reihenfolge wiederhergestellt.

## 4. Drag-and-drop-Sortierung

Drag-and-drop verändert ebenfalls ausschließlich `gallery_date`.

### Desktop

- Das Bild wird direkt angefasst und gezogen.
- Es gibt kein separates Drag-Icon.
- Während des Ziehens wird die Kachel visuell hervorgehoben.
- Die neue Zielposition wird sofort im Raster dargestellt.
- Nach dem Loslassen wird ein neuer `gallery_date`-Wert gespeichert.

### Mobile

- Das Bild wird kurz gehalten und anschließend gezogen.
- Ein kurzer Tap öffnet weiterhin die Lightbox.
- Vertikales Wischen scrollt weiterhin die Seite.
- Beim Ziehen nahe dem oberen oder unteren Bildschirmrand scrollt die Galerie automatisch.

### Datumsberechnung

Beim Verschieben zwischen zwei Bildern:

- Neuer Wert ist der zeitliche Mittelpunkt zwischen den beiden Nachbarn.

Beim Verschieben an den Anfang:

- Neuer Wert liegt vor dem bisherigen ersten Bild.

Beim Verschieben ans Ende:

- Neuer Wert liegt nach dem bisherigen letzten Bild.

Falls zwischen zwei Werten kein ausreichender Abstand mehr existiert:

- Die `gallery_date`-Werte der Galerie werden kontrolliert neu verteilt.
- Die sichtbare Reihenfolge bleibt unverändert.

## 5. Alternative Sortieraktionen

Zusätzlich zu Drag-and-drop kann jede Kachel anbieten:

- nach vorne verschieben
- nach hinten verschieben
- Datum bearbeiten

Diese Aktionen ändern ebenfalls nur `gallery_date`.

Buttons innerhalb der Kachel dürfen keine Drag-Geste starten.

## 6. Lightbox

Ein kurzer Klick oder Tap auf eine fertige Kachel öffnet eine Vollbild-Lightbox.

Die Lightbox zeigt:

- große Bildvorschau
- Dateiname
- `gallery_date`
- aktuelle Position
- Gesamtzahl der Bilder
- Aktion `open original`
- sichtbaren Schließen-Button

Navigation:

- vorheriges Bild
- nächstes Bild
- Pfeiltasten auf Desktop
- horizontaler Swipe auf Mobile
- zyklische Navigation am Anfang und Ende
- Schließen über Escape

Zustände:

- Ladeanzeige
- Bildanzeige
- verständliche Fehlermeldung
- bereits gecachte Bilder erscheinen sofort

## 7. Stabilität der Lightbox

Die Lightbox bleibt geöffnet bei:

- simuliertem Upload-Fortschritt
- abgeschlossenem Processing
- neu hinzugefügten Bildern
- Autosave
- Änderungen im Texteditor
- Änderungen an anderen Bildern
- Sortieränderungen

Dabei bleiben erhalten:

- aktuell angezeigtes Bild
- Navigationsposition
- geladene Vorschau
- Swipe-Zustand

Verspätete Bildantworten dürfen eine bereits geschlossene Lightbox nicht erneut öffnen.

## 8. Bildmetadaten bearbeiten

Pro Bild können bearbeitet werden:

- `gallery_date`
- Dateiname oder redaktioneller Anzeigename
- Alt-Text
- Bildunterschrift

Anforderungen:

- Bearbeitung erfolgt direkt aus der Kachel oder einem kompakten Dialog.
- Änderungen werden ohne vollständigen Seitenreload sichtbar.
- Ein geöffnetes Formular bleibt bei Hintergrundupdates geöffnet.
- Speichern und Abbrechen sind klar unterscheidbar.
- Die Originaldatei wird durch Metadatenänderungen nicht verändert.

Für den ersten Prototyp ist nur die Bearbeitung von `gallery_date` zwingend erforderlich.

## 9. Löschen mit Undo

- Löschen verlangt eine Bestätigung.
- Die Kachel verschwindet sofort aus der Galerie.
- Für zehn Sekunden erscheint eine Undo-Aktion.
- Undo stellt das Bild an seiner vorherigen Position wieder her.
- Nach Ablauf der Zeit gilt die Löschung als endgültig.
- Die Scrollposition bleibt beim Löschen unverändert.
- Die Galerie springt nicht an den Anfang.

Für den Prototyp wird die Löschung nur lokal simuliert.

## 10. Verhalten im CMS-Editor

- Uploads laufen sichtbar weiter, während Text bearbeitet wird.
- Die Galerie funktioniert unabhängig vom Texteditor.
- Autosave setzt keine Galerie-Zustände zurück.
- Editoränderungen schließen die Lightbox nicht.
- Editoränderungen brechen keine Drag-Geste ab.
- Neue Bilder erscheinen ohne vollständigen Seitenreload.
- Processing- und Fehlerzustände erscheinen nur im Editor.
- Die veröffentlichte Vorschau zeigt nur fertige Bilder.
- Die veröffentlichte Reihenfolge folgt `gallery_date`.

## 11. Optimistische Änderungen

Folgende Aktionen reagieren sofort im Interface:

- Bild hinzufügen
- Bild sortieren
- Datum ändern
- Bild löschen
- Löschung rückgängig machen

Das Interface wartet nicht sichtbar auf den simulierten Server.

Während des Speicherns kann ein dezenter Zustand angezeigt werden:

- `saving`
- `saved`
- `failed`

Bei einem Fehler:

- vorheriger Zustand wird wiederhergestellt
- verständliche Fehlermeldung erscheint
- erneutes Speichern ist möglich

## 12. Für den Prototyp ausreichend

Der Prototyp benötigt keine echte Upload- oder Storage-Infrastruktur.

Ausreichend sind:

- Bilder lokal über den Dateiauswahldialog laden
- lokale Object-URLs als Vorschauen verwenden
- Upload-Fortschritt per Timer simulieren
- Processing per Timer simulieren
- Fehlerzustand manuell auslösbar machen
- Bilder und Metadaten im Browserzustand speichern
- `gallery_date` lokal persistent simulieren
- Sortierung aus `gallery_date` berechnen
- Drag-and-drop vollständig interaktiv umsetzen
- Lightbox vollständig interaktiv umsetzen
- Löschen und Undo lokal simulieren
- Autosave-Updates simulieren, ohne die Galerie zurückzusetzen

## 13. Abnahmekriterien

1. Mehrere Bilder können über `Add` ausgewählt werden.
2. Dateien können auf Desktop in die Galerie gezogen werden.
3. Neue Dateien erscheinen sofort als Upload-Kacheln.
4. Upload und Processing werden sichtbar simuliert.
5. Ein Upload kann abgebrochen werden.
6. Ein fehlgeschlagener Upload kann erneut gestartet werden.
7. Fertige Bilder erscheinen automatisch im Raster.
8. Jedes Bild besitzt ein gespeichertes `gallery_date`.
9. Die Galerie sortiert nach `gallery_date`.
10. Das Datum kann direkt bearbeitet werden.
11. Desktop-Sortierung funktioniert über die gesamte Bildfläche.
12. Mobile-Sortierung funktioniert durch kurzes Halten und Ziehen.
13. Drag-and-drop berechnet einen neuen `gallery_date`-Wert.
14. Die Original-EXIF-Daten werden nicht verändert.
15. Ein kurzer Tap öffnet die Lightbox.
16. Die Lightbox zeigt Dateiname und Datum.
17. Die Lightbox bleibt bei simulierten Hintergrundupdates geöffnet.
18. Löschen verändert die Scrollposition nicht.
19. Undo stellt das Bild an der richtigen Position wieder her.
20. Die veröffentlichte Vorschau verwendet dieselbe datumsbasierte Reihenfolge.
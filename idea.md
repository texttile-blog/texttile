https://claude.ai/share/b8bb1068-ca01-4a36-ba75-36ce5f171c24


Triage:
- 

Werte
- Datensparsam - im frontend. Für Remote Locations. Keine Unemgen an Javascript. 
- Multiplayer editing.
- Minimal - nur dem Zweck dienlich. Ist erst gut wenn man nichts mehr weglassen kann. 

Coding: 
- Testgetrieben von Anfang an: evtl zwei Arten von Tests. Dinge die er selber schreibt und basierend auf prompts anpasst. Und welche die von mir definiert werden die nie ohne mein prompt failen dürfen. -> workflows 
- Workflows anschauen und verstehen. Inkl testing und Review. Claude Code is good video. Von Theo. 


Aufbau: 
- Titel 
- Text (guter Markdown editor, aber mit Bilder einfügen wie in Github)
- Tiles (Genau 1 Gallery)
- Tags
- Datum / Published Status
	- scheduled als dritter status. zukunftsdatum = geplant, mail an subscriber erst beim go-live.
	- publish zweistufig: button öffnet sheet mit slug, datum, notify. mobil als bottom sheet.
- Page oder Blogeintrag (option)
- notify subscribers on publihs
- allow comments
- slug
- Ein Log - wer was gemacht hat. 

Ediitor: 
- schriftart ist die selbe des themes
- wo Änderungen in Echtzeit an die anderen übertragen werden. inkl. der reihenfolge der bilder in den galerien! zwei cursors, wenn möglich. 
- genauso änderungen an den optionen. tags, settings, etc. 
- Text bekommt ein _weiches Dokument-Lock_, die Galerie bleibt für beide gleichzeitig offen. Das ist keine Notlösung, sondern architektonisch ehrlich: Der konfliktreiche Teil wird serialisiert, der konfliktarme bleibt frei. Und dein Hero-Feature – zwei Leute schieben live Kacheln – bleibt voll erhalten. [[live-editing]]
- Damit sich das trotzdem nach Multiplayer anfühlt, statt nach Warteschlange: Der Nicht-Editor sieht den Text **live mitlaufen** (read-only via PubSub, das ist trivial), sieht wer gerade schreibt, und kann mit einem Klick übernehmen. "Ich sehe dich schreiben und kann jederzeit dran" ist bei _zwei_ Leuten sozial fast so gut wie echtes Co-Editing – ihr redet ja ohnehin miteinander.
- und wenn der nicht-editor reinklickt wird das vom anderen übernommen. vorher kommt nochmal eine confirm bestätigung, dass man jetzt den anderen rauskickt. der andere bekommt eine nachricht, dass er rausgekcikt wurde.
- Die Upload Experience wie bei imaedge. Nur das mit dem teilweise hochladen lassen wir erst mal raus und man muss Dragon drop die Bilder bewegen können auch auf Mobil und die Reihenfolge ändert aber nicht  Den time Stamp. Aber das mit dem lokalen cachen und weitermachen auf jeden Fall und das mit dem Live Update der anderen auch auf jeden Fall
- editor zeigt last saved (temp) - trotzdem einen save button um eine version zu speichern.
- dann brauchen wir noch eine versoinierung. save erzeugt ja eine neue version.
  wo sieht man die alten versionen? (eigener tab würde ich sagen, mit diff) versionierung NUR für den haupt-text.

Admins / login
- Login mit Nutzername und Passwort
- in der config hinterlegt man den username des ersten admins (nicht passwort)
- beim ersten login muss jemand sein passwort vergeben
- eigene profil kann man sein passwort und email und angezeigter name ändern. 

topbar
- wordmark dropdown ganz links. 
	- new text 1
	- texts 2
	- comments 3
	- newsletter 7
	- stats 8
	- settings 9
	- view site 0
	- here now (wer live ist, auf welchen seiten die person ist)
	- kb (sektion mit meinem namen) -> your profile und sign out. 
- gegebenenfalls breadcrump mit / für artikelname (wenn man bearbeitet) oder auuf stats / comments / texts ist. 
- ganz rechts: mein eigenes profil  als chip (klaus).  in nicht-akzent farbe. wenn man draufklickt landet man auf seinem profil. 
- links daneben: die anderen player. mit hover wird angezeigt was der player gerade macht. wenn man mehrere tabs offen hat als nutzer, werden diese alle angezeigt. z.b ist auf: texts übersicht, ist in dem text, ist in settings, etc. und man kann direkt dahin verlinkt werden

bottom bar: mit den key shortcuts. 

Frontend:
- suche in der Textliste (titel, tags, volltext). / springt rein.
- Passwortschutz (inkl. weiterleitung zurück wenn man auf einen artikel kam)
- Alle Pages kommen automatisch ins menü, sortiert nach VÖ-Datum. 
- Radikal auf Platz optimiert. Vor allem mobile. Kein schnick schnack. 
- die gallery ist im frontend auch quadratische tiles mit lightbox oder Für die Galerie entweder stile wie bei V01 oder dass alles wirklich teils sind wie in einer iPhone Galerie bei der Saturn-Nachteile. Man darf dabei auch nicht vergessen, das macht man mit dem Beitragsbild, dass das auch in verschiedenen Formaten funktioniert. Hier kann ich mir solches wie in der Galerie ganz gut vorstellen, dass es einfach eine maximale Höhe hat, damit man es trotzdem gut lesen kann.


Settings
- Settings: Ob nutzer ihre email bestätigen müssen bevor sie ein kommentar schreiben können. 
- theming nur über ein css theme. 
- Settings: einen about block. der auch komplett markdown rendered. 
- Settings: welche page die startseite sein soll. oder ob eine liste von letzten artikeln. 
- Settings: Title + Tagline. 
- Settings: Sprache einstellen. 
- Settings: Passwörter der admins ändern. von jedem. es gibt kein berechtigungssystem, das feiner einschränkt. das ist für gleichbestimmte. 
- Settings: Bild-Größen umrechnen. es gibt ein setting für max längere kante. das wird geschaut beim ausgeben. und wenn es noch kein cached gibt, dann wird sie on the fly erstellt. und davor andere größen gelöscht, damit wir keine alten zu lange cachen. 
- Settings: email-bestätigung vor kommentaren an/aus. unbestätigte kommentare sind markiert bis link geklickt.
- Settings: logo + favicon hochladen. default ist das texttile logo. für beides.
-   bei den settings gibts kein save. aalles wird instant gespeichert. und oben ist ein: last saved.

Kommentare
- Kommentare Schreiben - optional via email bestätigen. ansonsten 
- Kommentare Verwalten als Admin
- Kommentare ohne approve.  mit basic [[spamschutz]]

Newsletter
- Newsletter wer informiert werden soll, wenn neuer Artikeld a ist
- Die Möglichkeit sich selbst auf den Newsletter zu setzen im frontend. Ohne Bestätigung. 
- In den mails mit neuen Artikeln  das Passwort rein falls es eines gibt. 

Architektur
- Admins bei der Installation abfragen und hashed speichern.
- Bilder lokal ablegen in einem ordner, inkl. cachte varianten
- sqlite. 
- so bauen das die unterschiedlichen menü einträge unterschiedliche module sind, dass die jemand auch erweitern kann um was eigenes? 
- wie architektured man das für das elixir ökosystem? mehr so ein alles in 1 docker image wie + datenbank zum selbstaufsetzen oder als hex paket?  -> [[architektur]]
- Für mich selbst bei fly hosten - das evtl. Auch als separates Open Source Projekt anbieten. One line Hosting aufsetzen. 
- https://world.hey.com/dhh/once-again-3e99f755 mal im Hinterkopf behalten
- Mailversand: Texttile liest beim Start eine MAIL_ADAPTER-Variable und lädt je nach Wahl (smtp, resend, postmark, brevo, ses) genau die passenden Credential-Variablen über Swoosh – mit Local-Vorschau als Fallback, wenn nichts konfiguriert is

Harte Konfiguration
- Ordner wo die bilder liegen
- Ordner / Datei wo sqlite liegt. 

Später:
- Themes oder einen anderen Namen geben, damit man sie später auseinanderhalten kann, falls die schon jemand anderes benutzt
- Videos. Selbst hosten. Konvertieren. Genauso. ffmpeg im docker. -threads 1, nice -n 19 oder os. 
-   kommentare später: delete, edit, hide
- Statistiken
- Live-Edits 
- Import: Ich brauche ein sauberes Input Format. Inkl Bildern als Links die dann importiert werden und Kommentaren. Gut dokumentiert dass jede ai da einen importer schreiben kann Key Shortcuts! STarke idee. 
- Hosting anbieten über die homepage - blogname.texttiles.blog
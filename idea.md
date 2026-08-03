https://claude.ai/share/b8bb1068-ca01-4a36-ba75-36ce5f171c24

Werte
- Datensparsam - im frontend. Für Remote Locations. Keine Unemgen an Javascript. 
- Multiplayer editing.
- Minimal - nur dem Zweck dienlich. Ist erst gut wenn man nichts mehr weglassen kann. 

Triage:
- finales logo mit finalem theme. 

Später:
- Themes oder einen anderen Namen geben, damit man sie später auseinanderhalten kann, falls die schon jemand anderes benutzt
- Videos. Selbst hosten. Konvertieren. Genauso. ffmpeg im docker. -threads 1, nice -n 19 oder os. 
-   kommentare später: delete, edit, hide
- Statistiken
- Live-Edits 
- Import: Ich brauche ein sauberes Input Format. Inkl Bildern als Links die dann importiert werden und Kommentaren. Gut dokumentiert dass jede ai da einen importer schreiben kann Key Shortcuts! STarke idee. 
- Hosting anbieten über die homepage - blogname.texttiles.blog


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
	- publish ist ein klick. slug, datum und die subscriber-option leben permanent in den text-settings, nicht in einem sheet. ein zukunftsdatum im feld macht aus dem klick eine planung. der button ganz rechts trägt danach den zustand: published bzw. scheduled, mit chevron-menü für unpublish, publish now und unschedule.
- Page oder Blogeintrag (option)
- notify subscribers on publihs
- allow comments
- slug
- Ein Log - wer was gemacht hat. 

Ediitor: 
- markdown editor. 
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

Settings
- Settings: Ob nutzer ihre email bestätigen müssen bevor sie ein kommentar schreiben können. 
- theming nur über ein css theme. 
- Settings: einen about block. der auch komplett markdown rendered. 
- Settings: welche page die startseite sein soll. oder ob eine liste von letzten artikeln. 
- Settings: Title + Tagline. 
- Settings: Sprache einstellen. 
- utzer-verwaltung, bewusst simpel: alle sind admins, gleichberechtigt, kein rollensystem.
- eue nutzer anlegen mit username + email. die person setzt ihr passwort beim ersten login selbst (gleicher flow wie beim ersten admin aus der config).
- passwort zurücksetzen: schickt der person eine mail mit link, darüber setzt sie selbst ein neues. niemand tippt fremde passwörter.
- nutzer löschen. geht nur, solange mindestens ein admin übrig bleibt.
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


Frontend:
- suche in der Textliste (titel, tags, volltext). / springt rein.
- Passwortschutz (inkl. weiterleitung zurück wenn man auf einen artikel kam)
- das site-passwort wird im klartext gespeichert, nicht gehasht. es ist ein geteiltes zugangswort, kein login: es steht in den benachrichtigungsmails und man gibt es weiter. gilt für den ganzen blog, nicht pro artikel. der artikel-schalter sagt nur, ob dieser text hinter dem site-passwort liegt.
- Alle Pages kommen automatisch ins menü, sortiert nach VÖ-Datum. 
- Radikal auf Platz optimiert. Vor allem mobile. Kein schnick schnack. 
- die gallery ist im frontend auch quadratische tiles mit lightbox oder Für die Galerie entweder stile wie bei V01 oder dass alles wirklich teils sind wie in einer iPhone Galerie bei der Saturn-Nachteile. Man darf dabei auch nicht vergessen, das macht man mit dem Beitragsbild, dass das auch in verschiedenen Formaten funktioniert. Hier kann ich mir solches wie in der Galerie ganz gut vorstellen, dass es einfach eine maximale Höhe hat, damit man es trotzdem gut lesen kann.
- top menu: Home (wenn separate seite) - ansonsten Blog  und dann die ganzen anderen pages. 








## done 


Admins / login
- Login mit Nutzername und Passwort
- erster login ohne admin? admin nutzer erstellen mit passwort. 
- **Zeitfenster**: Setup nur innerhalb von z.B. 30 Minuten nach dem Start möglich, danach Neustart nötig. Portainer macht das so. Kostet nichts und schließt das Fenster hart.
- Im eigenen Profil kann man seinen login namen, Passwort und seine E-Mail und seinen angezeigten Namen ändern. 
- login namen müssen eindeutig sein.

▎ Profil
▎ - jeder user hat ein eigenes profil, erreichbar über die topbar (kb-sektion im wordmark-dropdown).
- login-name ändern (muss eindeutig sein)
- bestätigungs-email, dass man sich hier registriert auf blogname hat mit nutzernamen (ohne passwort)
▎ - angezeigter name änderbar.  leerer name fällt auf den username zurück. (kein check auf eindueitkgiet)
▎ - email änderbar. (eindeutig sein)
▎ - eigenes passwort direkt neu setzen  - mit bestätigung des aktuellen
▎ - liste der eigenen offenen sessions ("this browser", weitere tabs).
▎ - sign out.
▎ - alles instant gespeichert, oben ein last saved.


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

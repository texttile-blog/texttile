aber die variante mit sqlite - wie macht man da backups, wie persitiert man das?

Orchestrierte SQLite-Persistierungsstrategien und Backup-Lösungen

Orchestrierte SQLite-Persistierungsstrategien und Backup-Lösungen

Das ist bei SQLite tatsächlich der Punkt, den man einmal richtig verstehen muss – danach ist es simpler als jedes Postgres-Setup. Zwei Themen: Persistenz und Backup.

**Persistenz: ein Volume, fertig**

Die Datenbank ist eine Datei. Im Container legst du sie auf ein gemountetes Volume, z.B. `/data/cuvee.db`, und startest mit `docker run -v cuvee_data:/data ...`. Damit übersteht sie Container-Neustarts und Image-Updates. Wichtig dabei: SQLite im WAL-Modus betreiben (`PRAGMA journal_mode=WAL` – bei `ecto_sqlite3` konfigurierbar), das ist bei Webapps Standard, weil Leser und Schreiber sich dann nicht blockieren. Praktische Konsequenz: Neben `cuvee.db` liegen dann auch `cuvee.db-wal` und `cuvee.db-shm` – die gehören zur Datenbank dazu, das ganze Verzeichnis ist die Einheit, nicht die einzelne Datei.

Und nicht vergessen: Bei Cuvée sind die **Bilder** mindestens so wichtig wie die Datenbank. Die Uploads gehören auf dasselbe Volume (z.B. `/data/uploads/`), dann ist `/data` der eine Ort, der das ganze System enthält. Das ist konzeptionell sehr schön: _ein Verzeichnis = deine komplette Installation_.

**Backup: die eine Regel und drei Wege**

Die eine Regel: Niemals einfach die DB-Datei mit `cp` wegkopieren, während die App läuft – bei einem Schreibvorgang mittendrin bekommst du eine korrupte Kopie. Stattdessen:

_Weg 1 – der eingebaute:_ SQLite kann konsistente Backups im laufenden Betrieb, entweder per `sqlite3 /data/cuvee.db ".backup /data/backup/cuvee-$(date +%F).db"` oder per SQL `VACUUM INTO 'pfad'`. Das per Cron nachts laufen lassen und die Backup-Datei irgendwohin schieben (rsync, S3, Hetzner Storage Box) – für ein Zwei-Personen-Blog völlig ausreichend. Charmant in Elixir: Du brauchst nicht mal Cron, ein simpler GenServer mit `Process.send_after` oder ein Oban-Job kann das `VACUUM INTO` direkt über Ecto ausführen.

_Weg 2 – der elegante:_ **Litestream.** Das ist ein kleines Go-Tool, das kontinuierlich das WAL abgreift und nach S3 (oder kompatibel: Backblaze B2, Hetzner, MinIO) streamt. Du bekommst quasi Point-in-Time-Recovery – bei einem Totalausfall stellst du mit einem Befehl den Stand von vor Sekunden wieder her. Läuft als zweiter Prozess im Container oder als Sidecar, kostet fast nichts (B2: Cent-Beträge/Monat). Das ist der Grund, warum das "SQLite in Produktion"-Lager in den letzten Jahren so gewachsen ist.

_Weg 3 – der pragmatische:_ Wenn der Host ohnehin gesichert wird (VPS-Snapshots, Borg/Restic aufs Volume), reicht das _fast_ – mit der Einschränkung, dass ein Snapshot mitten im Schreibvorgang theoretisch inkonsistent sein kann. WAL-Modus macht das unwahrscheinlich problematisch, aber sauberer ist: Cron erzeugt erst per `.backup` eine konsistente Kopie, und _die_ wandert ins normale Backup.

**Meine Empfehlung für Cuvée:** Litestream für die Datenbank + ein nächtlicher rclone/restic-Sync des Upload-Ordners zum selben S3-Bucket. Das kannst du sogar als optionales Feature ins Produkt einbauen – drei Env-Variablen (`BACKUP_S3_BUCKET`, Key, Secret) und Cuvée sichert sich selbst. Für ein Self-Hosting-Tool wäre das ein echtes Verkaufsargument, weil Backup genau das ist, was Selbsthoster chronisch verschieben.

Die Restore-Geschichte ist dann übrigens herrlich unspektakulär: neues Volume, Litestream-Restore ausführen, Uploads zurücksyncen, Container starten. Kein `pg_restore`, keine Versionskonflikte, keine Rollen und Rechte – es ist halt eine Datei.

ah, man macht also ein vps wo docker läuft. (wegen der updates). aber bilder und sqlite werden lokal gespeichert. dass man sie jederzeit backuppen kann.

macht 37signals das mit ihren once produkten auch so die man selbst hosten kann?

Verifizierte 37signals-Hosting-Architektur mit Docker, SQLite und lokalen Backups

Verifizierte 37signals-Hosting-Architektur mit Docker, SQLite und lokalen Backups

Ja, exakt – du hast gerade unabhängig die ONCE-Architektur hergeleitet. 37signals macht es praktisch genauso, und inzwischen sogar noch einen Schritt konsequenter:

**Das Grundprinzip ist identisch mit deinem Plan.** Campfire, das erste ONCE-Produkt, ist als Docker-Container völlig self-contained und läuft auf SQLite – "quasi wartungsfrei auf der Datenbankseite", alles was es braucht, steckt in einem einzigen Container. Writebook genauso: die Anwendungsdatenbank läuft als einzelne Datei via SQLite3. Und die Zielumgebung ist genau dein VPS-Szenario: Es läuft auf dem lokalen Laptop, einem Server im Schrank oder in der Cloud (AWS, DigitalOcean, Hetzner) – 2 GB RAM und 1 CPU reichen. [37signals Dev + 2](https://dev.37signals.com/fizzy-infrastructure/)

**Spannend für dich: die Backup-Lösung, die sie 2026 nachgeliefert haben.** Sie haben inzwischen einen kleinen App-Server namens ONCE gebaut (Go-Binary, MIT-lizenziert), der genau die Fragen beantwortet, die du gerade stellst. ONCE mountet ein persistentes Volume unter /storage – und genau dieses Volume ist das, was gebackupt wird. Sauber, vorhersehbar, keine Überraschungen. Also exakt dein "ein Verzeichnis = die ganze Installation"-Prinzip. [Pierre Filstroff](https://fiwares.com/articles/once-by-37signals-self-hosting-without-the-devops-tax)

Und für das SQLite-Konsistenzproblem haben sie eine elegante Konvention: Vor jedem Backup ruft ONCE einen /hooks/pre-backup-Hook auf, damit die App eine "sichere" Kopie ihrer Daten erzeugen kann – existiert der Hook nicht, pausiert ONCE stattdessen kurz den Container während des Kopierens. Backups sind so in beiden Fällen konsistent. Das Beispiel für den Hook bei SQLite-Apps: SQLites Online-Backup-Feature für eine konsistente Kopie nutzen. Das ist genau das `.backup`-Muster, über das wir gesprochen haben – nur als Plattform-Konvention formalisiert. [GitHub](https://github.com/basecamp/once)

**Auch die Docker-Updates hast du richtig eingeordnet:** Das Install-Script installiert Docker, falls es fehlt, und ONCE delegiert HTTP-Routing und Zero-Downtime-Deploys an Kamal Proxy. Der VPS braucht also wirklich nur Docker; Updates sind Image-Pull plus Neustart, die Daten liegen unberührt auf dem Volume. [Pierre Filstroff](https://fiwares.com/articles/once-by-37signals-self-hosting-without-the-devops-tax)

Ein Detail, wo dein Cuvée sogar _schlanker_ wäre als Writebook: Writebook schleppt noch Redis mit – als Cache und Task-Queue für asynchrone Jobs. Das braucht Rails halt. In Elixir übernimmt die BEAM das alles nativ (PubSub, Hintergrundjobs, Prozesse), dein Container wäre also wirklich nur App + SQLite-Datei. Reinster geht's kaum. [Mgmarlow](https://mgmarlow.com/words/2024-10-13-exploring-writebook/)

Für Cuvée könntest du dir aus dem ONCE-Playbook zwei Dinge direkt abschauen: die `/storage`- bzw. `/data`-Konvention (alles Persistente an einem Ort, Volume drüber) und einen dokumentierten Pre-Backup-Mechanismus – ob als Shell-Hook oder als eingebauter Litestream, der das Problem gleich ganz eliminiert. Damit wärst du sogar ONCE-kompatibel: Leute könnten Cuvée theoretisch als "third-party App" über deren Server installieren, denn der nimmt beliebige Docker-Images, die diesen Konventionen folgen. Das wäre ein hübscher Distributionskanal gratis dazu.

das wäre also komplizierter das auf fly.io aufzusetzen in diesem mechanismus?

Evaluierte Fly.io-Machbarkeit mit SQLite-Einschränkungen

Evaluierte Fly.io-Machbarkeit mit SQLite-Einschränkungen

Nein, komplizierter nicht – aber es gibt ein paar Fly-spezifische Eigenheiten, die man kennen sollte. Das Grundmuster funktioniert dort fast identisch:

**Was gleich bleibt:** Fly Volumes sind das Äquivalent zum Docker-Volume. Du legst die SQLite-Datenbank auf ein persistentes Volume, weil das Deployment-Image beim nächsten Deploy überschrieben wird – `fly volumes create`, im `fly.toml` mounten, fertig. Dein `/data`-Konzept überträgt sich eins zu eins. Und für Backups ist Litestream sogar der von Fly selbst empfohlene Weg; Fly zeigt in der eigenen Doku das Setup mit Tigris, ihrem integrierten S3-kompatiblen Storage – das Backup-Ziel bekommst du also quasi frei Haus, ohne separaten AWS-Account. Litestream wurde außerdem kürzlich grundlegend überarbeitet und hat die besten Ideen aus LiteFS übernommen (LTX-Format, schnelle Point-in-Time-Restores) – das Tool ist lebendiger denn je. [Fly.io + 2](https://fly.io/docs/rails/advanced-guides/sqlite3/)

**Die Eigenheiten:**

Erstens: Volumes sind an einen Host gebunden – SQLite-Apps auf Fly können nicht in mehrere Regionen deployed werden. Für Cuvée egal (wir hatten Single-Node ja ohnehin beschlossen), aber du musst Fly aktiv sagen, dass es genau _eine_ Maschine geben soll – Flys Reflexe (Autoscaling, mehrere Maschinen für Verfügbarkeit) arbeiten gegen dich. Fly selbst empfiehlt eigentlich "immer mindestens zwei Volumes pro App, sonst gibt es irgendwann Downtime" – mit SQLite geht das nicht, also akzeptierst du bewusst: Bei Deploys und Host-Wartung ist die App kurz weg. Für ein Zwei-Personen-Blog völlig okay. [Fly.io](https://fly.io/docs/rails/advanced-guides/sqlite3/)[Fly.io](https://community.fly.io/t/so-its-not-possible-to-use-sqlite-on-fly-without-litefs/12306)

Zweitens, falls du über LiteFS stolperst (Flys verteiltes SQLite): Finger weg. Fly selbst schreibt inzwischen ein dickes Warnschild in die Doku: "Wir können für dieses Produkt keinen Support bieten. Mit Vorsicht verwenden" – insbesondere nicht mit Autostop/Autostart kombinieren, weil das zu Datenverlust führen kann. Die klare Ansage aus Flys eigener FAQ: Litestream für Single-Server-Deployments, LiteFS für Multi-Server – du bist der Litestream-Fall. [Fly.io](https://fly.io/docs/litefs/)[Fly.io](https://fly.io/docs/litefs/faq/)

Drittens: Flys Auto-Stop-Feature (Maschine schläft ein, wenn niemand zugreift) ist verlockend fürs Sparen, beißt sich aber leicht mit deinem Anwendungsfall – LiveView lebt von offenen WebSockets, und der Kaltstart beim Aufwachen kostet ein paar Sekunden. Ich würde die eine Maschine einfach durchlaufen lassen; bei der kleinsten Größe kostet das wenige Euro im Monat.

**Unterm Strich:** Fly ist für dich als _Entwickler_ von Cuvée sogar bequemer als ein VPS – `fly deploy` statt SSH und Docker-Pull, Tigris-Bucket per Befehl, Volume-Snapshots macht Fly zusätzlich automatisch. Der VPS-Weg ist dafür der richtige für deine _Nutzer_ (das ONCE-Publikum, das einen Server im Schrank oder bei Hetzner hat). Das Schöne: Es ist dasselbe Docker-Image. Du entwickelst und hostest deine eigene Instanz auf Fly, und die README beschreibt den `docker run`-Weg für Selbsthoster – kein Widerspruch, nur zwei Deployment-Ziele derselben Architektur.
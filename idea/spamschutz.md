Für ein Zwei-Personen-Blog mit Kommentaren ist das gut lösbar – und das Schöne: Die tracking-armen Lösungen sind hier sogar die _besseren_, nicht nur die netteren. Ich sortiere mal nach Eskalationsstufen:

**Stufe 1: Die unsichtbaren Klassiker (kein Captcha nötig)**

Der Großteil des Kommentar-Spams kommt von dummen Bots, die Formulare automatisiert abschicken. Gegen die helfen drei Tricks, die den echten Nutzer null belästigen:

- **Honeypot-Feld:** Ein verstecktes Formularfeld (per CSS unsichtbar), das Menschen leer lassen und Bots brav ausfüllen. Ist es gefüllt → verwerfen.
- **Zeitfalle:** Ein Mensch braucht mindestens ein paar Sekunden, um einen Kommentar zu tippen. Formular abgeschickt nach unter 3 Sekunden → Bot. Mit LiveView hast du das fast gratis, weil du die Mount-Zeit des Formulars serverseitig kennst – kein verstecktes Timestamp-Feld nötig, das manipulierbar wäre.
- **Rate Limiting:** Pro IP z.B. max. 3 Kommentare pro Minute. In Elixir trivial mit einem GenServer oder der Hammer/ExRated-Library, ganz ohne Redis.

Diese Kombination filtert erfahrungsgemäß 90%+ des automatisierten Spams und ist komplett tracking-frei – keine Cookies, keine Drittanbieter, nichts.

**Stufe 2: Captchas – die Landschaft**

Falls du doch eine explizite Hürde willst:

- **reCAPTCHA (Google):** Der Marktführer und für dein Projekt die falsche Wahl – trackt aggressiv, braucht Google-Cookies, GDPR-technisch Dauerbaustelle. Für ein Self-Hosting-Tool mit Privacy-Anspruch fast schon rufschädigend.
- **hCaptcha:** Weniger Google, aber immer noch ein Drittanbieter mit eigenem Geschäftsmodell (Bildlabeling), und Nutzer müssen Ampeln klicken. Meh.
- **Cloudflare Turnstile:** Deutlich besser – meist unsichtbar, keine Rätsel, datensparsamer. Aber: immer noch ein externer Dienst, den jeder Selbsthoster deiner Software einbinden müsste. Für ein "ein Container, deine Daten"-Produkt ein Fremdkörper.
- **ALTCHA / mCaptcha (Proof-of-Work):** Das ist die spannende Kategorie für dich. Statt Rätsel lösen lässt du den Browser des Kommentators eine kleine Rechenaufgabe knacken (ein paar hundert Millisekunden CPU). Für Menschen unmerklich, für Spammer, die tausende Kommentare absetzen wollen, wird's teuer. **Open Source, self-hosted, null Tracking, kein externer Dienst** – philosophisch die perfekte Passung zu Texttile. ALTCHA ist ein schlankes Widget plus serverseitige Verifikation, die du in Elixir in ~50 Zeilen selbst implementieren kannst (es ist im Kern nur SHA-256-Hashing).

**Stufe 3: Inhaltsbasiert (gegen menschliche Spammer und schlaue Bots)**

- **Akismet** (der WordPress-Spamfilter) hat eine API und funktioniert gut, ist aber wieder ein Cloud-Dienst, an den Kommentarinhalte geschickt werden – für dein Produkt höchstens als Opt-in.
- **Moderation als Feature:** Bei einem Blog von zwei Leuten ist die ehrlichste Lösung oft: Erster Kommentar einer E-Mail-Adresse landet in der Moderationswarteschlange, danach ist die Adresse freigeschaltet. Ihr seid ohnehin beide live im System – eine kleine Badge "1 Kommentar wartet" im LiveView-Header, und die Moderation kostet einen Klick. Bei eurem Traffic-Profil ist das realistischer als jede Automatik.

**Meine Empfehlung für Texttile als Produkt:** Stufe 1 komplett einbauen (Honeypot + Zeitfalle + Rate Limit, immer an, konfigurationsfrei), Moderations-Queue als Default für Erstkommentierer, und optional ALTCHA als eingebautes Proof-of-Work-Captcha für Instanzen, die stärker unter Beschuss stehen. Damit bleibt das Versprechen intakt: keine externen Dienste, kein Tracking, ein Container. Das wäre sogar ein Satz für die README wert – "Spam protection built-in. No Google, no third parties."

Einen habe ich noch fürs Naming-Kapitel: Bei einem Produkt namens Cuvée hätte man Spam-Kommentare stilecht "Essigstich" nennen können. Bei Texttile müssen wir wohl bei "kaputten Kacheln" bleiben.
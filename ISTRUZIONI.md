# Lista Spesa Automatica — Istruzioni

Tiene le scorte di casa, legge gli scontrini, confronta i volantini e ti dice cosa comprare e dove conviene.

## Cosa c'è nella cartella

| File / cartella | A cosa serve |
|---|---|
| `index.html` | L'app (si apre con doppio clic nel browser, funziona offline) |
| `Rinomina-Scontrini.bat` | Avvia la lettura automatica delle foto degli scontrini |
| `Rinomina-Scontrini.ps1` | Lo script usato dal `.bat` (non serve aprirlo) |
| `Scontrini/Nuovi` | Qui metti le foto degli scontrini |
| `Scontrini/Archiviati` | Scontrini letti correttamente, rinominati `Negozio_Data` |
| `Scontrini/Da controllare` | Scontrini con negozio o data non letti |
| `Scontrini/Duplicati` | Foto identiche a una già ricevuta |
| `Scontrini/archivio.json` | Memoria dello script (non toccare) |

## 1. Foto degli scontrini

1. Fai doppio clic su `Rinomina-Scontrini.bat` e lascia la finestra aperta. Controlla la cartella `Nuovi` ogni 5 secondi.
2. Metti le foto in `Scontrini/Nuovi`.
3. Lo script legge il testo con l'OCR italiano di Windows (non serve installare nulla), trova negozio e data e sposta le foto in `Archiviati`.

Esempio: `Lidl_2026-10-12_1842.jpg` e il file di testo `Lidl_2026-10-12_1842.txt` con le righe lette.

### Scontrino lungo, con più foto

Fotografa lo scontrino a pezzi facendo **sovrapporre qualche riga** tra una foto e la successiva. Per ogni scontrino:

- le foto dello stesso scontrino vengono unite, senza ripetere le righe (`_p1`, `_p2`, …) e con un solo `.txt`;
- una foto identica a una già inviata va in `Duplicati` e viene ignorata;
- l'ordine di arrivo non conta: se prima arriva la parte senza intestazione, resta in `Da controllare` e si sposta in `Archiviati` quando arriva la foto con il negozio.

### Controllo del totale

Nel `.txt` e nel messaggio della finestra c'è una riga di controllo:

- `OK: somma righe = totale` → scontrino completo.
- `ATTENZIONE: totale X ma somma righe Y` → manca una foto o l'OCR ha perso una riga. Aggiungi la foto mancante in `Nuovi`, oppure correggi a mano nell'app.

### Se una foto finisce in "Da controllare"

Il negozio non è tra quelli noti o la data non si legge. Puoi:

- rinominarla a mano;
- se è un pezzo di uno scontrino già inviato, rimetterla in `Nuovi`;
- aggiungere la catena all'elenco `$stores` in `Rinomina-Scontrini.ps1`.

Catene già riconosciute: Esselunga, Conad, Coop, Lidl, Eurospin, Carrefour, MD, Penny, Aldi, Pam, Iper, Despar, Tigros, Famila, Bennet, In's, Dok, Sigma, Todis, Prix, Unes, Il Gigante, NaturaSì, Decathlon, Tigotà, Acqua e Sapone.

### Limiti

- Le foto devono essere nitide, dritte e ben illuminate. L'OCR sbaglia qualche carattere ("1L" letto "IL").
- Due scontrini diversi dello stesso negozio e giorno restano separati se l'ora è leggibile; senza ora e con righe in comune potrebbero unirsi per errore. Il controllo del totale serve a scoprirlo.

## 2. L'app (`index.html`)

Apri `index.html` nel browser. I dati restano nel browser del computer (non sono condivisi tra dispositivi).

### Riquadro "Controllo volantini"

Ad ogni apertura, in cima a ogni scheda, mostra:

- quante offerte sono valide, scadute o in scadenza entro 2 giorni;
- in quale negozio conviene fare la spesa oggi, con costo stimato e risparmio;
- quanto risparmieresti dividendo la spesa tra più negozi.

Se non ci sono volantini validi ti avvisa di aggiornarli.

### Scheda 📦 Scorte

Aggiungi i prodotti con:

- **In casa**: quantità attuale (con pulsanti − e +);
- **Minimo**: sotto questa quantità finisce in lista;
- **Obiettivo**: quanto ne vuoi avere dopo la spesa;
- **Consumo/giorno**: scala le scorte da solo nel tempo (es. 0,3 latte al giorno);
- **Prezzo abituale**: si aggiorna da solo con gli scontrini;
- **Parole chiave scontrino**: come compare il prodotto sullo scontrino (es. `latte, lt parz`).

### Categorie dei prodotti

Ogni prodotto ha una categoria, assegnata da sola dal nome (e dalle parole chiave dello scontrino): 🥫 Dispensa, 🍪 Colazione e dolci, 🥖 Pane e forno, 🍝 Pasta e cereali, 🥛 Latticini e uova, 🧀 Salumi e formaggi, 🥩 Carne, 🐟 Pesce, ❄️ Surgelati, 🥬 Frutta e verdura, 🍕 Piatti pronti, 🥤 Bevande, 🍿 Snack, 🧴 Igiene personale, 🧽 Casa e pulizia, 🐾 Animali, 📦 Altro.

- Nella scheda **Scorte** i prodotti sono raggruppati per categoria e c'è un filtro per vederne una sola. Se la categoria è sbagliata, la cambi dal menu sotto il nome del prodotto: la scelta resta.
- Nella **Lista consigliata** i prodotti di ogni negozio sono ordinati per categoria, come i reparti del supermercato.
- I prodotti nuovi creati da uno scontrino ricevono la categoria in automatico. Quelli già presenti prima dell'aggiornamento la ricevono alla prima apertura, senza cambiare quantità o prezzi.
- Se una parola non viene riconosciuta finisce in 📦 Altro. Le parole chiave sono nell'elenco `CATS` all'inizio dello script di `index.html`.

### Scheda 🧾 Scontrini

1. Apri il `.txt` accanto alla foto archiviata (cartella `Archiviati`) e copia tutto il testo.
2. Incollalo nella scheda e premi **Analizza**. Le righe non-prodotto (totale, IVA, resto, pagamento) vengono filtrate.
3. Controlla l'associazione di ogni riga a un prodotto (o "Nuovo prodotto" / "ignora") e premi **Aggiungi alle scorte**.

Se lo scontrino è già stato importato, l'app avvisa e chiede conferma, per non sommare due volte le scorte.

### Scheda 🏷️ Volantini

In cima c'è **📍 I miei supermercati**: spunta le catene che hai vicino (puoi aggiungerne altre a mano). Confronto, riquadro in alto e lista useranno solo i volantini di quei negozi; le offerte degli altri restano nella tabella, in grigio e segnate "negozio non selezionato", ma non contano. Se non spunti nulla vengono considerati tutti. La scelta si può cambiare in ogni momento dal link "modifica" nel riquadro in alto.

Inserisci le offerte della settimana:

- una alla volta con il modulo, oppure
- incolla più righe nel formato `negozio; prodotto; prezzo; dal; al` (le date sono facoltative), per esempio:
  ```
  Lidl; latte parzialmente scremato; 0,99; 10/10; 16/10
  Conad; pasta barilla; 0,89; ; 20/10
  ```

Le offerte scadute vengono ignorate e si cancellano con **Elimina offerte scadute**. I volantini non si scaricano da soli: vanno inseriti a mano.

### Scheda 📋 Lista consigliata

Si genera da sola:

- entrano i prodotti sotto il minimo (al prezzo di volantino, se c'è);
- entrano anche i prodotti non ancora finiti con uno sconto di almeno il 20% rispetto al prezzo abituale, per fare scorta;
- è raggruppata per negozio (ogni articolo nel negozio dove costa meno), con la tabella "Dove conviene fare la spesa".

Dopo la spesa seleziona gli articoli comprati e premi **Ho comprato**: le scorte si aggiornano. Con **Carica dati di esempio** (a scorte vuote) puoi vedere l'app in funzione.

## Flusso consigliato

1. Dopo la spesa: foto dello scontrino in `Scontrini/Nuovi` (con il `.bat` attivo).
2. Copia il testo del `.txt` nella scheda **Scontrini** dell'app → scorte aggiornate.
3. Ogni settimana: aggiorna i **Volantini**.
4. Prima di uscire: apri l'app, guarda il riquadro in alto e la **Lista consigliata**.

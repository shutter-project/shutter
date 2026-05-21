# Selezione interattiva su Wayland (strada A)

Data: 2026-05-21
Branch: `feature/wayland-interactive-selection`

## Problema

Su Wayland Shutter cattura solo lo schermo intero (via `xdg-desktop-portal`).
I bottoni Selezione area, Finestra e Attiva sono disabilitati perché dipendono
da X11 (`Wnck`, `GdkX11`), non accessibile su Wayland per ragioni di sicurezza.
Riferimento upstream: issue #187.

## Obiettivo

Abilitare su Wayland i bottoni Selezione / Finestra / Attiva. Tutti invocano il
portal XDG in modalità **interattiva**: il compositor (GNOME) mostra il proprio
selettore nativo (area / finestra / schermo) e ritorna un'immagine già ritagliata,
che entra nel flusso post-cattura esistente di Shutter.

## Componenti toccati

### 1. `share/shutter/resources/modules/Shutter/Screenshot/Wayland.pm`
- `xdg_portal($screenshooter, $interactive)`: nuovo secondo parametro.
- Opzioni portal: `{handle_token => $token, interactive => $interactive ? TRUE : FALSE}`.
- Chiamata full-screen attuale → passa `FALSE` (comportamento invariato).

### 2. `bin/shutter` (~riga 4406)
- Logica che disabilita i bottoni su Wayland (`$x11_supported` falso): condizionare
  così che Selezione, Finestra e Attiva restino **abilitati** anche su Wayland.
- Bottoni che richiedono geometria/regex predefinita restano fuori scope (vedi sotto).

### 3. `bin/shutter` (~riga 6198, dispatch cattura)
- Quando modalità = select / window / active **e** sessione = Wayland →
  chiamare `Shutter::Screenshot::Wayland::xdg_portal($s, TRUE)` invece del path X11.

## Flusso

1. Utente clicca un bottone di selezione.
2. Shutter chiama il portal in modalità interattiva.
3. GNOME mostra il selettore nativo; l'utente sceglie area/finestra/schermo.
4. Il portal ritorna l'URI del file (immagine già ritagliata).
5. Shutter carica il pixbuf e prosegue con il **post-processing esistente**
   (salvataggio / editor / upload). Identico al full-screen Wayland già funzionante.

## Gestione errori

- Response `num != 0` dal portal = utente ha annullato nel selettore GNOME.
  → Abort silenzioso, nessun dialog d'errore (cancellazione volontaria, non fallimento).
- Eccezioni DBus → comportamento attuale (`_error_text`), invariato.

## Fuori scope

- Cattura finestra per nome/regex (`--window=PATTERN`): il portal non accetta target.
- Selezione con coordinate predefinite (`-s=X,Y,W,H`): il portal non accetta geometria.
- Overlay di selezione nativo di Shutter su Wayland: resta inattivo; il selettore è
  quello di GNOME.

## Test (sessione Wayland)

- Ogni bottone (Selezione / Finestra / Attiva) apre il selettore GNOME.
- L'immagine catturata viene caricata in Shutter e segue il flusso normale.
- Annullamento nel selettore non genera dialog d'errore.
- Regressione: full-screen su Wayland e tutta la cattura su Xorg restano invariati.

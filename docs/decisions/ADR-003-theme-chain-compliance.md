# ADR-003: Theme chain compliance — extension groups, complete bridges, no off-chain literals

## Status

Accepted

## Date

2026-05-09

## Context

OlonJS Architecture Specifications **v1.6** (CIP §4.4) define a normative 4-layer theme chain:

```
theme.json → published runtime vars (--theme-*) → tenant semantic bridge (:root) → section --local-* → JSX classes
```

An audit of the LightAlpine tenant revealed three classes of compliance gaps:

1. **Layer 1 bridge incomplete.** `src/index.css` only ponticellava i colori (e un `--radius` parziale). Tipografia (`scale`, `tracking`, `leading`), spacing, zIndex, e l'intero set di radius `xl/full` non avevano un bridge semantico tenant-sovrano. Il risultato è che `:root` non esponeva nomi semantici per quelle dimensioni — sezioni che vi accedevano dovevano usare direttamente i nomi `--theme-*-*` (leak di vocabolario engine), oppure cadere su literal.

2. **TOCC overlay con literal hardcodati.** Le selettori `[data-jp-section-overlay]` (rif. spec §7) usavano `z-index: 9999`, `color: #fff`, `border: 2px solid …`, `padding: 0.2rem 0.55rem`, `font-size: 9px`, `letter-spacing: 0.1em`, durate `0.15s` — tutti fuori catena. Questo viola §4.4.11 (non-compliant patterns) anche se localizzato a chrome di Studio.

3. **Sezioni con palette categorical hardcoded e wordmark inline.**
   - `wine-cellar/View.tsx`: map `wineTypeColors` con classi Tailwind `text-red-400 / bg-red-400/10 / border-red-400/20` (e analoghe per white/sparkling/dessert).
   - `experience-timeline/View.tsx`: map `difficultyColors` con classi `text-green-400 / yellow / orange / red`.
   - `resort-highlights/View.tsx`: `text-white` e `text-white/80` su card sopra immagini, più `text-[1.2rem]`.
   - `header/View.tsx` e `footer/View.tsx`: wordmark con `style={{ fontFamily: '"Cormorant Garamond"…', fontWeight: 600, letterSpacing: '-0.04em' }}` inline, ridondante rispetto alla classe `font-display` e ai token tipografici già presenti in `theme.json` sotto `typography.wordmark`.

Le palette categorical (tipo vino, livello difficoltà) non sono "tiny decorative one-off values" (§4.4.10) — sono semantica visiva ricorrente del tenant, candidata a token-set sotto un gruppo `tokens.semantic.*`.

Lo schema design v1 (`https://olon.js.org/schemas/v1/design.schema.json`) consente `additionalProperties: true` a livello `tokens`, quindi gruppi extension (`animation`, `borders`, `semantic`) sono ammessi senza modifiche allo schema.

## Decision

1. **Estendere `theme.json` con gruppi extension** invece di aggiungere literal in CSS o nelle View:
   - `tokens.animation.{duration,easing,delay,timing}` per durate/curve/delay riusabili
   - `tokens.borders.{width,style}` per spessori/stili di bordo standard
   - `tokens.zIndex.overlay-stage` (`9999`) per il chrome Studio sopra `modal/toast`
   - `tokens.typography.wordmark.tracking` (`-0.04em`) per il marchio
   - `tokens.semantic.difficulty.{easy,moderate,challenging,expert}` con triplette `{bg,border,text}`
   - `tokens.semantic.wine.{red,white,sparkling,dessert}` con triplette `{bg,border,text}`
   - `tokens.semantic.overlay.text-on-image` per testo bianco su gradient nero (uso documentato)
   - Specchio in `tokens.modes.light.semantic.*` solo per le palette che richiedono override percettivi.

2. **Completare Layer 1 (`:root`)** in `src/index.css` aggiungendo bridge semantici tenant per ogni nuovo gruppo (typography scale/tracking/leading, spacing, zIndex completo, radius `xl/full`, animation, borders, semantic). Naming sovrano del tenant — non si esporta `--theme-*-*` direttamente nelle View.

3. **Completare Layer 2 (`@theme`)** esponendo i nomi nuovi alle utility Tailwind (`--radius-xl`, `--radius-full`, `--text-*`, `--tracking-*`, `--leading-*`, `--spacing-*`).

4. **Rifattorizzare TOCC overlay** sostituendo ogni literal con token (z-index → `--z-overlay-stage`, `#fff` → `--primary-foreground`, durate → `--anim-duration-fast`, font-size → `--text-xs`, tracking → `--tracking-widest`).

5. **Aggiungere helper `.font-wordmark`** che applica `font-family + font-weight + letter-spacing` dai token `wordmark.*` — header e footer lo consumano via classe, non via `style={{}}`.

6. **Sezioni consumano semantic via Layer 3 `--local-*`.** Esempio per `wine-cellar`:
   ```tsx
   '--local-wine-red-bg': 'var(--semantic-wine-red-bg)',
   '--local-wine-red-text': 'var(--semantic-wine-red-text)',
   ```
   Nessuna classe `text-red-400 / bg-red-400/10` resta nelle View.

7. **`resort-highlights`** usa `--local-text-on-image` ponticellato a `var(--semantic-overlay-text-on-image)` — il bianco resta semanticamente "testo su gradient scuro", non literal `text-white`.

8. **Esclusioni esplicite:**
   - `src/components/ui/*` (shadcn primitives, vincolati al loro contratto upstream)
   - `src/components/save-drawer/*` (chrome Studio interno con identità visiva sovrana)
   - `src/components/form-demo/*` (showroom Form Factory, non sezione editoriale del tenant)

## Alternatives Considered

### A. Spostare solo i colori in token, lasciare dimensioni/animazioni hardcoded

Rejected: viola §4.4.11 ("hardcoding primary themed values in JSX or section-local inline styles"). Una catena parzialmente conforme è una fonte di drift — la prossima sezione aggiunta replicherà i literal "perché tanto già ce ne sono".

### B. Mettere palette difficulty/wine in `data` invece che in `theme.json`

Pros: tenant editor potrebbe in teoria cambiare la tinta del badge "Expert" senza toccare il tema.  
Cons: la tinta è una proprietà visiva del tenant, non del contenuto. Cambiarla per pagina porterebbe a inconsistenza UX. Inoltre il pattern v1.6 (§A.2.6) raccomanda raggruppamenti tenant-sovrani sotto `tokens` quando l'uso è ricorrente e sistematico.  
Rejected: appartiene al theme, non al data layer.

### C. Lasciare che `@olonjs/core` definisca i token semantic standard (difficulty, wine, ecc.)

Rejected esplicitamente da v1.6 §4.4.2: "Core must not govern or restrict the tenant semantic vocabulary". Il core è un trasportatore, non un'autorità semantica. Difficulty/wine sono vocabolario del tenant (resort di montagna con cantina).

### D. Stylesheet separato per TOCC con i suoi token

Pros: isolation chrome Studio.  
Cons: aumenta numero di stylesheet caricati e duplica bridging. TOCC è già in `index.css` per ragioni di ordering CSS (vedi ADR-001) e spec §7 lo prevede in tenant CSS.  
Rejected: peggiore della soluzione token-driven nello stesso file.

## Consequences

### Positive

- Aggiungere una nuova sezione tematica non richiede di "scegliere un colore Tailwind a caso" — il tenant ha un vocabolario.
- Cambiare il branding (es. switch a palette "Toscana") richiede di toccare solo `theme.json`; le View restano invariate.
- TOCC overlay ora rispetta il tema: in light mode il label cambia colore di testo con coerenza percettiva.
- Compliance tracciabile: `Grep "text-(red|blue|green|yellow|...)-\d+" src/components/{section}/View.tsx` deve restituire 0 risultati.

### Negative / Trade-offs

- `theme.json` cresce significativamente (~60% in più di righe). Compensato dal fatto che è il source of truth — se non sta lì, sta sparpagliato.
- Engine deve flatten gruppi extension (`semantic`, `animation`, `borders`); se non lo fa, le palette categorical non risolvono. Mitigation: verifica DevTools dopo il primo render; fallback documentato sotto.
- Il vocabolario tenant è ora più denso — agenti che lavoreranno su nuove sezioni devono leggere `theme.json` prima di inventare nomi.

### Risks and Mitigations

- **Engine non flatten extension groups.** Se DevTools mostra che `--theme-semantic-wine-red-bg` non viene pubblicato, il fallback è bridging manuale in `:root` (`--semantic-wine-red-bg: oklch(...);`) con valori duplicati da `theme.json`. Brutto ma compatibile. Verifica al primo dev start.
- **Override per modo light mancanti.** Le palette `semantic.*` con un solo set di valori potrebbero contrastare male in light mode. Mitigation: ogni semantic palette ha la sua sezione in `tokens.modes.light.semantic.*`.
- **`text-[1.2rem]` → `text-xl`** introduce un mini-jump (1.2rem vs 1.25rem). Differenza ~0.8px, accettabile per consistenza con scala tipografica.

## References

- OlonJS Architecture Specifications v1.6 — §4.4 (Local Design Tokens), §4.4.11 (non-compliant patterns), §A.2.6 (ThemeConfig tenant sovereignty)
- Schema design v1: `https://olon.js.org/schemas/v1/design.schema.json` (additionalProperties true at tokens root)
- ADR-001: Tenant theme CSS order and remote `@import` handling
- ADR-002: Internal navigation uses React Router `Link`
- Implementation files:
  - `src/data/config/theme.json` (extension groups added)
  - `src/index.css` (Layer 1+2 completed, TOCC refactored)
  - `src/components/header/View.tsx`, `src/components/footer/View.tsx` (wordmark via `.font-wordmark`)
  - `src/components/wine-cellar/View.tsx`, `src/components/experience-timeline/View.tsx` (semantic palettes via `--local-*`)
  - `src/components/resort-highlights/View.tsx` (overlay text via `--local-text-on-image`)

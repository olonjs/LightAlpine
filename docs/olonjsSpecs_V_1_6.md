
# OlonJS Architecture Specifications v1.6 

**Status:** Mandatory Standard  
**Version:** 1.6.0 (Complete Draft - Core-Agnostic Theme Transport, Shell/Menu Contract Clarification, Full v1.5 Consolidation)  
**Target:** Senior Architects / AI Agents / Enterprise Governance

**Scope v1.6:** This edition is intended as a complete replacement specification, not as an addendum. It preserves the valid architecture of v1.5 while correcting the parts that could mislead agents or implementers. It keeps the full architecture surface (MTRP, JSP, TBP, CIP, ECIP, IDAC, TOCC, BSDS, ASC, JEB, JAP, Appendix A) and clarifies three architectural laws that were under-specified before: Core theme agnosticism, explicit theme flattening/publication, and `menu.json` as the source of truth for menu structures.

**Primary v1.6 clarifications:**

- `@olonjs/core` is a token transporter/publisher, not the semantic authority for tenant theme vocabulary
- theme flattening is explicit and normative
- tenant theme sovereignty is explicit
- `menu.json` is the source of truth for menu structures
- `site.json` owns shell structure and shell instance declaration
- `header` and `footer` are shell-scoped section instances, not conceptually reserved types
- normative companion JSON Schemas are defined for `site.json` and `menu.json`

**Scope note:** v1.6 does not freeze every current runtime compatibility shortcut as architectural law. Where runtime adapters or compatibility branches exist, architecture takes precedence.

---

## 1. Modular Type Registry Pattern (MTRP) v1.3

**Objective:** Establish a strictly typed, open-ended protocol for extending content data structures where the Core engine is the orchestrator and the Tenant is the provider.

### 1.1 The Sovereign Dependency Inversion

The Core defines empty registries.
Tenant injects concrete definitions using module augmentation.

This allows Core to be distributed as a compiled NPM package while remaining aware of tenant-specific types at compile time.

### 1.2 Technical Implementation (`@olonjs/core/kernel`)

```typescript
export interface SectionDataRegistry {} // Augmented by Tenant
export interface SectionSettingsRegistry {} // Augmented by Tenant

export interface BaseSection<K extends keyof SectionDataRegistry> {
  id: string;
  type: K;
  data: SectionDataRegistry[K];
  settings?: K extends keyof SectionSettingsRegistry
    ? SectionSettingsRegistry[K]
    : BaseSectionSettings;
}

export type Section = {
  [K in keyof SectionDataRegistry]: BaseSection<K>
}[keyof SectionDataRegistry];
```

Core exports or allows the tenant to infer `SectionType` as `keyof SectionDataRegistry`.
After tenant augmentation this becomes the union of all supported section keys.

### 1.3 Architectural Rule

Core must remain open to tenant augmentation.
Tenant-specific section types must not require Core source edits.

**Why it matters:** MTRP is the foundation that allows one Core engine to serve many tenants while preserving end-to-end type safety.

---

## 2. JsonPages Site Protocol (JSP) v1.9

**Objective:** Define deterministic content/config topology and the site-level document contract.

### 2.1 The File System Ontology

Every tenant should expose a deterministic content/config silo:

- `src/data/config/site.json`
- `src/data/config/menu.json`
- `src/data/config/theme.json`
- `src/data/pages/**/*.json`

The CLI or projection workflow may use different physical staging paths, but the runtime contract remains that the app receives `siteConfig`, `menuConfig`, `themeConfig`, `pages`, and optional `refDocuments`.

### 2.2 Source Of Truth Separation

The canonical tenant document responsibilities are:

- `site.json` -> site identity, shell structure, shell-scoped section instances, page listing metadata
- `menu.json` -> menu trees and named menu collections
- `theme.json` -> theme token source of truth
- `pages/**/*.json` -> page-scoped content sections

### 2.3 Menu Source Of Truth Rule

`menu.json` is the source of truth for menu data.

Shell components may consume menu data.
Shell components must not be treated as the authoritative source of menu structure.

### 2.4 Shell Binding Rule

If a shell component uses menu data, it should bind to `menu.json` through `data.menu.$ref`.

Canonical rule:

### 2.5 Bound External Field Rule

If an authored field contains a `$ref` to an external document, that field is a binding field, not an ownership field.

Canonical consequences:

- the authored document keeps the binding expression
- the referenced document remains the owner of the bound data
- Studio may present the resolved value in Inspector as if it were local
- draft mutation and persistence must target the referenced owner document, not the binding document
- the binding document must not be canonically materialized with the resolved payload during save

Example:

- `site.json -> header.data.menu.$ref -> ../config/menu.json#/main`
- Inspector may render `header.data.menu` as concrete `MenuItem[]`
- edits must update `menu.json.main`
- `site.json` must keep `data.menu.$ref`

- no menu -> omit the field
- has menu -> use `$ref`

Resolved Editing Surface Rule: Component Zod schemas (e.g., HeaderSchema) describe the resolved data surface presented to the Inspector, not the raw authored JSON. If a field like data.menu is authored as a
$ref in site.json, the corresponding Zod schema MUST describe the resolved shape (e.g., z.array(MenuItemSchema)). The engine handles resolving the $ref for the Form Factory and routing the edits back to the
referenced document (e.g., menu.json).

### 2.5 Deterministic Projection

Tenant generation and scaffolding should preserve deterministic paths for:

- config documents
- page documents
- component capsules
- registries
- schemas

Canonical projection workflow:

1. Infra projection generates the shell files such as `package.json`, `tsconfig.json`, and `vite.config.ts`
2. Source projection reconstructs the tenant DNA under `src/`
3. Dependency resolution pins the expected runtime/build stack for the tenant

The exact tool implementation may evolve, but the projection result must remain deterministic enough that agents and tooling can rediscover the same contract surfaces without heuristic scanning.

**Why it matters:** JSP gives agents and tooling stable paths for discovery, projection, validation, and migration.

---

## 3. Tenant Block Protocol (TBP) v1.1

**Objective:** Standardize the capsule structure for tenant section/component types.

### 3.1 The Atomic Capsule Structure

Components are self-contained directories under `src/components/<sectionType>/`:

- `View.tsx` -> pure React component
- `schema.ts` -> Zod schema(s) for the data contract and optionally settings
- `types.ts` -> TypeScript interfaces inferred from the schema
- `index.ts` -> public API re-exporting View, schema(s), and types

`schema.ts` must export at least one data schema for the type.
Data schema should extend `BaseSectionData`.
Array items should extend `BaseArrayItem`.

### 3.2 Shell-Scoped Section Instances

`header` and `footer` are not conceptually reserved types.

They are ordinary tenant section/component types whose instances are declared in `site.json` instead of page JSON.

They therefore share:

- the same component model
- the same schema-driven contract style
- the same compositional principles

They differ only in:

- data placement
- rendering scope

They also participate in two distinct contracts that must not be conflated:

- authored shell config contract in `site.json`, where menu usage is expressed as `data.menu.$ref`
- resolved runtime props contract, where a shell component may receive concrete `MenuItem[]` after resolution

### 3.3 Runtime Special Handling

Core may render shell-scoped instances specially in the global shell path.
This is a runtime/layout concern, not a separate ontological category of section type.

**Why it matters:** TBP keeps extension uniform and prevents shell components from becoming a hidden second component system.

---

## 4. Component Implementation Protocol (CIP) v1.7

**Objective:** Ensure system-wide stability, theme portability, and Admin UI integrity.

### 4.1 The Sovereign View Law

Components receive `data` and `settings` and return JSX.
Shell-scoped instances may receive additional resolved props such as resolved menu trees when the shell binding contract requires it.

Views are metadata-blind:

- they do not import Zod schemas
- they do not embed form logic
- they do not become the semantic authority for tenant theme vocabulary

### 4.2 Z-Index Neutrality

Components must not use `z-index > 1` for ordinary section content.
Layout delegation such as sticky or fixed behavior belongs to the renderer/shell contract, not to arbitrary page sections.

Documented exceptions may exist for shell chrome such as header/footer, but they must remain compatible with overlay visibility.

### 4.3 Agnostic Asset Protocol

Use `resolveAssetUrl(path, tenantId)` for all tenant media.
Resolved URLs are published under `/assets/...`.

### 4.4 Local Design Tokens

**Objective:** Standardize how a section consumes tenant theme values without leaking global styling assumptions into section implementation.

#### 4.4.1 Theme Source Of Truth

For themed tenants, `theme.json` is the tenant-level source of truth for theme tokens.

The tenant decides:

- which token groups exist
- which token names exist
- which semantic vocabulary is used
- how those tokens are bridged into semantic CSS and utilities

Core and section Views are read-only consumers of that contract.

#### 4.4.2 Core Theme Transport Rule

`@olonjs/core` is a token transporter/publisher, not a semantic authority.

That means:

- Core reads `theme.json`
- Core recursively flattens discovered token paths
- Core publishes those values as CSS custom properties before section rendering
- Core may expose convenience aliases
- Core must not govern or restrict the tenant semantic vocabulary

If a tenant token tree is flattenable, Core should publish it.

#### 4.4.3 The Required Layered Chain

For any section that controls background, text color, border color, accent color, or radii, the following chain is normative:

1. Tenant theme source of truth in `theme.json`
2. Runtime theme publication through flattened CSS custom properties
3. Tenant semantic bridge in global CSS such as `:root` and `@theme`
4. Section-local scope through `--local-*` variables when the section owns those concerns
5. Rendered utilities/classes consuming the local or tenant semantic layer

Canonical chain:

`theme.json -> published runtime vars -> tenant semantic bridge -> section --local-* -> JSX classes`

#### 4.4.4 Flattening Rule

Normative rule:

`theme.json object path -> kebab-case path segments -> --theme-... CSS variable`

Examples:

- `tokens.colors.primary` -> `--theme-colors-primary`
- `tokens.typography.fontFamily.display` -> `--theme-typography-font-family-display`
- `tokens.typography.tracking.tight` -> `--theme-typography-tracking-tight`
- `tokens.borderRadius.md` -> `--theme-border-radius-md`
- `tokens.spacing.container-max` -> `--theme-spacing-container-max`
- `tokens.modes.light.colors.background` -> `--theme-modes-light-colors-background`

This flattening rule is architectural law and must not be inferred indirectly by agents.

#### 4.4.5 Runtime Theme Publication

Runtime publication is mandatory for themed tenants.

The compliant bridge is a layered architecture typically implemented in tenant `index.css`:

`theme.json -> engine injection -> :root bridge -> @theme bridge -> JSX classes`

Layer roles:

- engine injection publishes flattened `--theme-*` variables
- `:root` bridge maps published runtime variables into tenant semantic names
- `@theme` bridge exposes those names to Tailwind or equivalent utilities
- section-local `--local-*` variables scope owned concerns to a section root

Concrete bridge examples:

Layer 0 - Engine injection:

| JSON path | Injected CSS var |
|---|---|
| `tokens.colors.{name}` | `--theme-colors-{name}` |
| `tokens.typography.fontFamily.{role}` | `--theme-font-{role}` |
| `tokens.typography.scale.{step}` | `--theme-typography-scale-{step}` |
| `tokens.typography.tracking.{name}` | `--theme-typography-tracking-{name}` |
| `tokens.typography.leading.{name}` | `--theme-typography-leading-{name}` |
| `tokens.typography.wordmark.*` | `--theme-typography-wordmark-*` |
| `tokens.borderRadius.{name}` | `--theme-border-radius-{name}` |
| `tokens.spacing.{name}` | `--theme-spacing-{name}` |
| `tokens.zIndex.{name}` | `--theme-z-index-{name}` |
| `tokens.modes.{mode}.colors.{name}` | `--theme-modes-{mode}-colors-{name}` |

Layer 1 - Tenant semantic bridge:

```css
:root {
  --background: var(--theme-colors-background);
  --foreground: var(--theme-colors-foreground);
  --card: var(--theme-colors-card);
  --primary: var(--theme-colors-primary);
  --border: var(--theme-colors-border);

  --font-primary: var(--theme-font-primary);
  --font-display: var(--theme-font-display);

  --theme-container-max: var(--theme-spacing-container-max);
  --z-overlay: var(--theme-z-index-overlay);
}
```

Layer 2 - `@theme` bridge:

```css
@theme {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card: var(--card);
  --color-primary: var(--primary);
  --color-border: var(--border);

  --font-primary: var(--font-primary);
  --font-display: var(--font-display);

  --radius-md: var(--theme-radius-md);
  --radius-lg: var(--theme-radius-lg);
}
```

Additional modes should override the Layer 1 semantic bridge, for example under `[data-theme=\"light\"]`, while leaving Layer 2 unchanged.

Rule:

- skipping Layer 2 breaks utility resolution
- skipping Layer 1 couples sections to engine-internal naming
- hardcoding values in any bridge layer is non-compliant

#### 4.4.6 Alias Rule

Aliases such as:

- `--theme-font-primary`
- `--theme-font-display`
- `--theme-radius-md`

are conveniences only.

They do not redefine tenant vocabulary ownership and must not be mistaken for the canonical contract.

#### 4.4.7 Tenant Semantic Bridge

The tenant owns the bridge from published runtime vars into:

- `:root` semantic variables
- Tailwind `@theme` variables
- section-local `--local-*` variables
- utility classes

The naming in this bridge is the tenant's sovereign choice.
Core does not impose semantic names such as `foreground`, `card`, or `muted-foreground`.

#### 4.4.8 Local Token Consumption Rule

If a section visually owns background, text, border, accent, or radius concerns, it must not bypass local scoping for those concerns.

Required pattern:

- section root defines `--local-*` variables for owned color/radius concerns
- child utilities consume `var(--local-*)`

Directly using global theme variables throughout JSX for section-owned concerns is non-canonical for a fully themed section.

#### 4.4.9 Typography Rule

Typography follows the same source-of-truth rule, but local scoping is optional unless the section truly remaps typography locally.

Canonical typography chain:

`theme.json -> published runtime vars -> tenant semantic font bridge -> utility or CSS variable -> JSX typography`

#### 4.4.10 Allowed Exceptions

The following are acceptable if documented and intentionally limited:

- tiny decorative one-off values that are not part of the tenant theme contract
- temporary migration shims where the compliant path still exists and is primary
- semantic alias bridges in tenant CSS whose source remains the published theme layer

#### 4.4.11 Non-Compliant Patterns

The following are non-compliant:

- reading `theme.json` directly inside a View
- hardcoding primary themed values in JSX or section-local inline styles
- using `rounded-[7px]`, `bg-blue-500`, `text-zinc-100`, or similar literals as the primary themed contract
- defining `--local-*` at the root and then bypassing them with raw global utilities for the same owned concerns
- treating tenant-specific extension keys as a replacement for the tenant's own primary semantic contract

#### 4.4.12 Practical Interpretation

`--local-*` is not the source of truth.
It is the section-local scoping layer between tenant theme publication and section rendering.

### 4.5 Z-Index & Overlay Governance

Section content roots must remain at `z-index <= 1` so the Studio overlay can remain authoritative.
Shell-scoped instances may use higher values only as documented shell exceptions.

**Why it matters:** View components stay dumb and portable, themed tenants remain reproducible, and Studio overlay behavior remains deterministic.

---

## 5. Editor Component Implementation Protocol (ECIP) v1.6

**Objective:** Standardize the schema-driven editing contract used by Studio tooling.

### 5.1 Recursive Form Factory

The Admin UI builds forms by traversing the Zod ontology rather than hardcoding per-type editor implementations.

### 5.2 UI Metadata

Schema descriptions may encode UI metadata using `.describe('ui:...')`.
This is the contract by which the Form Factory chooses widgets.

### 5.3 Deterministic IDs

Every object in an editable `ZodArray` must extend `BaseArrayItem` or otherwise include stable `id`.
This guarantees React reconciliation stability during reorder/delete flows.

### 5.4 UI Metadata Vocabulary

Standard keys for the Form Factory are:

| Key | Use case |
|-----|----------|
| `ui:text` | Single-line text input |
| `ui:textarea` | Multi-line text |
| `ui:select` | Enum or single choice |
| `ui:number` | Numeric input |
| `ui:list` | Array editor with add/remove/reorder |
| `ui:icon-picker` | Icon selection via tenant-registered icon registry |

Unknown keys may be treated as `ui:text`.

#### `ui:icon-picker` — Tenant Icon Registry Contract

The icon picker is **empty by default**. Core does not ship any hardcoded icons.

The tenant must pass an `iconRegistry` in `JsonPagesConfig` at bootstrap:

```typescript
// App.tsx
const config: JsonPagesConfig = {
  // ...
  iconRegistry: iconMap, // Record<string, LucideIcon> from tenant IconResolver
};
```

Core provides `iconRegistry` via `IconRegistryContext`. The Form Factory reads this context and renders only the tenant-registered icons in the picker dialog.

**Tenant responsibility:** declare all usable icons in `src/lib/IconResolver.tsx` and export `iconMap`. Pass it to `JsonPagesConfig.iconRegistry`. If `iconRegistry` is empty or not provided, the picker renders no options.

### 5.5 Path-Only Nested Selection & Expansion

In strict nested editing behavior, nested targets are represented by path segments from root to leaf:

```typescript
export type SelectionPathSegment = { fieldKey: string; itemId?: string };
export type SelectionPath = SelectionPathSegment[];
```

Rules:

- expansion and focus for nested arrays must be computed from `SelectionPath`
- matching by `fieldKey` alone is non-compliant for nested structures
- legacy flat payload fields such as `itemField` and `itemId` are not the normative nested protocol

**Why it matters:** ECIP keeps the editor machine-discoverable and prevents nested arrays from opening the wrong branch or mutating the wrong node.

---

## 6. ICE Data Attribute Contract (IDAC) v1.2

**Objective:** Mandatory data attributes so Stage and Inspector can bind selection and field/item editing without coupling to tenant DOM structure.

### 6.1 Section-Level Markup

`SectionRenderer` or equivalent Core shell wrapper provides:

- `data-section-id` for the section instance identity
- a sibling overlay element using `data-jp-section-overlay`

Tenant Views render the content root inside the Core wrapper.

### 6.2 Field-Level Binding

For every editable scalar field, the View must attach:

- `data-jp-field="<fieldKey>"`

The field key must match the schema/data path such as `title`, `description`, `label`, or `sectionTitle`.

### 6.3 Array-Item Binding

For every editable array item, the View must attach:

- `data-jp-item-id="<stableId>"`
- `data-jp-item-field="<arrayKey>"`

The preferred source of identity is `item.id`.
Index fallback is non-canonical in strict editable object arrays.

### 6.4 Compliance

All editable Stage content that participates in Studio editing must implement field and array-item bindings.
Shell-scoped instances may omit these bindings only when they are out of editing scope for the current Studio surface.

### 6.5 Strict Path Extraction For Nested Arrays

For nested array targets, the runtime selection target is expressed as `SelectionPath` from root to leaf.

Rules:

- flat identity is not sufficient for nested structures
- nested editable object arrays require stable item identity
- path derivation must remain deterministic from DOM bindings and item identity

**Why it matters:** IDAC is the bridge between tenant DOM and Studio orchestration. Without it, Stage clicks and Inspector focus become guesswork.

---

## 7. Tenant Overlay CSS Contract (TOCC) v1.1

**Objective:** The Stage iframe loads tenant HTML/CSS. Core injects overlay markup but does not own tenant overlay visuals.

### 7.1 Required Selectors

Tenant global CSS must style at least:

1. `[data-jp-section-overlay]` as absolute overlay shell with transparent base state
2. `[data-section-id]:hover [data-jp-section-overlay]` for hover state
3. `[data-section-id][data-jp-selected] [data-jp-section-overlay]` for selected state
4. `[data-jp-section-overlay] > div` for the type label

### 7.2 Z-Index

Overlay z-index must remain above section content and consistent with CIP overlay governance.

### 7.3 Responsibility Split

- Core injects wrapper, overlay DOM, and selection state
- Tenant owns overlay appearance through CSS

**Why it matters:** Without TOCC, selection rings and type labels are structurally present but visually absent.

---

## 8. Base Section Data & Settings (BSDS) v1.1

**Objective:** Standardize base schema fragments for anchors, array items, and section settings.

### 8.1 BaseSectionData

Every section data schema must extend a base with at least:

- `anchorId?: string`

Canonical Zod:

```typescript
export const BaseSectionData = z.object({
  anchorId: z.string().optional().describe('ui:text'),
});
```

### 8.2 BaseArrayItem

Every array item schema editable in the Inspector must include:

- `id?: string`

Canonical Zod:

```typescript
export const BaseArrayItem = z.object({
  id: z.string().optional(),
});
```

Recommended: generate stable UUIDs for newly created items.

### 8.3 BaseSectionSettings

Common section-level settings may be defined once and extended by capsules.

Canonical example:

```typescript
export const BaseSectionSettingsSchema = z.object({
  paddingTop: z.enum(['none', 'sm', 'md', 'lg', 'xl', '2xl']).default('md').describe('ui:select'),
  paddingBottom: z.enum(['none', 'sm', 'md', 'lg', 'xl', '2xl']).default('md').describe('ui:select'),
  theme: z.enum(['dark', 'light', 'accent']).default('dark').describe('ui:select'),
  container: z.enum(['boxed', 'fluid']).default('boxed').describe('ui:select'),
});
```

**Why it matters:** Shared base fragments keep capsules aligned and make validation, add-section defaults, and Inspector behavior deterministic.

---

## 9. AddSectionConfig (ASC) v1.1

**Objective:** Formalize the Add Section contract used by Studio.

Core-facing type:

```typescript
interface AddSectionConfig {
  addableSectionTypes: readonly string[];
  sectionTypeLabels: Record<string, string>;
  getDefaultSectionData(sectionType: string): Record<string, unknown>;
}
```

Required shape:

- `addableSectionTypes` lists addable section type keys
- `sectionTypeLabels` maps type keys to display labels
- `getDefaultSectionData(type)` returns valid default data for a new section

Core creates a new section with deterministic UUID, type, and default data.

**Why it matters:** ASC gives Studio a deterministic add-section library without hardcoding tenant knowledge into Core.

---

## 10. JsonPagesConfig & Engine Bootstrap (JEB) v1.2

**Objective:** Define the bootstrap contract between tenant app and `JsonPagesEngine`.

### 10.1 JsonPagesConfig

The tenant passes a single config object to `JsonPagesEngine`.
Required fields are:

| Field | Type | Description |
|-------|------|-------------|
| `tenantId` | string | Used by asset resolution and runtime tenant identity |
| `registry` | `{ [K in SectionType]: React.FC<SectionComponentPropsMap[K]> }` | Component registry matching MTRP keys |
| `schemas` | `Record<SectionType, ZodType>` | Data schema aggregate used by the Form Factory |
| `pages` | `Record<string, PageConfig>` | Slug to page config map |
| `siteConfig` | `SiteConfig` | Site identity and shell instance declarations |
| `themeConfig` | `ThemeConfig` | Tenant theme source of truth |
| `menuConfig` | `MenuConfig` | Menu document payload and bootstrap resolver surface |
| `refDocuments` | `Record<string, unknown>` optional | Extra JSON documents available to `$ref` resolution |
| `themeCss` | `{ tenant: string }` | Tenant CSS bridge data for Stage/runtime injection |
| `addSection` | `AddSectionConfig` | Add-section configuration |

### 10.2 JsonPagesEngine

`<JsonPagesEngine config={config} />` owns:

- route to page resolution
- section rendering orchestration
- runtime config resolution
- Studio shell integration
- wrapper/overlay injection for editable sections

Tenant does not reimplement the shell.

### 10.3 Runtime Config Resolution

The engine may combine:

- page documents
- authored config drafts (`siteConfig`, `themeConfig`, `menuConfig`, page drafts)
- referenced documents from the local JSON graph and optional `refDocuments`

This is what allows shell bindings and document indirection to resolve before rendering.

Resolution precedence rule:

- active mutable drafts take precedence over bootstrap/reference inputs
- `refDocuments` act as initial resolution/bootstrap sources unless a mutable draft for the same document is present

### 10.3.1 RefDocuments Bootstrap Rule

`refDocuments` are bootstrap and reference-resolution inputs.

They may provide the initial external JSON documents used to resolve authored `$ref` bindings at runtime or at Studio startup.

They are not, by themselves, the mutable source of truth for an active Studio editing session.

When Studio creates a mutable draft for a referenced document, that draft takes precedence over the corresponding `refDocuments` entry for subsequent resolution and editing.

Why it matters:
without this rule, Studio may resolve a referenced field from a stale bootstrap snapshot instead of from the active mutable document draft.

### 10.4 Menu Binding Clarification

`menu.json` remains the source of truth for menu structures.
`menuConfig` in bootstrap is the resolved menu document surface passed into the engine.

Shell instances do not become menu owners because bootstrap includes `menuConfig`.

**Why it matters:** JEB is the runtime boundary between sovereign tenant data and Core orchestration.

---

# OlonJS Admin Protocol (JAP) v1.3

**Objective:** Deterministic orchestration of the Studio environment.

## 1. The Sovereign Shell Topology

The Admin interface is a sovereign shell from `@olonjs/core`.

1. The Stage is an isolated iframe using postMessage and IDAC bindings
2. The Inspector consumes tenant schemas to generate editors
3. Studio actions orchestrate save, hot save, add, reorder, and delete flows

## 2. State Orchestration & Persistence

- Working Draft holds reactive local state for unsaved changes
- Inspector changes propagate into Working Draft and then Stage synchronization
- persistence channels are explicit callbacks rather than implicit file mutation on every keystroke

## 3. Context Switching

- shell-scoped selection enters global mode and maps to `site.json`
- page-local selection enters page mode and maps to the current page document

## 4. Section Lifecycle Management

1. Add Section uses `AddSectionConfig`
2. Reorder mutates the working draft array deterministically
3. Delete removes the section and clears invalid selection

## 5. Stage Isolation & Overlay

- Stage runs in an iframe so tenant CSS does not leak into Admin chrome
- overlay markup is injected by Core
- overlay appearance is styled by the tenant per TOCC

## 6. Green Build Validation

Studio and supporting build flows must remain compatible with a green `tsc && vite build` standard.

## 7. Path-Deterministic Selection & Sidebar Expansion

- section and nested focus synchronization uses path segments for nested targets
- sidebar expansion state for nested arrays derives from the full root-to-leaf path
- flat-only heuristics are non-compliant for nested structures

**Why it matters:** JAP keeps editing deterministic across shell and page scopes without collapsing Studio into tenant-specific admin logic.

---

## Compliance Model

v1.6 distinguishes between:

- architectural law
- current implementation limitations
- tenant drift

Agents and implementers must not treat narrow runtime shortcuts as final architectural law when the spec states otherwise.

| Dimension | Transitional / Narrow Implementation | Full v1.6 Architecture |
|---|---|---|
| ICE binding | Missing or partial `data-jp-*` coverage | IDAC on editable fields and array items |
| Overlay styling | Markup exists but visuals are ad hoc or absent | Core injects markup, tenant styles TOCC selectors |
| Theme handling | Core or tenant-specific semantic assumptions | Core publishes flattened tokens; tenant owns semantics |
| Design token chain | Raw utilities or literals bypass theme layers | `theme.json -> runtime vars -> tenant bridge -> local scope -> JSX` |
| Typography chain | Fonts are hardcoded or ambiguously bridged | Published semantic font chain with optional local remapping |
| Menu ownership | `header/footer` appear to own links locally | `menu.json` is SOT; shell instances bind by reference in authored config and receive resolved props at runtime |
| Referenced field editing | Resolved values are edited and saved back into the binding document | Binding document preserves `$ref`; edits persist into the referenced owner document draft |
| Shell types | Treated as conceptually reserved | Same compositional model, different scope and placement |
| Add section | Ad hoc defaults or modal wiring | `AddSectionConfig` with labels and valid default payloads |
| Bootstrap | Implicit app wiring | `JsonPagesConfig` plus `JsonPagesEngine` |
| Nested editing | Shorthands and flat adapters may survive | Deterministic path-based nested targeting |
| Array identity | Index-based fallback as primary model | Stable item identity across schema, DOM, and editor |
| Agent contract | Narrative-only understanding | Narrative plus machine-readable contract artifacts |

---

## Appendix A - Tenant Type & Code-Generation Annex

**Objective:** Make the specification sufficient to generate or audit a full tenant without a reference codebase.

**Status:** Mandatory for code-generation and governance.

Appendix A distinguishes between:

- authored document contracts, formalized by normative companion JSON Schemas
- resolved runtime contracts, consumed by Core and tenant components after document resolution

## A.1 Core-Provided Types

The following are assumed to be exported by Core and consumed by the tenant:

| Type | Description |
|------|-------------|
| `SectionType` | `keyof SectionDataRegistry` after tenant augmentation |
| `Section` | Union of `BaseSection<K>` for all K |
| `BaseSectionSettings` | Optional shared settings type |
| `MenuItem` | Minimum menu node shape such as `{ label: string; href: string }` |
| `AddSectionConfig` | Add-section contract described in ASC |
| `JsonPagesConfig` | Bootstrap contract described in JEB |

## A.2 Tenant-Provided Types

The tenant should define these in a single module such as `src/types.ts`.
That module performs module augmentation for `@olonjs/core` and exports the tenant-facing contract types.

### A.2.1 SectionComponentPropsMap

Maps section type keys to React props.
Shell-scoped instances may have additional resolved props such as materialized menu trees.

Important distinction:

- authored config in `site.json` expresses menu usage via `data.menu.$ref`
- resolved runtime props passed to the component may contain concrete `MenuItem[]`

Explicit pattern:

```typescript
import type { MenuItem } from '@olonjs/core';

export type SectionComponentPropsMap = {
  header: { data: HeaderData; settings?: HeaderSettings; menu?: MenuItem[] };
  footer: { data: FooterData; settings?: FooterSettings; menu?: MenuItem[] };
  hero: { data: HeroData; settings?: HeroSettings };
};
```

Mapped pattern:

```typescript
export type SectionComponentPropsMap = {
  [K in SectionType]:
    { data: SectionDataRegistry[K]; settings?: K extends keyof SectionSettingsRegistry ? SectionSettingsRegistry[K] : BaseSectionSettings }
};
```

Use an explicit variant when shell-scoped props differ from ordinary page sections.

### A.2.2 ComponentRegistry

The registry object must be typed as:

```typescript
export const ComponentRegistry: {
  [K in SectionType]: React.FC<SectionComponentPropsMap[K]>;
} = { /* ... */ };
```

Conventional file: `src/lib/ComponentRegistry.tsx`.

### A.2.3 PageConfig

Minimum page shape:

```typescript
export interface PageConfig {
  id?: string;
  slug: string;
  meta?: {
    title?: string;
    description?: string;
  };
  sections: Section[];
}
```

### A.2.4 SiteConfig

`site.json` owns shell structure and shell instance declaration.

Canonical direction for v1.6:

- `header` is optional and `footer` is required in `site.json`
- each shell instance must provide `id`, `type`, and `data`
- `data` is tenant-sovereign in shape
- if a shell instance uses menu data, it binds to `menu.json` through `data.menu.$ref`
- no menu means `data.menu` is omitted

Illustrative minimum shape:

```typescript
export interface JsonRef {
  $ref: string;
}

export interface SiteConfig {
  header: {
    id: string;
    type: 'header';
    data: HeaderData & { menu?: JsonRef };
    settings?: HeaderSettings;
  };
  footer: {
    id: string;
    type: 'footer';
    data: FooterData & { menu?: JsonRef };
    settings?: FooterSettings;
  };
}
```

Normative companion schema:

- [site.schema.json](/wsl.localhost/Ubuntu/home/dev/npm-jpcore/specs/site.schema.json)

Authored config rule:

- `site.json` stores reference intent in `data.menu`
- it does not canonically own the materialized menu tree
- the authored JSON contract is formalized by the companion schema above

Studio editing rule:

- if `data.menu` is a `$ref`, the editable menu draft belongs to the referenced menu document
- editing the resolved menu value must not rewrite authored `site.json` to inline the resolved array

Resolved runtime rule:

- after config resolution, shell components may receive concrete `MenuItem[]` props
- this runtime convenience does not change authorship or source of truth

### A.2.5 MenuConfig

`menu.json` is the source of truth for menu structures.
Named menu collections are allowed.

Illustrative minimum shape:

```typescript
export interface MenuConfig {
  main?: MenuItem[];
  [key: string]: MenuItem[] | undefined;
}
```

Runtime may resolve references such as `menu.json#/main` before passing concrete `MenuItem[]` into shell instances.

Normative companion schema:

- [menu.schema.json](/wsl.localhost/Ubuntu/home/dev/npm-jpcore/specs/menu.schema.json)

Authored config rule:

- `menu.json` is the authored menu source of truth
- named menu collections are formalized by the companion schema above
- shell/runtime consumers read materialized menu trees after resolution rather than redefining menu ownership

Studio persistence rule:

- if a shell instance binds `data.menu.$ref` to a branch such as `menu.json#/main` or `menu.json#/footer`
- Inspector edits to that resolved menu must persist into the referenced branch of `menu.json`
- persistence must not redirect those edits into `site.json`

### A.2.6 ThemeConfig

`theme.json` is the single source of truth for the visual token contract.

v1.6 rule:

- Core should not define tenant semantic vocabulary
- Core should publish flattenable token paths
- tenant owns semantic interpretation and bridging

Illustrative grouped-open contract:

```typescript
export interface ThemeValueMap {
  [key: string]: string | undefined;
}

export interface ThemeTypography {
  fontFamily?: ThemeValueMap;
  scale?: ThemeValueMap;
  tracking?: ThemeValueMap;
  leading?: ThemeValueMap;
  wordmark?: ThemeValueMap;
  [key: string]: ThemeValueMap | undefined;
}

export interface ThemeModes {
  [mode: string]: {
    colors?: ThemeValueMap;
    [key: string]: ThemeValueMap | undefined;
  } | undefined;
}

export interface ThemeTokens {
  colors?: ThemeValueMap;
  typography?: ThemeTypography;
  borderRadius?: ThemeValueMap;
  spacing?: ThemeValueMap;
  zIndex?: ThemeValueMap;
  modes?: ThemeModes;
  [key: string]: ThemeValueMap | ThemeTypography | ThemeModes | undefined;
}

export interface ThemeConfig {
  name: string;
  tokens: ThemeTokens;
}
```

Practical expectation:

- `tokens.colors`, `tokens.typography`, `tokens.borderRadius`, `tokens.spacing`, `tokens.zIndex`, and `tokens.modes` are canonical groups when present
- each group remains open-map and tenant-sovereign internally
- extra groups are allowed as additive extensions
- tenant naming is sovereign

## A.3 Schema Contract (SECTION_SCHEMAS)

Conventional location: `src/lib/schemas.ts`.

Contract:

- `SECTION_SCHEMAS` is a single object keyed by `SectionType`
- values are Zod schemas for section data
- base fragments such as `BaseSectionData` and `BaseArrayItem` are reused by capsules
- the app passes this aggregate to `JsonPagesEngine` as `config.schemas`

Important distinction:

- `SECTION_SCHEMAS` formalize section data contracts for component/editing/runtime surfaces
- the companion JSON Schemas formalize authored document contracts for `site.json` and `menu.json`
- these contract layers complement each other and must not be conflated

## A.4 File Paths & Data Layout

| Purpose | Path (conventional) | Description |
|---------|---------------------|-------------|
| Site config | `src/data/config/site.json` | `SiteConfig` |
| Menu config | `src/data/config/menu.json` | `MenuConfig` |
| Theme config | `src/data/config/theme.json` | `ThemeConfig` |
| Page data | `src/data/pages/<slug>.json` | `PageConfig` |
| Base schemas | `src/lib/base-schemas.ts` | Base fragments |
| Schema aggregate | `src/lib/schemas.ts` | `SECTION_SCHEMAS` |
| Registry | `src/lib/ComponentRegistry.tsx` | `ComponentRegistry` |
| Add-section config | `src/lib/addSectionConfig.ts` | `AddSectionConfig` |
| Tenant types | `src/types.ts` | augmentation and contract types |
| Bootstrap | `src/App.tsx` | builds `JsonPagesConfig` and renders `JsonPagesEngine` |

## A.5 Integration Checklist

When generating or auditing a tenant, ensure:

1. capsules exist for each section type with `View.tsx`, `schema.ts`, `types.ts`, and `index.ts`
2. base schemas define `BaseSectionData`, `BaseArrayItem`, and optional `BaseSectionSettings`
3. `src/types.ts` performs module augmentation and exports tenant contract types
4. `ComponentRegistry` is typed against `SectionType` and `SectionComponentPropsMap`
5. `SECTION_SCHEMAS` is a single keyed schema aggregate
6. `addSectionConfig` provides addable types, labels, and valid defaults
7. `App.tsx` builds `JsonPagesConfig` with pages, site, theme, menu, registry, schemas, CSS bridge data, and optional `refDocuments`
8. config/page JSON files conform to `SiteConfig`, `MenuConfig`, `ThemeConfig`, and `PageConfig`
9. themed tenants publish runtime theme variables before themed sections render
10. tenant global CSS includes TOCC selectors and semantic/theme bridge rules
11. shell instances consume menu data by reference binding rather than canonical local ownership

## A.6 Path/Nested Strictness Addendum

This addendum preserves prior obligations and adds:

1. `SelectionPathSegment` and `SelectionPath` should be exported for Studio messaging
2. nested targeting uses path segments from root to leaf
3. editable object arrays require stable item identity
4. legacy flat fields are transitional adapters, not the normative nested protocol

## A.7 Local Design Tokens Implementation Addendum

This addendum preserves prior obligations and adds:

1. tenant theme values live in `src/data/config/theme.json`
2. runtime publication is mandatory for themed tenants
3. themed sections scope owned color/radius concerns through `--local-*`
4. section-owned color/radius classes consume the local or tenant semantic layer, not hardcoded literals
5. typography consumes the published semantic font chain
6. migration shims may exist temporarily but are not the primary themed contract

Canonical implementation pattern:

```text
theme.json -> published runtime theme vars -> tenant semantic bridge -> section --local-* -> JSX classes
```

Canonical typography pattern:

```text
theme.json -> published runtime theme vars -> tenant semantic font bridge -> section typography
```

Minimal compliant example:

```tsx
<section
  style={{
    '--local-bg': 'var(--background)',
    '--local-text': 'var(--foreground)',
    '--local-primary': 'var(--primary)',
    '--local-radius-md': 'var(--theme-radius-md)',
  } as React.CSSProperties}
  className="bg-[var(--local-bg)]"
>
  <h2 className="font-display text-[var(--local-text)]">Title</h2>
  <a className="bg-[var(--local-primary)] rounded-[var(--local-radius-md)]">CTA</a>
</section>
```

Deterministic compliance checklist:

1. tenant theme source of truth exists
2. runtime publication exists
3. tenant semantic bridge exists
4. section-local scope exists when the section owns the concern
5. section-owned classes consume local or tenant semantic variables
6. primary themed values are not hardcoded

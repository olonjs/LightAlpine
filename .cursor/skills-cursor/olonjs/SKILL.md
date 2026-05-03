---
name: olonjs-tenant
description: Use when working on a OlonJS tenant, transforming the base tenant DNA into a branded tenant, adding or modifying tenant sections, maintaining schema-driven editability, or reasoning about what belongs to @olonjs/core versus the tenant.
---

# OlonJS Tenant

Use this skill for work on the OlonJS ecosystem when the task involves:

- a tenant generated from the OlonJS CLI
- `@olonjs/core`
- tenant sections/capsules
- `src/data/pages/**/*.json` or `src/data/config/*.json`
- schema-driven editing and inspector compatibility
- generator scripts that turn a base tenant into a branded tenant

Read code first. Treat documents as secondary unless they help interpret code that is otherwise ambiguous.

## Architecture Specifications 

**Normative:** OlonJS Architecture Specifications **v1.5** (`olonjsSpecs_V_1_5.md`): three-layer CSS theme bridge (engine → `:root` → `@theme`), `ThemeConfig` / appendix A.2.6, path-based Studio selection (`itemPath`), local tokens (`--local-*`), IDAC, TOCC, JSP, TBP, CIP, ECIP, JEB, JAP.

Use this document as the architectural law for each tenant; compliance is judged against it:

- `\\wsl.localhost\Ubuntu\home\dev\npm-jpcore\specs\olonjsSpecs_V_1_5.md`




## Core Model

OlonJS has a hard split between `core` and `tenant`.

- `@olonjs/core` owns routing, `/admin`, `/admin/preview`, preview stage, studio state, inspector/form factory, and shared engine behavior.
- The tenant owns sections, schemas, type augmentation, page/config JSON, theme/design layer, and local workflow scripts.
- The tenant does not implement the CMS. It implements the tenant protocol consumed by the engine.

In this ecosystem, code is the source of truth.

Compliance priority:

1. Data is bound correctly.
2. Schemas describe fields correctly.
3. Content is editable without breaking the inspector.
4. Tenant structure stays standardized.
5. Context-aware focus/highlight in the legacy admin is desirable but secondary.

## Canonical References

Use these local references when available:

- Base tenant DNA: `\\wsl.localhost\Ubuntu\home\dev\temp\alpha`
- Custom tenant reference: `\\wsl.localhost\Ubuntu\home\dev\temp\gptgiorgio`
- Core engine: `\\wsl.localhost\Ubuntu\home\dev\npm-jpcore\packages\core`
- Generator example: `\\wsl.localhost\Ubuntu\home\dev\temp\clonark\generate_olon.sh`

If these paths are missing, infer the same roles from the current workspace:

- base CLI-generated tenant
- branded tenant
- core package
- generator script

## Tenant Anatomy

Expect these files to move together:

- `src/components/<section>/View.tsx`
- `src/components/<section>/schema.ts`
- `src/components/<section>/types.ts`
- `src/components/<section>/index.ts`
- `src/lib/ComponentRegistry.tsx`
- `src/lib/schemas.ts`
- `src/lib/addSectionConfig.ts`
- `src/types.ts`
- `src/data/pages/**/*.json`
- `src/data/config/site.json`
- `src/data/config/theme.json`
- `src/data/config/menu.json`

Useful rule: if a section type changes, check all of the files above before concluding the task is done.

## What Good Work Looks Like

A good tenant change:

- stays inside tenant boundaries unless the issue is truly in `@olonjs/core`
- keeps schema, defaults, registry, and type augmentation aligned
- preserves editability for strings, lists, nested objects, CTAs, and image fields
- uses `ImageSelectionSchema`-style image fields when the content is image-driven
- keeps page content JSON-first

A suspicious tenant change:

- patches the core to fix a tenant modeling problem
- adds visual complexity without data bindings
- introduces fields into JSON that are not represented in schema
- changes a section view without updating defaults or types
- optimizes legacy context awareness at the expense of simpler, reliable editability

## Workflow 1: Base Tenant -> Branded Tenant

This is the primary workflow.

Goal:

- transform a CLI-generated base tenant into a branded tenant through a single generator script

Treat the generator script as procedural source of truth for the green build workflow.

When maintaining or authoring a generator:

1. Separate non-deterministic bootstrap from deterministic sync.
2. Make explicit which files are managed output.
3. Keep the script aligned with the current tenant code, not with stale docs.
4. Preserve tenant protocol files: sections, schemas, registries, type augmentation, config JSON, assets, shims.
5. Prefer deterministic local writes after any remote/bootstrap step.

Typical structure of a good generator:

- preflight checks
- remote/bootstrap steps such as `shadcn` or external registries
- deterministic creation/sync of tenant files
- compatibility patches for known unstable upstream payloads
- final validation commands

When asked to update a branded tenant generator:

1. Diff base tenant against branded tenant.
2. Classify differences into:
   - intended branded output
   - reusable generator logic
   - accidental drift
3. Encode only the reusable intended differences into the script.
4. Keep the output reproducible from a fresh base tenant.

## Workflow 2: Add Or Change A Section

When adding a new section type:

1. Create `View.tsx`, `schema.ts`, `types.ts`, `index.ts`.
2. Register the section in `src/lib/ComponentRegistry.tsx`.
3. Register the schema in `src/lib/schemas.ts`.
4. Add defaults and label in `src/lib/addSectionConfig.ts`.
5. Extend `SectionComponentPropsMap` and module augmentation in `src/types.ts`.
6. Add or update page JSON using the new section type.

When changing an existing section:

1. Read the section schema first.
2. Read the page JSON using it.
3. Check the view for `data-jp-field` usage and binding shape.
4. Update defaults if the data shape changed.
5. Verify the inspector still has a path to edit the content.

## Workflow 3: Images, Rich Content, Nested Routes

Images:

- Prefer structured image objects compatible with tenant base schemas.
- Assume the core supports image picking and upload flows.
- The tenant is responsible for declaring image fields in schema and rendering them coherently.

Rich editorial content:

- Tiptap-style sections are tenant-level integrations.
- Treat page JSON using `type: "tiptap"` as runtime usage examples, and section code as the real source of truth.

Nested routes:

- Files under `src/data/pages/**/*.json` may represent nested slugs.
- Preserve slug/path consistency and do not replace file-based routing with manual lists.

## Decision Rules

Use `alpha` patterns when the task is about:

- tenant DNA
- capability reference
- baseline protocol shape
- proving what the base system already supports

Use `gptgiorgio` patterns when the task is about:

- stronger branded frontend customization
- richer domain-specific sections
- image-heavy schema design
- proving how far customization can go without changing the bootstrap

Do not treat `gptgiorgio` as canonical for legacy admin context awareness.

## Default Operating Procedure

When you receive a OlonJS tenant task:

1. Identify whether the problem belongs to `core`, tenant, or generator.
2. Read the smallest code surface that proves it.
3. Prefer fixing the tenant contract before touching visual polish.
4. Keep generated and deterministic workflows reproducible.
5. State assumptions when inferring intended branded output from examples.

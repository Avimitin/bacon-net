# Signal Grid

Signal Grid is the working interface language for bacon-net. It combines the
precision of an arcade service console with the energy of rhythm-game graphics:
sharp planes, oversized type, visible structure, and small bursts of signal
color. It remains a Carbon product interface underneath, but it must never look
like a page assembled from default components.

The language now spans authentication, dashboard, cards, scores, rankings,
profile settings, and the operator console. This document is the contract for
future component and placement work.

## North star

**Make a player's network legible in five seconds.** The interface should show
what is connected, what needs attention, and the most useful next action without
making every object look equally important.

The player and operator experiences are separate modes. Player routes organize
cards, game identities, scores, rankings, and settings around player goals. The
operator console keeps infrastructure and moderation concepts in its own route
and permission boundary.

## Principles

1. **Grid before decoration.** Every composition begins with the 2x Grid. A
   visual move that does not align to the grid needs a functional reason.
2. **One plane, one job.** White planes are working content, black planes explain
   systems or relationships, and signal color identifies an action or layer.
3. **Turn relationships into graphics.** Connectors and overlaps explain a real
   account, card, profile, or data relationship. They are never ambient texture.
4. **Let type carry the energy.** Scale and weight create the boldness. Cards do
   not need rounded corners, gradients, or a stack of effects to feel expressive.
5. **Keep the route productive.** Carbon behavior, clear labels, complete states,
   keyboard flow, and readable data win over visual novelty.

## 2x Grid contract

The [IBM 2x Grid](https://www.ibm.com/design/language/2x-grid/) is the governing
system, not a background motif.

- `1U = 8px`. All spatial decisions use whole mini-units.
- Preferred spacing is `1U, 2U, 3U, 4U, 6U, 8U, 10U, 12U`.
- Responsive page grids use 4 equal columns at small widths, 8 at medium widths,
  and 16 at large widths, following Carbon breakpoints.
- Margins are part of the live area. Columns divide the space inside those
  margins; do not begin a second, unrelated grid at the viewport edge.
- Gutters are equal and type aligns to the gutter edge.
- Container dimensions use whole mini-units. Prefer `1:1`, `4:3`, `3:2`, `2:1`,
  or `16:9` when an asset has a fixed aspect ratio.
- The allowed micro-grid exceptions are 1px structural rules, 1px connector
  lines, 2px focus indicators, and type metrics from the IBM Plex/Carbon scale.
  These exceptions must still begin and end on the 8px structure.

CSS exposes the unit as `--bn-unit` and derives spatial tokens from it. New
components should consume those tokens instead of introducing one-off values.

## Color syntax

| Token | Value | Role |
| --- | --- | --- |
| Canvas | Carbon Gray 10 / `#f4f4f4` | Full-viewport field and quiet separation |
| Paper | White / `#ffffff` | Primary working surfaces |
| Ink | Carbon Gray 100 / `#161616` | Type, rules, and system-explanation planes |
| Signal blue | Blue 60 / `#0f62fe` | Primary action and the main network signal |
| Signal purple | Purple 60 / `#8a3ffc` | Secondary identity accent |
| Signal teal | Teal 50 / `#009d9a` | Secondary identity accent |
| Signal red | Red 50 / `#fa4d56` | Expressive accent; not an error without text/icon support |

Color is syntax, not decoration. Blue should dominate. Purple, teal, and red may
differentiate repeated profile surfaces, but never encode status on their own.
Status always has a label or icon and passes Carbon contrast requirements.

Do not place gradients, glass effects, glow, or photography behind product UI.

## Typography

- IBM Plex Sans, supplied by Carbon, is the default face.
- IBM Plex Mono is reserved for coordinates, indices, IDs, version strings, and
  terse system labels.
- Display headings use light weight and stepped, grid-aligned line boxes: 48px
  on small screens, 64px at medium sizes, and up to 80px on large screens.
- Section headings are sentence case. System labels are uppercase, short, and
  tracked. Body copy stays conversational and direct.
- A route has exactly one `h1`; visual size never determines heading level.

## Geometry and depth

- Corners are square by default. Radius is reserved for a future concept with a
  semantic need, not for generic friendliness.
- Flat planes use 1px rules to show hierarchy. Avoid card-on-card nesting.
- No drop shadows in the product shell or standard cards.
- Purposeful overlap is allowed inside an explanatory diagram when it shows
  ownership, flow, action/result, or zoom. It does not cross over working text.
- Interactive movement is restrained to color and content changes; layout does
  not jump on hover. Motion uses Carbon productive easing and honors reduced
  motion preferences.

## Hybrid UI translation

IBM's [Hybrid UI design guidance](https://www.ibm.com/design/language/illustration/hybrid-ui-style/design/)
informs composition, but its
[usage guidance](https://www.ibm.com/design/language/illustration/hybrid-ui-style/usage/)
says hybrid UI illustrations should not be dropped into the product itself.
Signal Grid therefore translates the method rather than copying the artifact:

- Use UI fragments, pictograms, nodes, and 1px connectors to explain a real
  product relationship.
- Keep diagrams at low-to-mid fidelity. Preserve only text that carries meaning;
  simplify incidental detail.
- Use a flat Gray 10, white, or dark UI plane as the background.
- UI fragments may overlap to show a consequence or handoff. Expressive elements
  remain flat and shadowless.
- Every diagram needs an equivalent text statement. If it explains nothing, it
  should not exist.

The dashboard account map is the reference implementation: account → bound
cards → game profiles. It is a live summary of the same data rendered below, not
a decorative hero image.

## Carbon contract

Carbon owns interaction semantics and product behavior:

- responsive grid, breakpoints, type, focus, and theme foundations;
- buttons, inputs, menus, navigation, data tables, dialogs, loading, and notices;
- keyboard behavior, accessible names, busy announcements, and modal focus;
- state patterns for loading, first use, no results, failure, permission, stale
  data, and consequential confirmation.

Signal Grid owns composition:

- task hierarchy and content order;
- plane, rule, and accent placement;
- display typography and domain-specific data grouping;
- purposeful explanatory diagrams;
- responsive arrangement within Carbon's 4/8/16-column system.

Do not override Carbon component internals to force a look. Add a product class
to the component root and style the surrounding composition. Do not add a second
component system.

## Route grammar

Signed-in task routes begin with a 16-column structural hero: ten columns
establish the task and six visualize the live system context. The dashboard
uses nine plus seven to give its denser account topology more room. At the
medium breakpoint, task heroes become five plus three on the 8-column grid while
the dashboard stacks. At small sizes both planes occupy all four columns. The
diagram is built from 8px grid lines and three overlapping UI fragments; its
caption and metrics must come from the route's real state.

| Surface | Signal color | Primary job | Working composition |
| --- | --- | --- | --- |
| Login / register | Blue on black | Establish player identity | Network diagram + bounded form |
| Dashboard | Blue | Understand the whole account | Topology + summary + profile matrix |
| Cards | Blue | Manage physical access | Bind rail + card/profile ledger |
| Scores | Purple | Scan personal history | Page filters + dense archive table |
| Rankings | Teal | Resolve competitive position | Four-step query + dark result plane |
| Profile settings | Red | Tune one game identity | Identity strip + versioned editor |
| Operator console | Blue on black | Control service state | Security strip + domain workspaces |

Accent colors identify a route or repeated data layer; they do not replace
status language. The operator's black copy plane is a mode boundary, while the
player routes keep the primary copy plane white.

## Surface hierarchy

All routes follow this sequence when the task needs each layer:

1. **Hero:** location, one concise value statement, a real system diagram, and
   at most one page-level action.
2. **Context strip:** only when identity or permission needs to remain visible
   while working (profile identity and operator authorization).
3. **Section heading:** a numbered label, direct task title, and one sentence of
   operational guidance.
4. **Working plane:** Carbon inputs, tabs, tables, and dialogs arranged by the
   route's task rather than by component type.
5. **Result or state:** content, first-use guidance, no-result response, or a
   recoverable error in the same geometric footprint.

The dashboard applies that hierarchy as follows:

1. **Hero:** player context, one concise value statement, and one primary action
   (`Explore scores`). Card management is secondary.
2. **Account map:** an equivalent visual model of account, cards, and profiles.
3. **Summary strip:** three bounded account facts, readable without interaction.
4. **Identity layer:** the main working area. Each game profile links to its
   settings and shows only player ID and available versions.
5. **Access layer:** a secondary card rail with identifiers, cached Konami ID,
   profile count, and management entry point.

Masked PINs and repeated card IDs are intentionally removed from profile cards;
they consumed attention without helping the dashboard's primary task.

## Responsive behavior

- Large (16 columns): generic route heroes use a 10/6 split and task work uses
  route-specific whole-column spans. On the dashboard, profile work occupies 12
  columns and the access rail occupies 4, separated by the equal Carbon gutter.
- Medium (8 columns): generic route heroes use a 5/3 split and side-by-side work
  uses 3/5. The dashboard's richer topology stacks at full width; profile cards
  stay two-up when labels have room.
- Small (4 columns): actions, metrics, profiles, and access rail become single
  column. Query controls become a numbered sequence and wide tables scroll only
  inside their bounded data plane. The account diagram repositions on the same
  four-column structure.
- Navigation becomes a Carbon side-nav disclosure. The active route remains
  programmatic and all controls remain reachable at 200% zoom.

No component may depend on viewport clipping to hide overflow. Long user names,
IDs, localized labels, zero profiles, zero cards, and more than four games must
remain legible.

## Content voice

Use short, active labels: “Explore scores,” “Manage cards,” “Open settings.”
Describe the player's model, not implementation tables or API resources. Empty
states explain what belongs in the space, why it is empty, and the next useful
action. Errors state what failed and offer retry when retry is meaningful.

## Definition of done for new surfaces

- The layout can be drawn as equal 4, 8, or 16 columns before components are
  placed.
- Every spatial value resolves to the mini-unit scale or is an approved micro
  exception.
- The first viewport communicates location, current state, and likely next task.
- There is one page-level primary action and one `h1`.
- Loading and exceptional states preserve the final geometry.
- Keyboard order, focus visibility, landmarks, accessible names, and status text
  are verified at narrow and wide widths.
- Closed dialogs do not affect route geometry; open dialogs fit the four-column
  viewport, contain focus, and close with Escape.
- Long content, 200% zoom, reduced motion, and forced colors do not break the
  structure.

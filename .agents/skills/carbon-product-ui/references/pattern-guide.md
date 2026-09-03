# Carbon product-pattern guide

This reference distills the decisions that matter most when designing or reviewing a React product with Carbon. It is not a copy of the Carbon manual.

## Source provenance

The guidance was derived from the official `carbon-design-system/carbon-website` pattern MDX at commit [`df723531e56036f90bac8b1bbec7a0414a285063`](https://github.com/carbon-design-system/carbon-website/tree/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns):

- [Patterns overview](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/overview.mdx)
- [Global header](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/global-header/index.mdx)
- [Login](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/login-pattern/index.mdx)
- [Forms](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/forms-pattern/index.mdx)
- [Filtering](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/filtering/index.mdx)
- [Empty states](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/empty-states-pattern/index.mdx)
- [Loading](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/loading-pattern/index.mdx)
- [Dialogs](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/dialog-pattern/index.mdx)
- [Disclosures](https://github.com/carbon-design-system/carbon-website/blob/df723531e56036f90bac8b1bbec7a0414a285063/src/pages/patterns/disclosures-pattern/index.mdx)

Check the current official MDX when exact component behavior or a recently changed pattern matters. Keep conclusions tied to product goals; IBM-specific brand rules are not automatically requirements for non-IBM products.

## Pattern decision matrix

| Concern | Carbon-derived decision | Evidence to seek in the product |
| --- | --- | --- |
| Shell | Header-only is for a small set of peer sections; combine header and left panel when navigation has depth or persistent submenus. | Route map, role map, active item, narrow-screen behavior |
| Orientation | The shell must communicate location, account, and active mode. Detail pages need a breadcrumb back to their parent. | Active nav state, page title, breadcrumbs, mode/tenant indicator |
| State preservation | Preserve task context and filters, commonly in the URL. | Reload, back/forward, deep link, shared URL |
| Task organization | Organize around user goals and audiences rather than technical limitations or storage topology. | Labels, grouping, primary tasks, absence of raw schema concepts |
| Forms | Group logically, progressively disclose conditional or advanced fields, validate inline after blur, and explain server errors with inline notifications. | Field error behavior, submit state, long-form hierarchy |
| Login | Use a title containing “Log in”; protect account enumeration with a generic credentials error; clear/refocus appropriately after failure; provide recovery when the product supports it. | Failure path, keyboard flow, recovery link, session-expiry return path |
| Filtering | Choose single, multi, category, batch, or instant filters based on the user's decision and response latency. Show applied filters and provide clear-all. | Filter semantics, applied count/tags, reset, URL/API contract |
| Empty states | Explain what belongs here, why it is empty, and the next useful action. Distinguish first-use, user-cleared, no-results, permission, and system failures. | Purpose-built copy and action rather than a generic notification |
| Loading | Skeletons represent initial data/container shape; inline loaders represent local actions; progress is better for longer work; progressive batches suit dashboards and large datasets. | Shape stability, `aria-busy`/announcements, retry/cancel behavior |
| Dialogs | Keep them short, focused, user-initiated, and sparse. Use danger treatment for irreversible confirmation and keep large/complex work on a page. | Focus trap/return, disabled repeated action, consequence copy |
| Profile disclosure | A global-header product with accounts should offer session/profile/settings/logout through an accessible profile menu. | Trigger name, keyboard support, relevant session context |

## Information architecture review

Start by drawing a small route tree annotated with persona and task. Flag these smells:

- end-user and operator navigation shown together without role or mode separation;
- major tasks hidden in one giant component or a long row of tabs;
- detail pages with only a handwritten “back” link;
- labels derived from database tables, transport fields, or API implementation;
- every object and action receiving equal visual weight;
- navigation state that disappears on reload or cannot be deep-linked;
- user-created or unbounded entities placed directly in side navigation.

For a simple end-user product, a global header with a few peer routes can be correct. For an operations console, prefer a dedicated shell with side navigation, routable sections, breadcrumbs, scoped context such as shop or tenant, and page-level actions.

## Page composition

A robust page generally has these semantic layers, omitting any that do not help the task:

1. page context and one `h1`;
2. a short purpose or status line and primary action;
3. main working content;
4. secondary details or recent activity;
5. inline state feedback;
6. a purpose-built empty or error state.

Use Carbon `Grid`/`Column` and spacing, type, layer, and color tokens to establish rhythm. Set intentional content width and full-viewport background behavior. A library theme and a collection of tiles are not a layout system by themselves. Keep custom CSS at the composition layer; avoid hard-coded copies of Carbon values and selectors that depend on component internals.

Dashboard questions:

- What decision or action should be possible within five seconds?
- Does the first viewport show status, recent activity, and the likely next action?
- Are internal identifiers or low-value metadata displacing meaningful content?
- Is card or tile weight proportional to user importance?
- Does progressive loading keep independent sections usable?

## Collections, tables, rankings, and search

Estimate the upper-bound row and group counts before choosing a rendering shape. Rendering a table or tile for every server-side object is not viable for an unbounded dataset.

Use an explicit API contract such as cursor or page, limit, stable sort key, structured filters, and total or next-cursor metadata. Make sorting and filtering server-owned when the dataset can outgrow a browser. Debounce and cancel obsolete searches. Avoid array indexes as row identity when the domain has stable keys.

Choose filters that match domain questions such as game, song, chart, shop, status, and date. “Substring over JSON” is an implementation leak, not a user search model. Show active filters, allow reset, and preserve them in the route query. For rankings, let the user select or search a song and render one bounded leaderboard instead of mounting every song at once.

For operator tables, include only task-relevant fields, server pagination, sort, and filters, explicit row actions, clear refresh or staleness state, and role-scoped bulk actions. Raw document editing may exist in a separately permissioned developer tool, never as the ordinary management model.

## Forms and settings

Give inputs stable labels and helpful constraints. Placeholder text is not a label. On blur, set Carbon `invalid` and `invalidText` for correctable field errors; reserve an inline notification for submission- or system-level errors. Disable submit while a request is in flight and make retry outcomes unambiguous.

Do not send an entire stale settings object when the user changed one field. Prefer field-scoped commands or versioned patches with optimistic-concurrency handling. Track dirty state, make save scope obvious, and warn before abandoning unsaved changes. Put advanced but safe fields in a clear progressive disclosure; do not expose credentials, secrets, plaintext PINs, or unconstrained JSON merely because they exist in storage.

Registration with optional onboarding should tolerate partial progress deliberately. If account creation commits before card binding, present them as separate steps and make retry or resume clear rather than disguising a partial success as one atomic form.

## Async and exceptional states

Model these explicitly for each data surface:

- initial load;
- refresh with existing data;
- local mutation in progress;
- first use or no data;
- filters produce no results;
- permission denied;
- system or network failure;
- stale data or update conflict;
- partial success;
- cancellation or route change.

Use skeleton geometry close to the final containers so content does not jump. Add cancellation for obsolete fetches and ensure development double effects do not create duplicate writes. Tell assistive technology when a region becomes busy and when it finishes or fails.

## Accessibility acceptance checks

- The first keyboard control can skip repeated navigation and lands on the main region.
- Each route has one descriptive `h1`; headings are not chosen for visual size alone.
- Navigation, main, search, and form landmarks are semantic and uniquely labeled when repeated.
- Active navigation is exposed programmatically, such as `aria-current="page"`.
- All navigation remains reachable at narrow widths and at 200% zoom.
- Every icon-only control has a task-specific accessible name.
- Every field, including advanced editors, has an accessible name and associated error.
- A modal receives focus, traps it, closes by the expected keyboard path, and returns focus to its trigger.
- Loading, errors, completion, and updated result counts are announced without stealing focus unnecessarily.
- Decorative images use empty alt text; informative images have equivalent text.
- Status and selection never depend on color alone.

## Meaningful frontend verification

Prefer tests tied to user-observable invariants:

- role-specific navigation and unauthorized-route behavior;
- active location, deep links, breadcrumbs, and state restored from the URL;
- field validation, generic authentication error, focus after failure, and duplicate-submit prevention;
- first-use, no-results, permission, server-failure, retry, and partial-success states;
- paginated, sorted, and filtered API requests plus stale-response cancellation;
- dialog consequence copy, focus return, and exactly-once mutation behavior;
- axe checks, keyboard flows, zoom or narrow screenshots, and focus visibility;
- bounded DOM and render cost with representative large datasets;
- lazy loading and code splitting for heavy operator routes when bundle evidence warrants it.

Snapshot-only tests and assertions that a Carbon class name exists do not demonstrate these outcomes.

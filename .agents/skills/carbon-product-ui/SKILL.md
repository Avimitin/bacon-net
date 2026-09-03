---
name: carbon-product-ui
description: Design, implement, or review task-focused React product interfaces built with IBM Carbon. Use for Carbon information architecture, UI Shell/navigation, dense data views, forms, loading/empty/error states, dialogs, responsive behavior, accessibility, and frontend quality; do not trigger for unrelated React work that does not use Carbon.
---

# Carbon Product UI

Treat Carbon as a system for composing user workflows, not as a substitute for product design. A page can use only Carbon components and still have weak hierarchy, navigation, content, states, or scale behavior.

## Establish the product model

Before changing component code, inspect enough of the application to understand:

- the distinct user personas and permission boundaries;
- the primary task for each route and the most common path through those tasks;
- drill-down relationships between overview, collection, and detail pages;
- realistic data volume and whether filtering, sorting, and pagination are client- or server-owned;
- loading, first-use, no-results, permission, failure, stale-data, and destructive-action states;
- current screenshots at representative desktop and narrow widths.

Do not organize the interface around database tables, API routes, component names, or raw storage objects unless the actual audience is a developer performing that exact task. Separate materially different personas or modes, such as end users and operators, when combining them would blur permissions or navigation.

For a substantial review, redesign, shell, form, or data-heavy page, read [references/pattern-guide.md](references/pattern-guide.md). It contains the distilled Carbon guidance, source provenance, and acceptance checks. For a narrow component correction, read only the relevant section.

## Choose the structure before components

Define the page in this order:

1. State the user's goal and the completion condition in one sentence.
2. Choose the shell and route hierarchy based on task depth and persona.
3. Write the content hierarchy: page title, context, primary action, main data, supporting data, and exceptional states.
4. Map each interaction to a Carbon pattern and then to components.
5. Add a small product styling layer using Carbon grid, type, spacing, layer, and color tokens.

Header-only navigation suits a small number of peer sections. Use a header plus side navigation for deeper or operator-oriented products. Show the active location, move navigation appropriately at narrow widths, preserve useful state in the URL, and use breadcrumbs on drill-down pages.

Prefer one clear page-level primary action. Give information visual weight according to its task value rather than rendering every tile, tab, or field equally. Carbon permits purposeful composition; avoiding all product CSS commonly produces an unfinished layout.

## Design data and state behavior

- For large or unbounded collections, require server-side pagination, filtering, and sorting contracts. Do not fetch the complete corpus and hide it in the browser.
- Keep filter and page state in the URL when users may navigate away, reload, bookmark, or share the view.
- Use meaningful domain labels. Do not expose raw table names, JSON-search terminology, internal IDs, or editable JSON in an ordinary user workflow.
- Use skeletons for initial container/data loading, inline loading for a local action, and progress for work that is not momentary. Announce busy and completion states accessibly.
- Design first-use, no-results, permission, system-error, and unavailable states separately. Give the user a concise explanation and a prioritized next action where one exists.
- Use dialogs only for short, user-initiated tasks or consequential confirmation. Use a transactional danger modal for irreversible work, disable its action while submitting, and keep complex work on a page.

## Implement with semantic Carbon composition

- Use semantic links for navigation and buttons for actions; do not simulate navigation with a generic click handler.
- Use the Carbon responsive grid and tokens rather than repeated one-off inline layout styles or overrides of component internals.
- Give every page one `h1`, preserve heading order, add a skip-to-main link, and label navigation/main/search/form landmarks.
- Ensure every input has an accessible name. Validate at the field when possible, use an inline notification for server-wide errors, and prevent duplicate submissions.
- Use tags for status or categorization, not as a generic container for identifiers, account controls, or navigation.
- Put account/session actions in a keyboard-operable profile disclosure when the product has a global header.
- Preserve focus across route changes, dialogs, validation failures, and async completion. Do not rely on color alone.

When editing an established interface, preserve valid domain behavior and explicit user choices. Refactor incrementally unless the user asks for a broad redesign. Do not introduce a second component system to solve a composition problem Carbon already covers.

## Validate outcomes

Verification should exercise behavior, not merely snapshots or component presence:

- build, lint, type-check, and focused interaction tests;
- keyboard-only navigation, focus order/return, skip link, and dialog trapping;
- automated accessibility checks plus a manual screen-reader/landmark pass for major flows;
- narrow, medium, and wide layouts; 200% zoom; long labels; empty and large data;
- slow, failed, stale, canceled, and repeated requests;
- deep links, refresh, back/forward navigation, and URL-restored filters;
- destructive confirmation and duplicate-submit prevention;
- bundle and render cost for data-heavy routes.

For reviews, report each material finding with evidence, user or operational impact, a recommended pattern, and a testable acceptance criterion. Separate correctness/accessibility defects from taste. Lead with the few changes that improve the task model; do not turn the output into a component shopping list.

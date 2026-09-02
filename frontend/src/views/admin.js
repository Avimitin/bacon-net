import { api, tokens } from "../api.js";
import { el, link, jsonField, skeleton, emptyState, humanError, badge } from "../ui.js";

// sub routes: [] tables · ["table", name] docs · ["table", name, id|"new"] editor
export async function viewAdmin(main, sub, rerender) {
  if (!tokens.admin) return renderGate(main, rerender);

  try {
    if (sub[0] === "table" && sub.length === 3) {
      await adminEditor(main, sub[1], sub[2]);
    } else if (sub[0] === "table" && sub.length === 2) {
      await adminDocs(main, sub[1]);
    } else {
      await adminTables(main);
    }
  } catch (err) {
    if (err.status === 401) {
      tokens.admin = null;
      return renderGate(main, rerender, "Token rejected or expired — enter it again.");
    }
    main.replaceChildren(
      el("div", { class: "error-box" }, humanError(err)),
      link("#/admin", el("button", { class: "btn ghost" }, "← back to admin"))
    );
  }
}

function renderGate(main, rerender, message) {
  const input = el("input", {
    class: "input mono",
    type: "password",
    placeholder: "admin bearer token",
  });
  const error = el("p", { class: "form-error", role: "alert" }, message || "");
  const form = el(
    "form",
    {
      class: "form",
      onsubmit: async (ev) => {
        ev.preventDefault();
        const value = input.value.trim();
        if (!value) return;
        tokens.admin = value;
        rerender();
      },
    },
    field("Admin token", input),
    error,
    el("button", { class: "btn primary block", type: "submit" }, "Unlock admin area")
  );

  main.replaceChildren(
    el("h2", { class: "page-title" }, "Admin"),
    el("section", { class: "panel narrow" },
      el("p", { class: "muted" },
        "Operator area. The admin token is separate from your player login and is stored in this browser only."),
      form
    )
  );
}

async function adminTables(main) {
  main.replaceChildren(skeleton(4));
  const [{ tables }, { cards }] = await Promise.all([api.tables(), api.cardsAll()]);

  main.replaceChildren(
    el("div", { class: "panel-head page-head" },
      el("h2", { class: "page-title" }, "Admin — tables"),
      el("div", { class: "chips" },
        badge(`${cards.length} cards seen`, "badge-soft"),
        el("button", {
          class: "btn ghost small",
          type: "button",
          onclick: () => {
            tokens.admin = null;
            location.reload();
          },
        }, "forget token"))
    ),
    tables.length
      ? el("div", { class: "stack" },
          ...tables.map((t) =>
            el("div", { class: "panel row-card" },
              link(`#/admin/table/${encodeURIComponent(t.name)}`,
                el("strong", { class: "mono" }, t.name)),
              el("span", { class: "muted" }, `${t.count} doc${t.count === 1 ? "" : "s"}`),
              el("button", {
                class: "btn danger small",
                type: "button",
                onclick: async () => {
                  if (!confirm(`Drop table "${t.name}" and all its documents?`)) return;
                  await api.dropTable(t.name);
                  location.hash = "#/admin";
                  route_refresh();
                },
              }, "drop")
            )
          ))
      : emptyState("No tables")
  );

  function route_refresh() {
    // re-render current admin route in place
    adminTables(main).catch(() => {});
  }
}

async function adminDocs(main, table) {
  main.replaceChildren(skeleton(5));
  const { docs } = await api.docs(table);

  const filter = el("input", {
    class: "input filter",
    type: "search",
    placeholder: "filter (substring over JSON)…",
  });
  const listEl = el("div", { class: "stack" });

  const renderList = () => {
    const q = filter.value.toLowerCase();
    const matches = q
      ? docs.filter((d) => JSON.stringify(d).toLowerCase().includes(q))
      : docs;
    if (!matches.length) {
      listEl.replaceChildren(emptyState(docs.length ? "No matches" : "Table is empty"));
      return;
    }
    const rows = matches.map((doc) =>
      link(
        `#/admin/table/${encodeURIComponent(table)}/${encodeURIComponent(doc._id)}`,
        el(
          "div",
          { class: "panel row-card hoverable" },
          el("code", { class: "mono doc-id" }, `#${doc._id}`),
          el("span", { class: "muted summary" }, summarize(doc))
        )
      )
    );
    listEl.replaceChildren(...rows);
  };
  filter.addEventListener("input", renderList);
  renderList();

  main.replaceChildren(
    el("div", { class: "crumbs" },
      link("#/admin", "← admin"),
      el("span", { class: "muted" }, table)
    ),
    el("div", { class: "panel-head page-head" },
      el("h2", { class: "page-title" }, table),
      link(`#/admin/table/${encodeURIComponent(table)}/new`,
        el("button", { class: "btn primary small" }, "+ new document"))
    ),
    filter,
    listEl
  );
}

async function adminEditor(main, table, id) {
  const isNew = id === "new";
  main.replaceChildren(skeleton(5));

  let initial = "{}";
  if (!isNew) {
    const doc = await api.doc(table, id);
    initial = JSON.stringify(doc, null, 2);
  }

  const notice = el("p", { class: "notice", role: "status" });
  const editor = jsonField("Document JSON", initial);

  const saveBtn = el("button", {
    class: "btn primary",
    type: "button",
    onclick: async () => {
      const parsed = editor.validate();
      if (!parsed) return;
      notice.textContent = "";
      try {
        const saved = isNew
          ? await api.create(table, parsed)
          : await api.replace(table, id, parsed);
        location.hash = `#/admin/table/${encodeURIComponent(table)}/${encodeURIComponent(saved._id)}`;
      } catch (err) {
        notice.textContent = `Save failed: ${humanError(err)}`;
        notice.className = "notice bad";
      }
    },
  }, isNew ? "Create" : "Save (PUT)");
  editor.textarea.addEventListener("input", () => {
    saveBtn.disabled = !editor.validate();
  });

  const parts = [
    el("div", { class: "crumbs" },
      link(`#/admin/table/${encodeURIComponent(table)}`, `← ${table}`),
      el("span", { class: "muted" }, isNew ? "new document" : `#${id}`)
    ),
    el("h2", { class: "page-title" }, isNew ? "New document" : `Document #${id}`),
    el("section", { class: "panel" }, editor.field),
    el("div", { class: "actions" }, saveBtn),
    notice,
  ];

  if (!isNew) {
    const patchField = jsonField("Merge patch (top-level merge)", "{}");
    const patchBtn = el("button", {
      class: "btn ghost",
      type: "button",
      onclick: async () => {
        const parsed = patchField.validate();
        if (!parsed) return;
        try {
          const updated = await api.patch(table, id, parsed);
          editor.textarea.value = JSON.stringify(updated, null, 2);
          editor.validate();
          notice.textContent = "Patch applied.";
          notice.className = "notice ok";
        } catch (err) {
          notice.textContent = `Patch failed: ${humanError(err)}`;
          notice.className = "notice bad";
        }
      },
    }, "Apply patch (PATCH)");
    patchField.textarea.addEventListener("input", () => {
      patchBtn.disabled = !patchField.validate();
    });

    const deleteBtn = el("button", {
      class: "btn danger",
      type: "button",
      onclick: async () => {
        if (!confirm(`Delete ${table} #${id}?`)) return;
        await api.deleteDoc(table, id);
        location.hash = `#/admin/table/${encodeURIComponent(table)}`;
      },
    }, "Delete document");

    parts.push(el("section", { class: "panel" }, patchField.field, el("div", { class: "actions" }, patchBtn)));
    parts.push(el("div", { class: "actions" }, deleteBtn));
  }

  main.replaceChildren(...parts);
}

function summarize(doc) {
  const parts = [];
  for (const [key, value] of Object.entries(doc)) {
    if (key === "_id") continue;
    if (value === null || ["string", "number", "boolean"].includes(typeof value)) {
      parts.push(`${key}: ${JSON.stringify(value)}`);
    }
    if (parts.length >= 4) break;
  }
  return parts.join("  ·  ");
}

function field(labelText, control) {
  return el("label", { class: "field" }, el("span", { class: "field-label" }, labelText), control);
}

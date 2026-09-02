import { api } from "./api.js";
import "./style.css";

const app = document.getElementById("app");

// ---------- helpers ----------

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  for (const child of children) {
    if (child == null) continue;
    node.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
  return node;
}

function link(hash, ...children) {
  return el("a", { href: hash }, ...children);
}

function showError(target, err) {
  target.replaceChildren(el("div", { class: "error" }, `Error: ${err.message}`));
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

// ---------- shell ----------

async function renderShell() {
  app.replaceChildren();
  const title = link("#/cards", el("span", { class: "title" }, "bacon-net webui"));
  const subtitle = el("span", { class: "subtitle" }, "…");
  const header = el(
    "header",
    {},
    el("div", { class: "brand" }, title, subtitle),
    el("nav", {}, link("#/cards", "Cards"), link("#/tables", "Tables"))
  );
  const main = el("main", {});
  app.append(header, main);
  api
    .config()
    .then((cfg) => {
      const arcade = cfg.arcade ? `${cfg.arcade} — ` : "";
      subtitle.textContent = `${arcade}${cfg.ip}:${cfg.port}`;
    })
    .catch(() => {
      subtitle.textContent = "server unreachable";
    });
  return main;
}

// ---------- views ----------

async function viewCards(main) {
  main.replaceChildren(el("h2", {}, "Cards"));
  try {
    const { cards } = await api.cards();
    if (!cards.length) {
      main.append(el("p", { class: "muted" }, "No cards found."));
      return;
    }
    const grid = el("div", { class: "grid" });
    for (const card of cards) {
      const name = card.entries.find((e) => e.name)?.name;
      const tile = el(
        "div",
        { class: "card tile" },
        el("div", { class: "card-num" }, card.card),
        name ? el("div", { class: "player-name" }, name) : null,
        el(
          "ul",
          { class: "entries" },
          ...card.entries.map((e) =>
            el(
              "li",
              {},
              link(`#/table/${encodeURIComponent(e.table)}/${encodeURIComponent(e.id)}`,
                `${e.table} #${e.id}`)
            )
          )
        )
      );
      grid.append(tile);
    }
    main.append(grid);
  } catch (err) {
    showError(main, err);
  }
}

async function viewTables(main) {
  main.replaceChildren(el("h2", {}, "Tables"));
  try {
    const { tables } = await api.tables();
    if (!tables.length) {
      main.append(el("p", { class: "muted" }, "No tables."));
      return;
    }
    const list = el("div", { class: "table-list" });
    for (const t of tables) {
      const dropBtn = el(
        "button",
        {
          class: "danger small",
          onclick: async () => {
            if (!confirm(`Drop table "${t.name}" and all its documents?`)) return;
            try {
              await api.dropTable(t.name);
              route();
            } catch (err) {
              alert(`Drop failed: ${err.message}`);
            }
          },
        },
        "drop"
      );
      list.append(
        el(
          "div",
          { class: "card row" },
          link(`#/table/${encodeURIComponent(t.name)}`, el("strong", {}, t.name)),
          el("span", { class: "muted" }, `${t.count} doc${t.count === 1 ? "" : "s"}`),
          dropBtn
        )
      );
    }
    main.append(list);
  } catch (err) {
    showError(main, err);
  }
}

async function viewTable(main, table) {
  const filter = el("input", {
    type: "search",
    placeholder: "filter (substring match on JSON)…",
    class: "filter",
  });
  const listEl = el("div", { class: "doc-list" });
  main.replaceChildren(
    el(
      "div",
      { class: "view-head" },
      el("h2", {}, `Table: ${table}`),
      el("div", { class: "actions" },
        link(`#/table/${encodeURIComponent(table)}/new`, el("button", {}, "+ new document")),
        link("#/tables", el("button", { class: "ghost" }, "← tables")))
    ),
    filter,
    listEl
  );

  let docs = [];
  try {
    ({ docs } = await api.docs(table));
  } catch (err) {
    showError(listEl, err);
    return;
  }

  const renderList = () => {
    const q = filter.value.toLowerCase();
    const matches = q
      ? docs.filter((d) => JSON.stringify(d).toLowerCase().includes(q))
      : docs;
    listEl.replaceChildren();
    if (!matches.length) {
      listEl.append(el("p", { class: "muted" }, docs.length ? "No matches." : "Table is empty."));
      return;
    }
    for (const doc of matches) {
      listEl.append(
        link(
          `#/table/${encodeURIComponent(table)}/${encodeURIComponent(doc._id)}`,
          el(
            "div",
            { class: "card row" },
            el("code", { class: "doc-id" }, `#${doc._id}`),
            el("span", { class: "summary muted" }, summarize(doc))
          )
        )
      );
    }
  };
  filter.addEventListener("input", renderList);
  renderList();
}

function jsonField(labelText, value) {
  const textarea = el("textarea", { class: "json-editor", spellcheck: "false" });
  textarea.value = value;
  const status = el("div", { class: "json-status ok" }, "valid JSON");
  const validate = () => {
    try {
      const parsed = JSON.parse(textarea.value);
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error("must be a JSON object");
      }
      status.textContent = "valid JSON";
      status.className = "json-status ok";
      return parsed;
    } catch (err) {
      status.textContent = `invalid JSON: ${err.message}`;
      status.className = "json-status bad";
      return null;
    }
  };
  textarea.addEventListener("input", validate);
  const pretty = el(
    "button",
    {
      class: "ghost small",
      onclick: () => {
        const parsed = validate();
        if (parsed) textarea.value = JSON.stringify(parsed, null, 2);
      },
    },
    "pretty-print"
  );
  validate();
  return { field: el("div", { class: "json-field" }, el("label", {}, labelText, pretty), textarea, status), textarea, validate };
}

async function viewEditor(main, table, id) {
  const isNew = id === "new";
  main.replaceChildren(el("h2", {}, isNew ? `New document in ${table}` : `${table} #${id}`));

  let initial = "{}";
  let doc = null;
  if (!isNew) {
    try {
      doc = await api.doc(table, id);
    } catch (err) {
      showError(main, err);
      main.append(link(`#/table/${encodeURIComponent(table)}`, "← back"));
      return;
    }
    initial = JSON.stringify(doc, null, 2);
  }

  const back = link(`#/table/${encodeURIComponent(table)}`, el("button", { class: "ghost" }, "← back"));
  const notice = el("div", { class: "notice" });

  const editor = jsonField("Document JSON", initial);
  const saveBtn = el(
    "button",
    {
      onclick: async () => {
        const parsed = editor.validate();
        if (!parsed) return;
        notice.textContent = "";
        try {
          const saved = isNew
            ? await api.create(table, parsed)
            : await api.replace(table, id, parsed);
          location.hash = `#/table/${encodeURIComponent(table)}/${encodeURIComponent(saved._id)}`;
        } catch (err) {
          notice.textContent = `Save failed: ${err.message}`;
          notice.className = "notice bad";
        }
      },
    },
    isNew ? "Create" : "Save (PUT)"
  );
  editor.textarea.addEventListener("input", () => {
    saveBtn.disabled = !editor.validate();
  });

  main.append(
    el("div", { class: "view-head" }, el("span", {}), el("div", { class: "actions" }, back)),
    editor.field,
    el("div", { class: "actions" }, saveBtn),
    notice
  );

  if (!isNew) {
    const patch = jsonField("Merge patch (JSON object, PATCHed into the doc)", "{}");
    const patchBtn = el(
      "button",
      {
        class: "ghost",
        onclick: async () => {
          const parsed = patch.validate();
          if (!parsed) return;
          try {
            const updated = await api.patch(table, id, parsed);
            editor.textarea.value = JSON.stringify(updated, null, 2);
            editor.validate();
            notice.textContent = "Patch applied.";
            notice.className = "notice ok";
          } catch (err) {
            notice.textContent = `Patch failed: ${err.message}`;
            notice.className = "notice bad";
          }
        },
      },
      "Apply patch (PATCH)"
    );
    patch.textarea.addEventListener("input", () => {
      patchBtn.disabled = !patch.validate();
    });

    const deleteBtn = el(
      "button",
      {
        class: "danger",
        onclick: async () => {
          if (!confirm(`Delete ${table} #${id}?`)) return;
          try {
            await api.deleteDoc(table, id);
            location.hash = `#/table/${encodeURIComponent(table)}`;
          } catch (err) {
            notice.textContent = `Delete failed: ${err.message}`;
            notice.className = "notice bad";
          }
        },
      },
      "Delete document"
    );

    main.append(el("hr", {}), patch.field, el("div", { class: "actions" }, patchBtn), el("hr", {}), deleteBtn);
  }
}

// ---------- router ----------

async function route() {
  const main = await renderShell();
  const hash = location.hash.replace(/^#\/?/, "");
  const parts = hash.split("/").filter(Boolean).map(decodeURIComponent);

  if (parts[0] === "tables") {
    await viewTables(main);
  } else if (parts[0] === "table" && parts.length === 2) {
    await viewTable(main, parts[1]);
  } else if (parts[0] === "table" && parts.length === 3) {
    await viewEditor(main, parts[1], parts[2]);
  } else {
    await viewCards(main);
  }
}

window.addEventListener("hashchange", route);
route();

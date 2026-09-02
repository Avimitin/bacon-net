import { api, getGames, gameForProfileTable } from "../api.js";
import { el, link, jsonField, skeleton, humanError, badge } from "../ui.js";
import { IIDX_FIELDS } from "../schema.js";

export async function viewSettings(main, table, docId) {
  main.replaceChildren(skeleton(5));
  const [doc, games] = await Promise.all([api.profile(table, docId), getGames()]);
  const game = gameForProfileTable(games, table);
  const isIIDX = game?.key === "iidx";

  const versions = Object.keys(doc.version || {}).sort(
    (a, b) => Number(a) - Number(b)
  );
  let activeVer = versions[versions.length - 1] ?? null;
  // working copy: every nested edit happens here, then the WHOLE map is
  // PATCHed back (server merge is top-level only)
  let work = structuredClone(doc.version || {});

  const notice = el("p", { class: "notice", role: "status" });

  // ---- quick edit: name + pin ----
  const nameInput = el("input", { class: "input", type: "text", value: doc.name ?? "" });
  const pinInput = el("input", {
    class: "input mono",
    type: "text",
    value: String(doc.pin ?? ""),
    maxlength: "4",
    inputmode: "numeric",
  });

  // ---- version tabs + per-version panel ----
  const versionBody = el("div", {});
  const tabs = el(
    "div",
    { class: "tabs" },
    ...versions.map((v) =>
      el("button", {
        class: "tab",
        type: "button",
        dataset: { ver: v },
        onclick: () => {
          activeVer = v;
          renderVersionBody();
          syncTabs();
        },
      }, `ver ${v}`)
    )
  );

  function syncTabs() {
    for (const btn of tabs.children) {
      btn.classList.toggle("active", btn.dataset.ver === activeVer);
    }
  }

  let advanced = null; // current jsonField, adopted on save

  function renderVersionBody() {
    const settings = work[activeVer];
    if (settings == null || typeof settings !== "object") {
      versionBody.replaceChildren(el("p", { class: "muted" }, "No settings for this version."));
      advanced = null;
      return;
    }
    advanced = jsonField(`Advanced — raw JSON for version ${activeVer}`, JSON.stringify(settings, null, 2));
    const curated = isIIDX ? curatedForm(settings) : null;
    versionBody.replaceChildren(
      curated || el("p", { class: "muted" }, "No curated form for this game — use the JSON editor below."),
      advanced.field
    );
  }

  function curatedForm(settings) {
    const rows = IIDX_FIELDS.filter((f) => f.key in settings).map((f) => {
      const control = fieldControl(f, settings[f.key], (value) => {
        work[activeVer][f.key] = value;
        if (advanced) advanced.textarea.value = JSON.stringify(work[activeVer], null, 2);
        advanced?.validate();
      });
      return el("label", { class: "form-row" }, el("span", { class: "form-row-label" }, f.label), control);
    });
    if (!rows.length) return null;
    return el("div", { class: "form-grid" }, ...rows);
  }

  // ---- save ----
  const saveBtn = el("button", { class: "btn primary", type: "button" }, "Save changes");
  saveBtn.addEventListener("click", async () => {
    notice.textContent = "";
    notice.className = "notice";

    // adopt the advanced editor if the user typed into it
    if (advanced) {
      const serialized = JSON.stringify(work[activeVer], null, 2);
      if (advanced.textarea.value.trim() !== serialized.trim()) {
        const parsed = advanced.validate();
        if (!parsed) {
          notice.textContent = "Fix the advanced JSON first — it does not parse.";
          notice.className = "notice bad";
          return;
        }
        work[activeVer] = parsed;
      }
    }

    const patch = {};
    if (nameInput.value !== (doc.name ?? "")) patch.name = nameInput.value;
    if (pinInput.value !== String(doc.pin ?? "")) {
      patch.pin = typeof doc.pin === "number" ? Number(pinInput.value) : pinInput.value;
    }
    if (JSON.stringify(work) !== JSON.stringify(doc.version || {})) patch.version = work;

    if (!Object.keys(patch).length) {
      notice.textContent = "No changes to save.";
      notice.className = "notice";
      return;
    }

    saveBtn.disabled = true;
    try {
      const updated = await api.patchProfile(table, docId, patch);
      doc.name = updated.name;
      doc.pin = updated.pin;
      doc.version = updated.version;
      work = structuredClone(doc.version || {});
      notice.textContent = "Saved.";
      notice.className = "notice ok";
    } catch (err) {
      notice.textContent = `Save failed: ${humanError(err)}`;
      notice.className = "notice bad";
    } finally {
      saveBtn.disabled = false;
    }
  });

  renderVersionBody();
  syncTabs();

  main.replaceChildren(
    el("div", { class: "crumbs" },
      link("#/", "← dashboard"),
      el("span", { class: "muted" }, `${game?.name ?? table} · profile #${docId}`)
    ),
    el("h2", { class: "page-title" }, "Profile settings ",
      game ? badge(game.key, "badge-magenta") : null),

    el("section", { class: "panel" },
      el("h3", { class: "section-title" }, "Quick edit"),
      el("div", { class: "form-grid two" },
        el("label", { class: "form-row" }, el("span", { class: "form-row-label" }, "Player name"), nameInput),
        el("label", { class: "form-row" }, el("span", { class: "form-row-label" }, "PIN"), pinInput)
      ),
      el("p", { class: "muted small mono" }, `card ${doc.card}`)
    ),

    versions.length
      ? el("section", { class: "panel" },
          el("h3", { class: "section-title" }, "Per-version settings"),
          tabs,
          versionBody
        )
      : el("section", { class: "panel" }, el("p", { class: "muted" }, "This profile has no version data.")),

    el("div", { class: "actions" }, saveBtn),
    notice
  );
}

function fieldControl(def, value, onChange) {
  if (def.type === "bool") {
    const box = el("input", { type: "checkbox" });
    box.checked = Boolean(value);
    box.addEventListener("change", () => onChange(box.checked));
    return el("span", { class: "toggle" }, box, el("span", { class: "toggle-track" }));
  }
  if (def.type === "select") {
    const select = el(
      "select",
      { class: "input select" },
      ...Object.entries(def.options).map(([v, label]) => {
        const opt = el("option", { value: v }, label);
        if (String(value) === v) opt.selected = true;
        return opt;
      })
    );
    select.addEventListener("change", () => onChange(Number(select.value)));
    return select;
  }
  const input = el("input", {
    class: "input mono",
    type: "number",
    step: def.step ?? "1",
    value: String(value ?? 0),
  });
  input.addEventListener("change", () => {
    const n = Number(input.value);
    onChange(Number.isFinite(n) ? n : 0);
  });
  return input;
}

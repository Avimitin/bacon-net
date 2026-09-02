import { api, getGames, scoreTableMeta } from "../api.js";
import { el, buildTable, skeleton, emptyState, compare } from "../ui.js";
import { scoreColumns } from "../schema.js";

export async function viewScores(main) {
  main.replaceChildren(skeleton(6));
  const [{ games: myGames }, gamesMeta] = await Promise.all([api.myScores(), getGames()]);

  const withData = myGames.filter((g) =>
    Object.values(g.tables || {}).some((rows) => rows.length)
  );

  if (!withData.length) {
    main.replaceChildren(
      el("h2", { class: "page-title" }, "My scores"),
      emptyState("No scores yet", "Play some charts — your records will land here.")
    );
    return;
  }

  const state = {
    game: withData[0].game,
    table: pickDefaultTable(withData[0], gamesMeta),
    filter: "",
  };

  const container = el("div", {});
  main.replaceChildren(el("h2", { class: "page-title" }, "My scores"), container);

  const filterInput = el("input", {
    class: "input filter",
    type: "search",
    placeholder: "filter rows (substring over JSON)…",
    oninput: () => {
      state.filter = filterInput.value.toLowerCase();
      renderTable();
    },
  });

  function render() {
    const entry = withData.find((g) => g.game === state.game);
    const gameMeta = gamesMeta.find((g) => g.key === state.game);

    const tabs = el(
      "div",
      { class: "tabs" },
      ...withData.map((g) => {
        const gm = gamesMeta.find((x) => x.key === g.game);
        return el("button", {
          class: `tab ${g.game === state.game ? "active" : ""}`,
          type: "button",
          onclick: () => {
            state.game = g.game;
            state.table = pickDefaultTable(g, gamesMeta);
            render();
          },
        }, gm?.name ?? g.game);
      })
    );

    const tableNames = Object.keys(entry.tables || {}).filter(
      (t) => entry.tables[t].length
    );
    const toggle = el(
      "div",
      { class: "segmented" },
      ...tableNames.map((t) => {
        const meta = scoreTableMeta(gamesMeta, state.game, t);
        const label = meta?.kind ?? t.replace(/^.*?_/, "");
        return el("button", {
          class: `segment ${t === state.table ? "active" : ""}`,
          type: "button",
          onclick: () => {
            state.table = t;
            render();
          },
        }, label);
      })
    );

    container.replaceChildren(
      tabs,
      el("div", { class: "panel" },
        el("div", { class: "panel-head" },
          el("h3", { class: "section-title" }, gameMeta?.name ?? state.game),
          toggle
        ),
        filterInput,
        el("div", { class: "table-host" })
      )
    );
    renderTable();
  }

  function renderTable() {
    const host = container.querySelector(".table-host");
    if (!host) return;
    const entry = withData.find((g) => g.game === state.game);
    const meta = scoreTableMeta(gamesMeta, state.game, state.table) || {};
    const rows = (entry.tables[state.table] || []).filter(
      (r) => !state.filter || JSON.stringify(r).toLowerCase().includes(state.filter)
    );
    const songField = meta.song_field || "music_id";
    const scoreField = meta.score_field || "score";
    rows.sort((a, b) => {
      const s = compare(a[songField], b[songField]);
      if (s !== 0) return s;
      return compare(b[scoreField], a[scoreField]); // score desc
    });
    host.replaceChildren(
      rows.length
        ? buildTable(scoreColumns(state.game, rows[0]), rows)
        : emptyState("Nothing matches", "Try a different filter or table.")
    );
  }

  render();
}

function pickDefaultTable(entry, gamesMeta) {
  const names = Object.keys(entry.tables || {}).filter((t) => entry.tables[t].length);
  const best = names.find(
    (t) => scoreTableMeta(gamesMeta, entry.game, t)?.kind === "best" || t.endsWith("_best")
  );
  return best ?? names[0] ?? null;
}

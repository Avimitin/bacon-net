import { api, getGames } from "../api.js";
import { el, skeleton, emptyState, fmtDate, compare } from "../ui.js";

export async function viewRankings(main) {
  main.replaceChildren(skeleton(6));
  const [{ games: rankGames }, { profiles }, gamesMeta] = await Promise.all([
    api.rankings(),
    api.profiles(),
    getGames(),
  ]);

  const myIds = new Set(profiles.map((p) => String(p.game_id)));

  if (!rankGames.length) {
    main.replaceChildren(
      el("h2", { class: "page-title" }, "Rankings"),
      emptyState("No rankings yet", "Top scores appear here once players set records.")
    );
    return;
  }

  const options = rankGames.map((g, i) => ({
    index: i,
    label: `${gamesMeta.find((m) => m.key === g.game)?.name ?? g.game} — ${g.table}`,
  }));

  const select = el(
    "select",
    { class: "input select" },
    ...options.map((o) => el("option", { value: String(o.index) }, o.label))
  );

  const host = el("div", {});

  function render() {
    const group = rankGames[Number(select.value)] || rankGames[0];
    const songs = new Map();
    for (const e of group.entries || []) {
      const key = String(e.song);
      if (!songs.has(key)) songs.set(key, []);
      songs.get(key).push(e);
    }
    const sortedSongs = [...songs.keys()].sort(compare);

    if (!sortedSongs.length) {
      host.replaceChildren(emptyState("No entries in this table yet"));
      return;
    }

    host.replaceChildren(
      ...sortedSongs.map((song) =>
        el("section", { class: "panel song-group" },
          el("h3", { class: "song-head" }, "Song ", el("span", { class: "mono accent" }, song)),
          el("ol", { class: "rank-list" },
            ...songs.get(song)
              .slice()
              .sort((a, b) => a.rank - b.rank)
              .map((e) => rankRow(e, myIds))
          )
        )
      )
    );
  }

  select.addEventListener("change", render);

  main.replaceChildren(
    el("h2", { class: "page-title" }, "Rankings"),
    el("div", { class: "panel" },
      el("label", { class: "form-row" },
        el("span", { class: "form-row-label" }, "Game / best-scores table"),
        select
      )
    ),
    host
  );
  render();
}

function rankRow(entry, myIds) {
  const mine = myIds.has(String(entry.game_id));
  const medalClass =
    entry.rank === 1 ? "gold" : entry.rank === 2 ? "silver" : entry.rank === 3 ? "bronze" : "";
  return el("li", { class: `rank-row ${mine ? "mine" : ""}`.trim() },
    el("span", { class: `medal ${medalClass}`.trim() }, String(entry.rank)),
    el("span", { class: "rank-name" }, entry.name ?? "—"),
    el("span", { class: "rank-chart muted" }, entry.chart != null ? `chart ${entry.chart}` : ""),
    el("span", { class: "rank-score mono" }, String(entry.score)),
    el("span", { class: "rank-date muted" }, fmtDate(entry.timestamp)),
    mine ? el("span", { class: "you-badge" }, "you") : null
  );
}

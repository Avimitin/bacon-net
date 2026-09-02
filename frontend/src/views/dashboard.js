import { api, getGames, konamiCache } from "../api.js";
import { el, link, badge, skeleton, emptyState, fmtDate } from "../ui.js";

export async function viewDashboard(main) {
  main.replaceChildren(skeleton(4), el("div", { class: "grid" }, skeleton(3), skeleton(3)));

  const [me, { profiles }, games] = await Promise.all([
    api.me(),
    api.profiles(),
    getGames(),
  ]);

  const head = el(
    "div",
    { class: "dash-head" },
    el("h2", { class: "page-title" }, "Welcome back, ", el("span", { class: "accent" }, me.username)),
    el("p", { class: "muted" }, `on the network since ${fmtDate(me.created_at)}`)
  );

  // ---- bound cards ----
  const cardChips = me.cards.length
    ? me.cards.map((uid) =>
        el(
          "div",
          { class: "card-chip" },
          el("span", { class: "mono" }, uid),
          el("span", { class: "muted small" }, konamiCache.get(uid) ?? "konami id unknown")
        )
      )
    : [el("p", { class: "muted" }, "No cards bound yet.")];

  const cardsPanel = el(
    "section",
    { class: "panel" },
    el("div", { class: "panel-head" },
      el("h3", { class: "section-title" }, "Your cards"),
      link("#/cards", el("button", { class: "btn ghost small" }, "manage"))
    ),
    el("div", { class: "card-chips" }, ...cardChips)
  );

  // ---- game profiles ----
  const profilePanels = profiles.map((p) => {
    const game = games.find((g) => g.key === p.game);
    const versions = (p.versions || []).map((v) => badge(v, "badge-soft"));
    return el(
      "section",
      { class: "panel hoverable" },
      el("div", { class: "panel-head" },
        el("h3", { class: "game-name" }, game?.name ?? p.game),
        badge(p.game, "badge-magenta")
      ),
      el("div", { class: "profile-lines" },
        line("player", p.name ?? "—"),
        line("game id", el("span", { class: "mono" }, String(p.game_id))),
        line("card", el("span", { class: "mono small" }, p.card)),
        line("pin", "••••"),
        el("div", { class: "versions" }, ...(versions.length ? versions : [el("span", { class: "muted" }, "no versions")]))
      ),
      link(
        `#/settings/${encodeURIComponent(p.table)}/${encodeURIComponent(p.doc_id)}`,
        el("button", { class: "btn primary small" }, "Open settings →")
      )
    );
  });

  main.replaceChildren(
    head,
    cardsPanel,
    el("h3", { class: "section-title spaced" }, "Game profiles"),
    profilePanels.length
      ? el("div", { class: "grid" }, ...profilePanels)
      : emptyState(
          "No game profiles on your cards yet",
          "Play a game with one of your bound cards, or bind a card you've already used."
        )
  );
}

function line(label, value) {
  return el(
    "div",
    { class: "profile-line" },
    el("span", { class: "muted small caps" }, label),
    value?.nodeType ? value : el("span", {}, value)
  );
}

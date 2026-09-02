import { api, getGames, konamiCache } from "../api.js";
import { el, link, badge, skeleton, emptyState, humanError } from "../ui.js";

export async function viewCards(main, rerender) {
  main.replaceChildren(skeleton(4));

  const [me, { profiles }, games] = await Promise.all([
    api.me(),
    api.profiles(),
    getGames(),
  ]);

  const profilesByCard = new Map();
  for (const p of profiles) {
    if (!profilesByCard.has(p.card)) profilesByCard.set(p.card, []);
    profilesByCard.get(p.card).push(p);
  }

  const error = el("p", { class: "form-error", role: "alert" });
  const cardInput = el("input", {
    class: "input mono",
    type: "text",
    placeholder: "E004… card UID or Konami ID",
  });
  const bindBtn = el("button", { class: "btn primary", type: "submit" }, "Bind card");

  const bindForm = el(
    "form",
    {
      class: "bind-form",
      onsubmit: async (ev) => {
        ev.preventDefault();
        const value = cardInput.value.trim();
        if (!value) return;
        error.textContent = "";
        bindBtn.disabled = true;
        try {
          const res = await api.bindCard(value);
          konamiCache.set(res.bound?.uid ?? value, res.bound?.konami_id);
          cardInput.value = "";
          rerender();
        } catch (err) {
          error.textContent = humanError(err);
          bindBtn.disabled = false;
        }
      },
    },
    cardInput,
    bindBtn
  );

  const list = me.cards.length
    ? el(
        "div",
        { class: "stack" },
        ...me.cards.map((uid) => cardRow(uid, profilesByCard.get(uid) || [], games, rerender))
      )
    : emptyState("No cards bound", "Bind your e-amusement pass below to get started.");

  main.replaceChildren(
    el("h2", { class: "page-title" }, "Cards"),
    el("section", { class: "panel" },
      el("h3", { class: "section-title" }, "Bind a new card"),
      bindForm,
      error,
      el("p", { class: "muted small" }, "Accepts a card UID (E004…) or a Konami ID printed on the card.")
    ),
    list
  );
}

function cardRow(uid, cardProfiles, games, rerender) {
  const profileChips = cardProfiles.map((p) => {
    const game = games.find((g) => g.key === p.game);
    return link(
      `#/settings/${encodeURIComponent(p.table)}/${encodeURIComponent(p.doc_id)}`,
      badge(`${game?.name ?? p.game} · ${p.name ?? p.game_id}`, "badge-soft")
    );
  });

  const unbind = el(
    "button",
    {
      class: "btn danger small",
      onclick: async () => {
        if (!confirm(`Unbind card ${uid} from your account?`)) return;
        try {
          await api.unbindCard(uid);
          konamiCache.remove(uid);
          rerender();
        } catch (err) {
          alert(`Unbind failed: ${humanError(err)}`);
        }
      },
    },
    "unbind"
  );

  return el(
    "section",
    { class: "panel card-row" },
    el("div", { class: "card-row-main" },
      el("span", { class: "mono card-uid" }, uid),
      el("span", { class: "muted small" }, `konami id: ${konamiCache.get(uid) ?? "unknown"}`),
      el("div", { class: "chips" }, ...(profileChips.length ? profileChips : [el("span", { class: "muted small" }, "no game profiles")]))
    ),
    unbind
  );
}

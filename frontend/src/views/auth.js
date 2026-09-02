import { api, tokens, konamiCache } from "../api.js";
import { el, link, humanError } from "../ui.js";

function authLayout(cardTitle, cardSub, ...children) {
  return el(
    "div",
    { class: "auth-wrap" },
    el(
      "div",
      { class: "auth-card" },
      el("div", { class: "brand-mark" }, "bacon-net"),
      el("h1", { class: "auth-title" }, cardTitle),
      el("p", { class: "muted auth-sub" }, cardSub),
      ...children
    )
  );
}

function input(attrs) {
  return el("input", { class: "input", autocomplete: "off", ...attrs });
}

function saveSession(data) {
  tokens.player = {
    token: data.token,
    username: data.username,
    expires_at: data.expires_at,
  };
}

export function viewLogin(root) {
  const error = el("p", { class: "form-error", role: "alert" });
  const user = input({ type: "text", placeholder: "username", name: "username", required: "" });
  const pass = input({ type: "password", placeholder: "password", name: "password", required: "" });
  const submit = el("button", { class: "btn primary block", type: "submit" }, "Insert coin — log in");

  const form = el(
    "form",
    {
      class: "form",
      onsubmit: async (ev) => {
        ev.preventDefault();
        error.textContent = "";
        submit.disabled = true;
        try {
          saveSession(await api.login(user.value.trim(), pass.value));
          location.hash = "#/";
        } catch (err) {
          error.textContent = humanError(err);
          submit.disabled = false;
        }
      },
    },
    field("Username", user),
    field("Password", pass),
    error,
    submit,
    el(
      "p",
      { class: "muted auth-cross" },
      "New around here? ",
      link("#/register", "Create an account")
    )
  );

  root.replaceChildren(authLayout("Welcome back, player", "Log in with your bacon-net account", form));
}

export function viewRegister(root) {
  const error = el("p", { class: "form-error", role: "alert" });
  const user = input({ type: "text", placeholder: "e.g. player_one", name: "username", required: "" });
  const pass = input({ type: "password", placeholder: "min. 8 characters", name: "password", required: "" });
  const card = input({ type: "text", placeholder: "E004… or Konami ID (optional)", name: "card" });
  const submit = el("button", { class: "btn primary block", type: "submit" }, "Create account");

  const form = el(
    "form",
    {
      class: "form",
      onsubmit: async (ev) => {
        ev.preventDefault();
        error.textContent = "";
        error.className = "form-error";
        submit.disabled = true;
        try {
          saveSession(await api.register(user.value.trim(), pass.value));
        } catch (err) {
          error.textContent = humanError(err);
          submit.disabled = false;
          return;
        }
        const cardValue = card.value.trim();
        if (cardValue) {
          try {
            const res = await api.bindCard(cardValue);
            konamiCache.set(res.bound?.uid ?? cardValue, res.bound?.konami_id);
          } catch (err) {
            error.textContent = `Account created, but the card was not bound: ${humanError(err)}`;
            error.className = "form-error warn";
            submit.textContent = "Continue anyway →";
            submit.disabled = false;
            submit.type = "button";
            submit.onclick = () => (location.hash = "#/");
            return;
          }
        }
        location.hash = "#/";
      },
    },
    field("Username", user),
    field("Password", pass),
    field("Bind a card now (optional)", card),
    error,
    submit,
    el("p", { class: "muted auth-cross" }, "Already registered? ", link("#/login", "Log in"))
  );

  root.replaceChildren(authLayout("Join the network", "Pick a callsign and grab a card", form));
}

function field(labelText, control) {
  return el("label", { class: "field" }, el("span", { class: "field-label" }, labelText), control);
}

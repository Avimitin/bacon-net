import { api, tokens } from "./api.js";
import { el, link, humanError } from "./ui.js";
import { viewLogin, viewRegister } from "./views/auth.js";
import { viewDashboard } from "./views/dashboard.js";
import { viewCards } from "./views/cards.js";
import { viewSettings } from "./views/settings.js";
import { viewScores } from "./views/scores.js";
import { viewRankings } from "./views/rankings.js";
import { viewAdmin } from "./views/admin.js";
import "./style.css";

const app = document.getElementById("app");

const NAV = [
  ["", "Dashboard", "#/"],
  ["cards", "Cards", "#/cards"],
  ["scores", "Scores", "#/scores"],
  ["rankings", "Rankings", "#/rankings"],
  ["admin", "Admin", "#/admin"],
];

function renderShell(activeRoute) {
  const session = tokens.player;
  const navLinks = NAV.map(([route, label, hash]) =>
    el("a", {
      href: hash,
      class: route === activeRoute ? "active" : "",
    }, label)
  );

  const logoutBtn = el("button", {
    class: "btn ghost small",
    type: "button",
    onclick: async () => {
      try {
        await api.logout();
      } catch {
        /* token already dead — drop it anyway */
      }
      tokens.player = null;
      location.hash = "#/login";
    },
  }, "log out");

  const header = el("header", { class: "site" },
    el("div", { class: "shell-inner" },
      link("#/", el("span", { class: "brand" }, "bacon-net", el("span", { class: "brand-sub" }, " webui"))),
      el("nav", {}, ...navLinks),
      el("div", { class: "user-area" },
        el("span", { class: "chip" }, session?.username ?? "?"),
        logoutBtn
      )
    )
  );

  const main = el("main", { class: "container" });
  app.replaceChildren(header, main);
  return main;
}

async function route() {
  const hash = location.hash.replace(/^#\/?/, "");
  const parts = hash.split("/").filter(Boolean).map(decodeURIComponent);
  const route = parts[0] ?? "";

  const session = tokens.player;
  const isAuthRoute = route === "login" || route === "register";

  if (!session && !isAuthRoute) {
    location.hash = "#/login";
    return;
  }
  if (session && isAuthRoute) {
    location.hash = "#/";
    return;
  }

  if (isAuthRoute) {
    if (route === "register") viewRegister(app);
    else viewLogin(app);
    return;
  }

  const main = renderShell(route);
  const rerender = () => route();

  try {
    switch (route) {
      case "":
        await viewDashboard(main);
        break;
      case "cards":
        await viewCards(main, rerender);
        break;
      case "settings":
        if (parts.length === 3) await viewSettings(main, parts[1], parts[2]);
        else location.hash = "#/";
        break;
      case "scores":
        await viewScores(main);
        break;
      case "rankings":
        await viewRankings(main);
        break;
      case "admin":
        await viewAdmin(main, parts.slice(1), rerender);
        break;
      default:
        location.hash = "#/";
    }
  } catch (err) {
    if (err.status === 401 && !err.admin) {
      tokens.player = null;
      location.hash = "#/login";
      return;
    }
    main.replaceChildren(
      el("div", { class: "error-box" }, humanError(err)),
      el("p", {}, link("#/", "← back to dashboard"))
    );
  }
}

window.addEventListener("hashchange", route);
route();

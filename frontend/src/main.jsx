import React from "react";
import { createRoot } from "react-dom/client";
import {
  HashRouter,
  Routes,
  Route,
  Link,
  Navigate,
  useNavigate,
} from "react-router";
import {
  Theme,
  Header,
  HeaderName,
  HeaderNavigation,
  HeaderMenuItem,
  HeaderGlobalBar,
  HeaderGlobalAction,
  Content,
  Tag,
} from "@carbon/react";
import { Logout } from "@carbon/icons-react";
import "@carbon/styles/css/styles.css";

import { api } from "./api.js";
import { SessionProvider, RequireAuth, useSession } from "./session.jsx";
import Login from "./views/Login.jsx";
import Register from "./views/Register.jsx";
import Dashboard from "./views/Dashboard.jsx";
import Cards from "./views/Cards.jsx";
import Settings from "./views/Settings.jsx";
import Scores from "./views/Scores.jsx";
import Rankings from "./views/Rankings.jsx";
import Admin from "./views/Admin.jsx";

function Shell() {
  const { session, setSession } = useSession();
  const navigate = useNavigate();

  const logout = async () => {
    try {
      await api.logout();
    } catch {
      /* token already dead — drop it anyway */
    }
    setSession(null);
    navigate("/login");
  };

  return (
    <Theme theme="g100">
      <Header aria-label="bacon-net webui">
        <HeaderName as={Link} to="/" prefix="">
          bacon-net
        </HeaderName>
        <HeaderNavigation aria-label="Main navigation">
          {session && (
            <>
              <HeaderMenuItem as={Link} to="/">
                Dashboard
              </HeaderMenuItem>
              <HeaderMenuItem as={Link} to="/cards">
                Cards
              </HeaderMenuItem>
              <HeaderMenuItem as={Link} to="/scores">
                Scores
              </HeaderMenuItem>
              <HeaderMenuItem as={Link} to="/rankings">
                Rankings
              </HeaderMenuItem>
            </>
          )}
          <HeaderMenuItem as={Link} to="/admin">
            Admin
          </HeaderMenuItem>
        </HeaderNavigation>
        <HeaderGlobalBar>
          {session && (
            <>
              <Tag type="blue" size="md" style={{ alignSelf: "center", marginRight: "0.5rem" }}>
                {session.username}
              </Tag>
              <HeaderGlobalAction aria-label="Log out" tooltipAlignment="end" onClick={logout}>
                <Logout size={20} />
              </HeaderGlobalAction>
            </>
          )}
        </HeaderGlobalBar>
      </Header>
      <Content>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />
          <Route
            path="/"
            element={
              <RequireAuth>
                <Dashboard />
              </RequireAuth>
            }
          />
          <Route
            path="/cards"
            element={
              <RequireAuth>
                <Cards />
              </RequireAuth>
            }
          />
          <Route
            path="/settings/:table/:docId"
            element={
              <RequireAuth>
                <Settings />
              </RequireAuth>
            }
          />
          <Route
            path="/scores"
            element={
              <RequireAuth>
                <Scores />
              </RequireAuth>
            }
          />
          <Route
            path="/rankings"
            element={
              <RequireAuth>
                <Rankings />
              </RequireAuth>
            }
          />
          <Route path="/admin" element={<Admin />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Content>
    </Theme>
  );
}

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <HashRouter>
      <SessionProvider>
        <Shell />
      </SessionProvider>
    </HashRouter>
  </React.StrictMode>
);

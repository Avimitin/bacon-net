import React from "react";
import { createRoot } from "react-dom/client";
import {
  HashRouter,
  Routes,
  Route,
  Link,
  Navigate,
  useNavigate,
  useLocation,
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
  SkipToContent,
  Tag,
  Loading,
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

const Admin = React.lazy(() => import("./views/Admin.jsx"));

function NavItem({ to, end, currentPath, children }) {
  return (
    <HeaderMenuItem as={Link} to={to} isCurrentPage={end ? currentPath === to : currentPath.startsWith(to)}>
      {children}
    </HeaderMenuItem>
  );
}

function Shell() {
  const { session, setSession } = useSession();
  const navigate = useNavigate();
  const { pathname } = useLocation();

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
        <SkipToContent href="#main-content" />
        <HeaderName as={Link} to="/" prefix="">
          bacon-net
        </HeaderName>
        <HeaderNavigation aria-label="Main navigation">
          {session && (
            <>
              <NavItem to="/" end currentPath={pathname}>
                Dashboard
              </NavItem>
              <NavItem to="/cards" currentPath={pathname}>
                Cards
              </NavItem>
              <NavItem to="/scores" currentPath={pathname}>
                Scores
              </NavItem>
              <NavItem to="/rankings" currentPath={pathname}>
                Rankings
              </NavItem>
            </>
          )}
          <NavItem to="/admin" currentPath={pathname}>
            Admin
          </NavItem>
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
      <Content id="main-content">
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
          <Route
            path="/admin"
            element={
              <React.Suspense
                fallback={<Loading description="Loading admin console…" withOverlay={false} />}
              >
                <Admin />
              </React.Suspense>
            }
          />
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

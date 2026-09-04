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
  HeaderContainer,
  HeaderMenuButton,
  HeaderName,
  HeaderNavigation,
  HeaderMenuItem,
  HeaderGlobalBar,
  SideNav,
  SideNavItems,
  SideNavLink,
  OverflowMenu,
  OverflowMenuItem,
  Content,
  SkipToContent,
  Loading,
} from "@carbon/react";
import {
  ChartLine,
  Dashboard as DashboardIcon,
  Settings as SettingsIcon,
  Trophy,
  UserAvatar,
  Wallet,
} from "@carbon/icons-react";
import "@carbon/styles/css/styles.css";
import "./app.css";

import { api } from "./api.js";
import { SessionProvider, RequireAuth, RequireAdmin, useSession } from "./session.jsx";
import Login from "./views/Login.jsx";
import Register from "./views/Register.jsx";
import Dashboard from "./views/Dashboard.jsx";
import Cards from "./views/Cards.jsx";
import Settings from "./views/Settings.jsx";
import Scores from "./views/Scores.jsx";
import Rankings from "./views/Rankings.jsx";

const Admin = React.lazy(() => import("./views/Admin.jsx"));

const playerNavigation = [
  { to: "/", end: true, label: "Dashboard", index: "00", icon: DashboardIcon },
  { to: "/cards", label: "Cards", index: "01", icon: Wallet },
  { to: "/scores", label: "Scores", index: "02", icon: ChartLine },
  { to: "/rankings", label: "Rankings", index: "03", icon: Trophy },
];

const adminNavigation = {
  to: "/admin",
  label: "Admin",
  index: "04",
  icon: SettingsIcon,
};

function isCurrentRoute(item, pathname) {
  return item.end ? pathname === item.to : pathname.startsWith(item.to);
}

function NavItem({ item, currentPath }) {
  return (
    <HeaderMenuItem
      as={Link}
      to={item.to}
      isCurrentPage={isCurrentRoute(item, currentPath)}
      className="primary-nav__item"
    >
      <span className="primary-nav__index" aria-hidden="true">
        {item.index}
      </span>
      {item.label}
    </HeaderMenuItem>
  );
}

function MobileNavItem({ item, currentPath, onSelect }) {
  const current = isCurrentRoute(item, currentPath);

  return (
    <SideNavLink
      as={Link}
      to={item.to}
      renderIcon={item.icon}
      isActive={current}
      aria-current={current ? "page" : undefined}
      onClick={onSelect}
      large
    >
      <span className="mobile-nav__label">
        <span aria-hidden="true">{item.index}</span>
        {item.label}
      </span>
    </SideNavLink>
  );
}

function Shell() {
  const { session, setSession } = useSession();
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const navigation = session?.admin
    ? [...playerNavigation, adminNavigation]
    : playerNavigation;

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
    <>
      <Theme theme="g100">
        <HeaderContainer
          render={({ isSideNavExpanded, onClickSideNavExpand }) => (
            <>
              <Header aria-label="bacon-net" className="app-header">
                <SkipToContent href="#main-content" />
                {session && (
                  <HeaderMenuButton
                    aria-label={isSideNavExpanded ? "Close navigation" : "Open navigation"}
                    aria-expanded={isSideNavExpanded}
                    className="app-menu-button"
                    isActive={isSideNavExpanded}
                    isCollapsible
                    onClick={onClickSideNavExpand}
                  />
                )}
                <HeaderName
                  as={Link}
                  to="/"
                  prefix=""
                  className="brand-name"
                  aria-label="bacon-net home"
                >
                  <span className="brand-mark" aria-hidden="true" />
                  <span>
                    bacon<span className="brand-slash">/</span>net
                  </span>
                </HeaderName>
                <HeaderNavigation aria-label="Primary navigation" className="primary-nav">
                  {session &&
                    navigation.map((item) => (
                      <NavItem key={item.to} item={item} currentPath={pathname} />
                    ))}
                </HeaderNavigation>
                <HeaderGlobalBar className="account-bar">
                  {session && (
                    <>
                      <span className="account-bar__name" aria-hidden="true">
                        {session.username}
                      </span>
                      <OverflowMenu
                        aria-label={`Account menu for ${session.username}`}
                        iconDescription={`Account menu for ${session.username}`}
                        renderIcon={UserAvatar}
                        direction="bottom"
                        flipped
                        className="account-menu"
                        menuOptionsClass="account-menu__options"
                      >
                        <OverflowMenuItem itemText={`Signed in as ${session.username}`} disabled />
                        <OverflowMenuItem itemText="Log out" hasDivider onClick={logout} />
                      </OverflowMenu>
                    </>
                  )}
                </HeaderGlobalBar>
              </Header>
              {session && (
                <SideNav
                  aria-label="Mobile navigation"
                  expanded={isSideNavExpanded}
                  isPersistent={false}
                  onOverlayClick={onClickSideNavExpand}
                  onSideNavBlur={onClickSideNavExpand}
                  className="mobile-side-nav"
                >
                  <SideNavItems>
                    {navigation.map((item) => (
                      <MobileNavItem
                        key={item.to}
                        item={item}
                        currentPath={pathname}
                        onSelect={onClickSideNavExpand}
                      />
                    ))}
                  </SideNavItems>
                </SideNav>
              )}
            </>
          )}
        />
      </Theme>

      <Theme theme="g10" className="app-theme">
        <Content id="main-content" className="app-content">
          <div className="route-frame route-frame--flush">
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
                  <RequireAdmin>
                    <React.Suspense
                      fallback={
                        <Loading description="Loading admin console…" withOverlay={false} />
                      }
                    >
                      <Admin />
                    </React.Suspense>
                  </RequireAdmin>
                }
              />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </div>
        </Content>
      </Theme>
    </>
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

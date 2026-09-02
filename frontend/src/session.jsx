// Player session context + auth guards. The session cookie is HttpOnly, so
// on load we ask /account/api/me who we are; a 401 means "logged out".
import { createContext, useContext, useEffect, useState } from "react";
import { Navigate, useNavigate } from "react-router";
import { InlineNotification, SkeletonText, Stack } from "@carbon/react";
import { api } from "./api.js";

const SessionContext = createContext(null);

export function SessionProvider({ children }) {
  const [session, setSession] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    api
      .me()
      .then((me) => {
        if (!cancelled) setSession(me);
      })
      .catch(() => {
        /* no live session cookie */
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <SessionContext.Provider value={{ session, setSession, loading }}>
      {children}
    </SessionContext.Provider>
  );
}

export function useSession() {
  return useContext(SessionContext);
}

function SessionSkeleton() {
  return (
    <Stack gap={6} style={{ marginTop: "1rem" }}>
      <SkeletonText heading width="30%" />
      <SkeletonText paragraph lineCount={4} />
    </Stack>
  );
}

export function RequireAuth({ children }) {
  const { session, loading } = useSession();
  if (loading) return <SessionSkeleton />;
  if (!session) return <Navigate to="/login" replace />;
  return children;
}

// Operator-only routes: accounts without the admin flag get a 403-style
// empty state instead of the console.
export function RequireAdmin({ children }) {
  const { session, loading } = useSession();
  if (loading) return <SessionSkeleton />;
  if (!session) return <Navigate to="/login" replace />;
  if (!session.admin) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <h1>Admin</h1>
        <InlineNotification
          kind="error"
          title="403 — no permission"
          subtitle="This area is restricted to operator accounts."
          hideCloseButton
          lowContrast
        />
      </Stack>
    );
  }
  return children;
}

// Returns a handler: a 401 on a player call drops the session and redirects
// to login. Returns true when the error was handled that way.
export function useAuthFailure() {
  const { setSession } = useSession();
  const navigate = useNavigate();
  return (err) => {
    if (err?.status === 401 && !err.admin) {
      setSession(null);
      navigate("/login");
      return true;
    }
    return false;
  };
}

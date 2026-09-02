// Player session context + auth guard. Session mirrors tokens.player in
// localStorage so a page reload keeps the login.
import { createContext, useContext, useState } from "react";
import { Navigate, useNavigate } from "react-router";
import { tokens } from "./api.js";

const SessionContext = createContext(null);

export function SessionProvider({ children }) {
  const [session, setSessionState] = useState(tokens.player);
  const setSession = (s) => {
    tokens.player = s;
    setSessionState(s);
  };
  return (
    <SessionContext.Provider value={{ session, setSession }}>
      {children}
    </SessionContext.Provider>
  );
}

export function useSession() {
  return useContext(SessionContext);
}

export function RequireAuth({ children }) {
  const { session } = useSession();
  if (!session) return <Navigate to="/login" replace />;
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

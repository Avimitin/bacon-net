import { useRef, useState } from "react";
import { Link, Navigate, useNavigate } from "react-router";
import {
  Form,
  TextInput,
  PasswordInput,
  Button,
  InlineNotification,
  Grid,
  Column,
  Tile,
  Stack,
} from "@carbon/react";
import { api } from "../api.js";
import { useSession } from "../session.jsx";
import { humanError } from "../util.js";

export default function Login() {
  const { session, setSession, loading } = useSession();
  const navigate = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const passwordRef = useRef(null);

  if (loading) return null; // session cookie check in flight
  if (session) return <Navigate to="/" replace />;

  const submit = async (ev) => {
    ev.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await api.login(username.trim(), password);
      setSession(await api.me()); // cookie is set; fetch the user doc (incl. admin flag)
      navigate("/");
    } catch (err) {
      setError(humanError(err));
      setBusy(false);
      setPassword("");
      passwordRef.current?.focus();
    }
  };

  return (
    <Grid narrow>
      <Column sm={4} md={{ span: 4, offset: 2 }} lg={{ span: 6, offset: 5 }}>
        <Tile style={{ marginTop: "3rem" }}>
          <Stack gap={6}>
            <div>
              <h1>Log in</h1>
              <p style={{ color: "var(--cds-text-secondary)" }}>
                Log in with your bacon-net account
              </p>
            </div>
            <Form onSubmit={submit}>
              <Stack gap={6}>
                <TextInput
                  id="login-username"
                  labelText="Username"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                />
                <PasswordInput
                  id="login-password"
                  labelText="Password"
                  value={password}
                  ref={passwordRef}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
                {error && (
                  <InlineNotification
                    kind="error"
                    title="Login failed"
                    subtitle={error}
                    hideCloseButton
                    lowContrast
                  />
                )}
                <Button type="submit" disabled={busy}>
                  {busy ? "Logging in…" : "Log in"}
                </Button>
              </Stack>
            </Form>
            <p style={{ color: "var(--cds-text-secondary)" }}>
              New around here? <Link to="/register">Create an account</Link>
            </p>
          </Stack>
        </Tile>
      </Column>
    </Grid>
  );
}

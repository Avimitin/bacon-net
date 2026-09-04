import { useRef, useState } from "react";
import { Link, Navigate, useNavigate } from "react-router";
import {
  Form,
  TextInput,
  PasswordInput,
  Button,
  InlineNotification,
  Stack,
} from "@carbon/react";
import { ArrowRight } from "@carbon/icons-react";
import { api } from "../api.js";
import { useSession } from "../session.jsx";
import { humanError } from "../util.js";
import { AuthFrame } from "../components/SignalLayout.jsx";

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
    <AuthFrame
      index="00"
      eyebrow="Player access"
      title="Return to"
      accent="the network."
      description="Your cards, profiles, and records stay connected under one player identity."
      footer={
        <>
          New around here? <Link to="/register">Create an account</Link>
        </>
      }
    >
      <Form onSubmit={submit}>
        <Stack gap={6}>
          <TextInput
            id="login-username"
            labelText="Username"
            autoComplete="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
          />
          <PasswordInput
            id="login-password"
            labelText="Password"
            autoComplete="current-password"
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
          <Button type="submit" disabled={busy} renderIcon={ArrowRight}>
            {busy ? "Logging in…" : "Log in"}
          </Button>
        </Stack>
      </Form>
    </AuthFrame>
  );
}

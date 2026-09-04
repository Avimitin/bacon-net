import { useState } from "react";
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
import { api, konamiCache } from "../api.js";
import { useSession } from "../session.jsx";
import { humanError } from "../util.js";
import { AuthFrame } from "../components/SignalLayout.jsx";

export default function Register() {
  const { session, setSession, loading } = useSession();
  const navigate = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [card, setCard] = useState("");
  const [error, setError] = useState(null);
  const [bindWarning, setBindWarning] = useState(null);
  const [busy, setBusy] = useState(false);

  if (loading) return null; // session cookie check in flight
  if (session) return <Navigate to="/" replace />;

  const submit = async (ev) => {
    ev.preventDefault();
    setError(null);
    setBindWarning(null);
    setBusy(true);
    try {
      await api.register(username.trim(), password);
      setSession(await api.me()); // cookie is set; fetch the user doc
    } catch (err) {
      setError(humanError(err));
      setBusy(false);
      return;
    }
    const cardValue = card.trim();
    if (cardValue) {
      try {
        const res = await api.bindCard(cardValue);
        konamiCache.set(res.bound?.uid ?? cardValue, res.bound?.konami_id);
      } catch (err) {
        // Account exists and session is live — let the user proceed anyway.
        setBindWarning(`Account created, but the card was not bound: ${humanError(err)}`);
        setBusy(false);
        return;
      }
    }
    navigate("/");
  };

  return (
    <AuthFrame
      index="01"
      eyebrow="New player"
      title="Make your"
      accent="connection."
      description="Create one account, then bind an e-amusement pass now or whenever you are ready."
      footer={
        <>
          Already registered? <Link to="/login">Log in</Link>
        </>
      }
    >
      <Form onSubmit={submit}>
        <Stack gap={6}>
          <TextInput
            id="reg-username"
            labelText="Username"
            placeholder="e.g. player_one"
            autoComplete="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
          />
          <PasswordInput
            id="reg-password"
            labelText="Password"
            placeholder="min. 8 characters"
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          <TextInput
            id="reg-card"
            labelText="Bind a card now (optional)"
            placeholder="E004… or Konami ID"
            value={card}
            onChange={(e) => setCard(e.target.value)}
          />
          {error && (
            <InlineNotification
              kind="error"
              title="Registration failed"
              subtitle={error}
              hideCloseButton
              lowContrast
            />
          )}
          {bindWarning && (
            <InlineNotification
              kind="warning"
              title="Card not bound"
              subtitle={bindWarning}
              hideCloseButton
              lowContrast
            />
          )}
          {bindWarning ? (
            <Button onClick={() => navigate("/")} renderIcon={ArrowRight}>
              Continue anyway
            </Button>
          ) : (
            <Button type="submit" disabled={busy} renderIcon={ArrowRight}>
              {busy ? "Creating…" : "Create account"}
            </Button>
          )}
        </Stack>
      </Form>
    </AuthFrame>
  );
}

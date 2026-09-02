import { useState } from "react";
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
import { api, konamiCache } from "../api.js";
import { useSession } from "../session.jsx";
import { humanError } from "../util.js";

export default function Register() {
  const { session, setSession } = useSession();
  const navigate = useNavigate();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [card, setCard] = useState("");
  const [error, setError] = useState(null);
  const [bindWarning, setBindWarning] = useState(null);
  const [busy, setBusy] = useState(false);

  if (session) return <Navigate to="/" replace />;

  const submit = async (ev) => {
    ev.preventDefault();
    setError(null);
    setBindWarning(null);
    setBusy(true);
    let data;
    try {
      data = await api.register(username.trim(), password);
      setSession({ token: data.token, username: data.username, expires_at: data.expires_at });
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
    <Grid narrow>
      <Column sm={4} md={{ span: 4, offset: 2 }} lg={{ span: 6, offset: 5 }}>
        <Tile style={{ marginTop: "3rem" }}>
          <Stack gap={6}>
            <div>
              <h2>Join the network</h2>
              <p style={{ color: "var(--cds-text-secondary)" }}>
                Pick a callsign and grab a card
              </p>
            </div>
            <Form onSubmit={submit}>
              <Stack gap={6}>
                <TextInput
                  id="reg-username"
                  labelText="Username"
                  placeholder="e.g. player_one"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                />
                <PasswordInput
                  id="reg-password"
                  labelText="Password"
                  placeholder="min. 8 characters"
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
                  <Button onClick={() => navigate("/")}>Continue anyway</Button>
                ) : (
                  <Button type="submit" disabled={busy}>
                    {busy ? "Creating…" : "Create account"}
                  </Button>
                )}
              </Stack>
            </Form>
            <p style={{ color: "var(--cds-text-secondary)" }}>
              Already registered? <Link to="/login">Log in</Link>
            </p>
          </Stack>
        </Tile>
      </Column>
    </Grid>
  );
}

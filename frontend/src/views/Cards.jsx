import { useEffect, useState } from "react";
import { Link } from "react-router";
import {
  Form,
  TextInput,
  Button,
  Tag,
  Tile,
  Stack,
  SkeletonText,
  SkeletonPlaceholder,
  InlineNotification,
  Modal,
} from "@carbon/react";
import { api, getGames, konamiCache } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { humanError } from "../util.js";

export default function Cards() {
  const authFailure = useAuthFailure();
  const [data, setData] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [cardInput, setCardInput] = useState("");
  const [bindError, setBindError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [unbindTarget, setUnbindTarget] = useState(null);
  const [unbindError, setUnbindError] = useState(null);

  const load = () => {
    Promise.all([api.me(), api.profiles(), getGames()])
      .then(([me, { profiles }, games]) => setData({ me, profiles, games }))
      .catch((err) => {
        if (!authFailure(err)) setLoadError(humanError(err));
      });
  };

  useEffect(load, []); // eslint-disable-line react-hooks/exhaustive-deps

  const bind = async (ev) => {
    ev.preventDefault();
    const value = cardInput.trim();
    if (!value) return;
    setBindError(null);
    setBusy(true);
    try {
      const res = await api.bindCard(value);
      konamiCache.set(res.bound?.uid ?? value, res.bound?.konami_id);
      setCardInput("");
      setBusy(false);
      load();
    } catch (err) {
      if (!authFailure(err)) setBindError(humanError(err));
      setBusy(false);
    }
  };

  const unbind = async () => {
    const uid = unbindTarget;
    setUnbindError(null);
    try {
      await api.unbindCard(uid);
      konamiCache.remove(uid);
      setUnbindTarget(null);
      load();
    } catch (err) {
      if (!authFailure(err)) setUnbindError(humanError(err));
    }
  };

  if (loadError) {
    return (
      <InlineNotification
        kind="error"
        title="Could not load cards"
        subtitle={loadError}
        hideCloseButton
        lowContrast
      />
    );
  }

  if (!data) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <SkeletonText heading width="30%" />
        <SkeletonPlaceholder style={{ width: "100%", height: "8rem" }} />
        <SkeletonPlaceholder style={{ width: "100%", height: "6rem" }} />
      </Stack>
    );
  }

  const { me, profiles, games } = data;
  const profilesByCard = new Map();
  for (const p of profiles) {
    if (!profilesByCard.has(p.card)) profilesByCard.set(p.card, []);
    profilesByCard.get(p.card).push(p);
  }

  return (
    <Stack gap={7} style={{ marginTop: "1rem" }}>
      <h2>Cards</h2>

      <Tile>
        <Stack gap={4}>
          <h3>Bind a new card</h3>
          <Form onSubmit={bind}>
            <div style={{ display: "flex", gap: "1rem", alignItems: "flex-end" }}>
              <TextInput
                id="bind-card"
                labelText="Card UID or Konami ID"
                placeholder="E004… card UID or Konami ID"
                value={cardInput}
                onChange={(e) => setCardInput(e.target.value)}
                style={{ fontFamily: "monospace" }}
              />
              <Button type="submit" disabled={busy}>
                Bind card
              </Button>
            </div>
          </Form>
          {bindError && (
            <InlineNotification
              kind="error"
              title="Bind failed"
              subtitle={bindError}
              hideCloseButton
              lowContrast
            />
          )}
          <p style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem" }}>
            Accepts a card UID (E004…) or a Konami ID printed on the card.
          </p>
        </Stack>
      </Tile>

      {me.cards.length ? (
        me.cards.map((uid) => {
          const cardProfiles = profilesByCard.get(uid) || [];
          return (
            <Tile key={uid}>
              <Stack gap={3}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <div>
                    <strong style={{ fontFamily: "monospace" }}>{uid}</strong>
                    <span style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem", marginLeft: "1rem" }}>
                      konami id: {konamiCache.get(uid) ?? "unknown"}
                    </span>
                  </div>
                  <Button kind="danger" size="sm" onClick={() => setUnbindTarget(uid)}>
                    Unbind
                  </Button>
                </div>
                <div style={{ display: "flex", flexWrap: "wrap", gap: "0.25rem" }}>
                  {cardProfiles.length ? (
                    cardProfiles.map((p) => {
                      const game = games.find((g) => g.key === p.game);
                      return (
                        <Tag
                          key={`${p.table}:${p.doc_id}`}
                          as={Link}
                          to={`/settings/${encodeURIComponent(p.table)}/${encodeURIComponent(p.doc_id)}`}
                          type="cool-gray"
                          size="sm"
                        >
                          {game?.name ?? p.game} · {p.name ?? p.game_id}
                        </Tag>
                      );
                    })
                  ) : (
                    <span style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem" }}>
                      no game profiles
                    </span>
                  )}
                </div>
              </Stack>
            </Tile>
          );
        })
      ) : (
        <InlineNotification
          kind="info"
          title="No cards bound"
          subtitle="Bind your e-amusement pass above to get started."
          hideCloseButton
          lowContrast
        />
      )}

      <Modal
        open={unbindTarget !== null}
        danger
        modalHeading="Unbind card"
        primaryButtonText="Unbind"
        secondaryButtonText="Cancel"
        onRequestClose={() => {
          setUnbindTarget(null);
          setUnbindError(null);
        }}
        onRequestSubmit={unbind}
      >
        <p>Unbind card {unbindTarget} from your account?</p>
        {unbindError && (
          <InlineNotification
            kind="error"
            title="Unbind failed"
            subtitle={unbindError}
            hideCloseButton
            lowContrast
          />
        )}
      </Modal>
    </Stack>
  );
}

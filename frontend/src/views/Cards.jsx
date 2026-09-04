import { useEffect, useState } from "react";
import { Link } from "react-router";
import { Form, TextInput, Button, InlineNotification, Modal } from "@carbon/react";
import { ArrowRight, Wallet } from "@carbon/icons-react";
import { api, getGames, konamiCache } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { humanError } from "../util.js";
import { PageState, SectionHeading, SignalHero } from "../components/SignalLayout.jsx";

export default function Cards() {
  const authFailure = useAuthFailure();
  const [data, setData] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [cardInput, setCardInput] = useState("");
  const [bindError, setBindError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [unbindTarget, setUnbindTarget] = useState(null);
  const [unbindError, setUnbindError] = useState(null);
  const [unbindBusy, setUnbindBusy] = useState(false);

  const load = () => {
    setLoadError(null);
    Promise.all([api.me(), api.profiles(), getGames()])
      .then(([me, { profiles }, games]) => setData({ me, profiles, games }))
      .catch((err) => {
        if (!authFailure(err)) setLoadError(humanError(err));
      });
  };

  useEffect(load, []); // eslint-disable-line react-hooks/exhaustive-deps

  const bind = async (event) => {
    event.preventDefault();
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
    if (unbindBusy || unbindTarget === null) return;
    const uid = unbindTarget;
    setUnbindError(null);
    setUnbindBusy(true);
    try {
      await api.unbindCard(uid);
      konamiCache.remove(uid);
      setUnbindTarget(null);
      load();
    } catch (err) {
      if (!authFailure(err)) setUnbindError(humanError(err));
    } finally {
      setUnbindBusy(false);
    }
  };

  if (loadError) {
    return (
      <PageState kind="error" title="Could not load cards" description={loadError} onRetry={load} />
    );
  }

  if (!data) return <PageState title="Loading card access…" />;

  const { me, profiles, games } = data;
  const profilesByCard = new Map();
  for (const profile of profiles) {
    if (!profilesByCard.has(profile.card)) profilesByCard.set(profile.card, []);
    profilesByCard.get(profile.card).push(profile);
  }

  return (
    <div className="signal-page cards-page">
      <SignalHero
        index="01"
        eyebrow="Access layer"
        title="Cards are your"
        accent="physical key."
        description="Connect an e-amusement pass to this account. Every profile discovered on that card becomes part of your network."
        metrics={[
          { label: "Bound", value: String(me.cards.length).padStart(2, "0") },
          { label: "Profiles", value: String(profiles.length).padStart(2, "0") },
        ]}
        visualLabel="Identity / card / profile"
      />

      <div className="signal-page__body signal-split">
        <aside className="signal-form-panel" aria-label="Bind a card">
          <SectionHeading
            index="01.A"
            eyebrow="New access point"
            title="Bind a card"
            description="Use the UID read by a cabinet or the Konami ID printed on the pass."
          />
          <Form onSubmit={bind}>
            <div className="signal-form-stack">
              <TextInput
                id="bind-card"
                labelText="Card UID or Konami ID"
                placeholder="E004… or Konami ID"
                value={cardInput}
                onChange={(event) => setCardInput(event.target.value)}
                className="signal-mono-input"
              />
              <Button type="submit" disabled={busy} renderIcon={ArrowRight}>
                {busy ? "Binding…" : "Bind card"}
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
          <p className="signal-form-note">
            Binding changes account access only. Game data remains attached to the card.
          </p>
        </aside>

        <section className="signal-content-panel" aria-label="Bound cards">
          <SectionHeading
            index="01.B"
            eyebrow="Active access"
            title="Bound cards"
            description={`${me.cards.length} card${me.cards.length === 1 ? "" : "s"} currently connect to this account.`}
          />

          {me.cards.length ? (
            <ol className="card-ledger">
              {me.cards.map((uid, cardIndex) => {
                const cardProfiles = profilesByCard.get(uid) || [];
                return (
                  <li key={uid} className="card-ledger__item">
                    <div className="card-ledger__rail" aria-hidden="true">
                      <span>{String(cardIndex + 1).padStart(2, "0")}</span>
                      <Wallet size={24} />
                    </div>
                    <div className="card-ledger__body">
                      <div className="card-ledger__header">
                        <div>
                          <p className="card-ledger__label">Card UID</p>
                          <h3>{uid}</h3>
                        </div>
                        <Button
                          kind="danger--ghost"
                          size="sm"
                          onClick={() => setUnbindTarget(uid)}
                        >
                          Unbind
                        </Button>
                      </div>
                      <dl className="card-ledger__facts">
                        <div>
                          <dt>Konami ID</dt>
                          <dd>{konamiCache.get(uid) ?? "Not reported"}</dd>
                        </div>
                        <div>
                          <dt>Profiles</dt>
                          <dd>{String(cardProfiles.length).padStart(2, "0")}</dd>
                        </div>
                      </dl>
                      <div className="card-ledger__profiles">
                        <p>Connected profiles</p>
                        <ul>
                          {cardProfiles.length ? (
                            cardProfiles.map((profile) => {
                              const game = games.find((candidate) => candidate.key === profile.game);
                              return (
                                <li key={`${profile.table}:${profile.doc_id}`}>
                                  <Link
                                    to={`/settings/${encodeURIComponent(profile.table)}/${encodeURIComponent(profile.doc_id)}`}
                                  >
                                    <span>{game?.name ?? profile.game}</span>
                                    <strong>{profile.name ?? profile.game_id}</strong>
                                    <ArrowRight size={16} aria-hidden="true" />
                                  </Link>
                                </li>
                              );
                            })
                          ) : (
                            <li className="card-ledger__empty">No game profiles discovered yet.</li>
                          )}
                        </ul>
                      </div>
                    </div>
                  </li>
                );
              })}
            </ol>
          ) : (
            <div className="signal-empty-plane">
              <Wallet size={32} />
              <h3>No cards bound</h3>
              <p>Bind your e-amusement pass to make this account playable.</p>
            </div>
          )}
        </section>
      </div>

      {unbindTarget !== null && (
        <Modal
          size="xs"
          open
          danger
          modalHeading="Unbind card"
          primaryButtonText={unbindBusy ? "Unbinding…" : "Unbind"}
          primaryButtonDisabled={unbindBusy}
          secondaryButtonText="Cancel"
          onRequestClose={() => {
            if (unbindBusy) return;
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
      )}
    </div>
  );
}

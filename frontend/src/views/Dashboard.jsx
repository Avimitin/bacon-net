import { useEffect, useState } from "react";
import { Link } from "react-router";
import {
  ClickableTile,
  Tag,
  Tile,
  Grid,
  Column,
  Stack,
  SkeletonText,
  SkeletonPlaceholder,
  InlineNotification,
  NotificationActionButton,
  Button,
} from "@carbon/react";
import { ArrowRight } from "@carbon/icons-react";
import { api, getGames, konamiCache } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { fmtDate, humanError } from "../util.js";

export default function Dashboard() {
  const authFailure = useAuthFailure();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    Promise.all([api.me(), api.profiles(), getGames()])
      .then(([me, { profiles }, games]) => setData({ me, profiles, games }))
      .catch((err) => {
        if (!authFailure(err)) setError(humanError(err));
      });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (error) {
    return (
      <InlineNotification
        kind="error"
        title="Could not load dashboard"
        subtitle={error}
        hideCloseButton
        lowContrast
      />
    );
  }

  if (!data) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <SkeletonText heading width="40%" />
        <SkeletonPlaceholder style={{ width: "100%", height: "6rem" }} />
        <Grid narrow>
          {[0, 1, 2].map((i) => (
            <Column key={i} sm={4} md={4} lg={5}>
              <SkeletonPlaceholder style={{ width: "100%", height: "12rem" }} />
            </Column>
          ))}
        </Grid>
      </Stack>
    );
  }

  const { me, profiles, games } = data;

  return (
    <Stack gap={7} style={{ marginTop: "1rem" }}>
      <div>
        <h1>Welcome back, {me.username}</h1>
        <p style={{ color: "var(--cds-text-secondary)" }}>
          on the network since {fmtDate(me.created_at)}
        </p>
      </div>

      <Tile>
        <Stack gap={4}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <h3>Your cards</h3>
            <Button as={Link} to="/cards" kind="ghost" size="sm">
              Manage
            </Button>
          </div>
          {me.cards.length ? (
            <div style={{ display: "flex", flexWrap: "wrap", gap: "0.5rem" }}>
              {me.cards.map((uid) => (
                <Tag key={uid} type="cool-gray" size="md" title={konamiCache.get(uid) ?? "konami id unknown"}>
                  {uid}
                  {konamiCache.get(uid) ? ` · ${konamiCache.get(uid)}` : ""}
                </Tag>
              ))}
            </div>
          ) : (
            <p style={{ color: "var(--cds-text-secondary)" }}>No cards bound yet.</p>
          )}
        </Stack>
      </Tile>

      <div>
        <h3 style={{ marginBottom: "1rem" }}>Game profiles</h3>
        {profiles.length ? (
          <Grid narrow>
            {profiles.map((p) => {
              const game = games.find((g) => g.key === p.game);
              const icon = gameIcon(p.game);
              const to = `/settings/${encodeURIComponent(p.table)}/${encodeURIComponent(p.doc_id)}`;
              return (
                <Column key={`${p.table}:${p.doc_id}`} sm={4} md={4} lg={5} style={{ marginBottom: "1rem" }}>
                  <ClickableTile as={Link} to={to}>
                    <Stack gap={3}>
                      <div style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
                        {icon && <img src={icon} alt="" width={40} height={40} />}
                        <h4>{game?.name ?? p.game}</h4>
                        <Tag type="magenta" size="sm">
                          {p.game}
                        </Tag>
                      </div>
                      <dl style={{ display: "grid", gridTemplateColumns: "auto 1fr", gap: "0.25rem 1rem" }}>
                        <dt style={{ color: "var(--cds-text-secondary)" }}>player</dt>
                        <dd>{p.name ?? "—"}</dd>
                        <dt style={{ color: "var(--cds-text-secondary)" }}>game id</dt>
                        <dd style={{ fontFamily: "monospace" }}>{String(p.game_id)}</dd>
                        <dt style={{ color: "var(--cds-text-secondary)" }}>card</dt>
                        <dd style={{ fontFamily: "monospace", fontSize: "0.875rem" }}>{p.card}</dd>
                        <dt style={{ color: "var(--cds-text-secondary)" }}>pin</dt>
                        <dd>••••</dd>
                      </dl>
                      <div style={{ display: "flex", flexWrap: "wrap", gap: "0.25rem" }}>
                        {(p.versions || []).length ? (
                          p.versions.map((v) => (
                            <Tag key={v} type="cool-gray" size="sm">
                              ver {v}
                            </Tag>
                          ))
                        ) : (
                          <span style={{ color: "var(--cds-text-secondary)" }}>no versions</span>
                        )}
                      </div>
                      <span style={{ display: "inline-flex", alignItems: "center", gap: "0.25rem", color: "var(--cds-link-primary)" }}>
                        Open settings <ArrowRight size={16} />
                      </span>
                    </Stack>
                  </ClickableTile>
                </Column>
              );
            })}
          </Grid>
        ) : (
          <InlineNotification
            kind="info"
            title="No game profiles on your cards yet"
            subtitle="Play a game with one of your bound cards, or bind a card you've already used."
            hideCloseButton
            lowContrast
            actions={
              <NotificationActionButton as={Link} to="/cards">
                Bind a card
              </NotificationActionButton>
            }
          />
        )}
      </div>
    </Stack>
  );
}

import { useEffect, useState } from "react";
import { Link } from "react-router";
import {
  Button,
  ClickableTile,
  Column,
  Grid,
  SkeletonPlaceholder,
  SkeletonText,
} from "@carbon/react";
import {
  Add,
  ArrowRight,
  ChartLine,
  GameConsole,
  Renew,
  UserAvatar,
  Wallet,
} from "@carbon/icons-react";
import { api, getGames, konamiCache } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { fmtDate, humanError } from "../util.js";

const profileTones = ["blue", "purple", "teal", "red"];

function SectionLabel({ index, children }) {
  return (
    <p className="section-label">
      <span aria-hidden="true">{index}</span>
      {children}
    </p>
  );
}

function AccountTopology({ username, cards, profiles, games }) {
  const profileGames = [...new Set(profiles.map((profile) => profile.game))];
  const visibleGames = profileGames.slice(0, 4);

  return (
    <section className="account-map" aria-labelledby="account-map-title">
      <div className="account-map__heading">
        <div>
          <p className="account-map__overline">Live account model</p>
          <h2 id="account-map-title">Your network</h2>
        </div>
        <span className="account-map__state">
          <span aria-hidden="true" /> Connected
        </span>
      </div>

      <div className="account-map__canvas" aria-hidden="true">
        <svg viewBox="0 0 560 328" preserveAspectRatio="none" focusable="false">
          <path d="M112 64H224V160H304" />
          <path d="M272 160H352V240H432" />
          <circle cx="224" cy="160" r="4" />
          <circle cx="352" cy="240" r="4" />
        </svg>

        <div className="account-map__node account-map__node--user">
          <UserAvatar size={20} />
          <span>
            <small>Account</small>
            <strong>{username}</strong>
          </span>
        </div>

        <div className="account-map__node account-map__node--cards">
          <Wallet size={24} />
          <span>
            <strong>{String(cards.length).padStart(2, "0")}</strong>
            <small>bound cards</small>
          </span>
        </div>

        <div className="account-map__node account-map__node--profiles">
          <span className="account-map__profile-count">
            <GameConsole size={24} />
            <strong>{String(profiles.length).padStart(2, "0")}</strong>
          </span>
          <small>game profiles</small>
          {visibleGames.length > 0 && (
            <span className="account-map__games">
              {visibleGames.map((key) => {
                const icon = gameIcon(key);
                const game = games.find((candidate) => candidate.key === key);
                return icon ? (
                  <img key={key} src={icon} alt="" title={game?.name ?? key} />
                ) : (
                  <span key={key}>{key.slice(0, 2).toUpperCase()}</span>
                );
              })}
              {profileGames.length > visibleGames.length && (
                <span>+{profileGames.length - visibleGames.length}</span>
              )}
            </span>
          )}
        </div>

        <span className="account-map__coordinate account-map__coordinate--top">X / 08</span>
        <span className="account-map__coordinate account-map__coordinate--bottom">Y / 16</span>
      </div>

      <p className="sr-only">
        Account {username} connects {cards.length} bound cards to {profiles.length} game
        profiles.
      </p>
    </section>
  );
}

function ProfileCard({ profile, game, index }) {
  const icon = gameIcon(profile.game);
  const versions = profile.versions || [];
  const to = `/settings/${encodeURIComponent(profile.table)}/${encodeURIComponent(profile.doc_id)}`;
  const name = profile.name || "Player name not set";

  return (
    <li className="profile-grid__item">
      <ClickableTile
        as={Link}
        to={to}
        className="profile-card"
        data-tone={profileTones[index % profileTones.length]}
        aria-label={`Open settings for ${game?.name ?? profile.game}, player ${name}`}
      >
        <span className="profile-card__signal" aria-hidden="true" />
        <div className="profile-card__header">
          <span className="profile-card__index" aria-hidden="true">
            {String(index + 1).padStart(2, "0")}
          </span>
          <span className="profile-card__icon">
            {icon ? <img src={icon} alt="" /> : <GameConsole size={32} />}
          </span>
          <span className="profile-card__key">{profile.game}</span>
        </div>

        <div className="profile-card__body">
          <p className="profile-card__name">{name}</p>
          <h3>{game?.name ?? profile.game}</h3>
        </div>

        <dl className="profile-card__facts">
          <div>
            <dt>Player ID</dt>
            <dd>{profile.game_id == null ? "Not assigned" : String(profile.game_id)}</dd>
          </div>
          <div>
            <dt>Versions</dt>
            <dd>{versions.length ? versions.join(" / ") : "None detected"}</dd>
          </div>
        </dl>

        <span className="profile-card__action">
          Open settings <ArrowRight size={20} />
        </span>
      </ClickableTile>
    </li>
  );
}

function DashboardSkeleton() {
  return (
    <div className="dashboard dashboard--loading" aria-busy="true">
      <h1 className="sr-only">Loading dashboard</h1>
      <div className="dashboard-hero dashboard-hero--loading">
        <div className="dashboard-hero__copy">
          <SkeletonText width="20%" />
          <SkeletonText heading width="72%" />
          <SkeletonText paragraph lineCount={2} width="58%" />
        </div>
        <SkeletonPlaceholder className="dashboard-hero__skeleton-map" />
      </div>
      <div className="dashboard-summary">
        {[0, 1, 2].map((item) => (
          <SkeletonPlaceholder key={item} className="dashboard-summary__skeleton" />
        ))}
      </div>
      <Grid fullWidth className="dashboard-body">
        <Column sm={4} md={8} lg={12}>
          <SkeletonText heading width="32%" />
          <div className="profile-grid profile-grid--loading">
            {[0, 1, 2, 3].map((item) => (
              <SkeletonPlaceholder key={item} className="profile-grid__skeleton" />
            ))}
          </div>
        </Column>
        <Column sm={4} md={8} lg={4}>
          <SkeletonPlaceholder className="access-panel__skeleton" />
        </Column>
      </Grid>
    </div>
  );
}

export default function Dashboard() {
  const authFailure = useAuthFailure();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [loadAttempt, setLoadAttempt] = useState(0);

  useEffect(() => {
    let active = true;
    setError(null);

    Promise.all([api.me(), api.profiles(), getGames()])
      .then(([me, { profiles }, games]) => {
        if (active) setData({ me, profiles, games });
      })
      .catch((err) => {
        if (active && !authFailure(err)) setError(humanError(err));
      });

    return () => {
      active = false;
    };
  }, [loadAttempt]); // eslint-disable-line react-hooks/exhaustive-deps

  if (error) {
    return (
      <section className="dashboard-state" role="alert">
        <SectionLabel index="00">Signal interrupted</SectionLabel>
        <h1>Dashboard unavailable</h1>
        <p>{error}</p>
        <Button renderIcon={Renew} onClick={() => setLoadAttempt((attempt) => attempt + 1)}>
          Try again
        </Button>
      </section>
    );
  }

  if (!data) return <DashboardSkeleton />;

  const { me, profiles, games } = data;
  const connectedGames = new Set(profiles.map((profile) => profile.game)).size;
  const profilesByCard = new Map();

  for (const profile of profiles) {
    profilesByCard.set(profile.card, (profilesByCard.get(profile.card) || 0) + 1);
  }

  return (
    <div className="dashboard">
      <section className="dashboard-hero" aria-labelledby="dashboard-title">
        <div className="dashboard-hero__copy">
          <SectionLabel index="00">Player network</SectionLabel>
          <h1 id="dashboard-title">
            Your play,
            <span>wired together.</span>
          </h1>
          <p className="dashboard-hero__intro">
            Welcome back, <strong>{me.username}</strong>. Every card, profile, and score in
            one focused signal.
          </p>
          <div className="dashboard-hero__actions">
            <Button as={Link} to="/scores" renderIcon={ChartLine}>
              Explore scores
            </Button>
            <Button as={Link} to="/cards" kind="tertiary" renderIcon={ArrowRight}>
              Manage cards
            </Button>
          </div>
        </div>

        <AccountTopology
          username={me.username}
          cards={me.cards}
          profiles={profiles}
          games={games}
        />
      </section>

      <dl className="dashboard-summary" aria-label="Account summary">
        <div>
          <dt>Game profiles</dt>
          <dd className="dashboard-summary__value">
            {String(profiles.length).padStart(2, "0")}
          </dd>
          <dd className="dashboard-summary__detail">Ready to configure</dd>
        </div>
        <div>
          <dt>Bound cards</dt>
          <dd className="dashboard-summary__value">
            {String(me.cards.length).padStart(2, "0")}
          </dd>
          <dd className="dashboard-summary__detail">Your access points</dd>
        </div>
        <div>
          <dt>Connected games</dt>
          <dd className="dashboard-summary__value">
            {String(connectedGames).padStart(2, "0")}
          </dd>
          <dd className="dashboard-summary__detail">
            On the network since {fmtDate(me.created_at)}
          </dd>
        </div>
      </dl>

      <Grid fullWidth className="dashboard-body">
        <Column sm={4} md={8} lg={12} className="dashboard-profiles">
          <div className="dashboard-section__heading">
            <div>
              <SectionLabel index="01">Identity layer</SectionLabel>
              <h2>Game profiles</h2>
            </div>
            {profiles.length > 0 && (
              <Link className="dashboard-section__link" to="/scores">
                View all scores <ArrowRight size={16} />
              </Link>
            )}
          </div>

          {profiles.length > 0 ? (
            <ol className="profile-grid">
              {profiles.map((profile, index) => (
                <ProfileCard
                  key={`${profile.table}:${profile.doc_id}`}
                  profile={profile}
                  game={games.find((candidate) => candidate.key === profile.game)}
                  index={index}
                />
              ))}
            </ol>
          ) : (
            <div className="dashboard-empty">
              <GameConsole size={48} aria-hidden="true" />
              <h3>No game profiles yet</h3>
              <p>
                Play once with a bound card, or bind a card you have already used. Your
                profiles will appear here automatically.
              </p>
              <Button as={Link} to="/cards" renderIcon={Add}>
                Bind a card
              </Button>
            </div>
          )}
        </Column>

        <Column sm={4} md={8} lg={4}>
          <aside className="access-panel" aria-labelledby="access-panel-title">
            <div className="access-panel__heading">
              <SectionLabel index="02">Access layer</SectionLabel>
              <Wallet size={32} aria-hidden="true" />
              <h2 id="access-panel-title">Your cards</h2>
              <p>Physical access points linked to this account.</p>
            </div>

            {me.cards.length > 0 ? (
              <ol className="access-list">
                {me.cards.map((uid, index) => {
                  const konamiId = konamiCache.get(uid);
                  const profileCount = profilesByCard.get(uid) || 0;
                  return (
                    <li key={uid}>
                      <span className="access-list__index" aria-hidden="true">
                        {String(index + 1).padStart(2, "0")}
                      </span>
                      <div>
                        <p className="access-list__uid">{uid}</p>
                        <p className="access-list__meta">
                          {konamiId ? `Konami ID ${konamiId}` : "Konami ID unavailable"}
                        </p>
                        <p className="access-list__profiles">
                          <span aria-hidden="true" />
                          {profileCount} {profileCount === 1 ? "profile" : "profiles"}
                        </p>
                      </div>
                    </li>
                  );
                })}
              </ol>
            ) : (
              <div className="access-panel__empty">
                <p>No cards are bound to this account yet.</p>
              </div>
            )}

            <Button
              as={Link}
              to="/cards"
              kind="secondary"
              renderIcon={ArrowRight}
              className="access-panel__action"
            >
              {me.cards.length ? "Manage cards" : "Bind your first card"}
            </Button>
          </aside>
        </Column>
      </Grid>
    </div>
  );
}

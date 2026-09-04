import { useEffect, useState } from "react";
import { useSearchParams } from "react-router";
import {
  Dropdown,
  ComboBox,
  DataTable,
  Table,
  TableHead,
  TableRow,
  TableHeader,
  TableBody,
  TableCell,
  TableContainer,
  Tag,
  InlineLoading,
  InlineNotification,
} from "@carbon/react";
import { api, getGames, scoreTableMeta } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { fmtDate, compare, humanError } from "../util.js";
import { PageState, SectionHeading, SignalHero } from "../components/SignalLayout.jsx";

const HEADERS = [
  { key: "rank", header: "Rank" },
  { key: "name", header: "Player" },
  { key: "score", header: "Score" },
  { key: "timestamp", header: "Date" },
];

const LIMITS = [10, 25, 50, 100];
const isInt = (s) => /^\d+$/.test(s);

export default function Rankings() {
  const authFailure = useAuthFailure();
  const [searchParams, setSearchParams] = useSearchParams();

  const game = searchParams.get("game") || "";
  const song = searchParams.get("song") || "";
  const chart = searchParams.get("chart") || "";
  const limit = LIMITS.includes(Number(searchParams.get("limit")))
    ? Number(searchParams.get("limit"))
    : 50;

  const [gamesMeta, setGamesMeta] = useState(null);
  const [myIds, setMyIds] = useState(new Map()); // game key -> Set of game_id strings
  const [loadError, setLoadError] = useState(null);
  const [ownRows, setOwnRows] = useState([]); // own best-table rows, song/chart suggestions
  const [board, setBoard] = useState(null); // leaderboard response
  const [boardLoading, setBoardLoading] = useState(false);
  const [boardError, setBoardError] = useState(null);

  const setParams = (updates) => {
    const next = new URLSearchParams(searchParams);
    for (const [key, value] of Object.entries(updates)) {
      if (value === "" || value === null) next.delete(key);
      else next.set(key, String(value));
    }
    setSearchParams(next, { replace: true });
  };

  useEffect(() => {
    Promise.all([getGames(), api.profiles()])
      .then(([games, { profiles }]) => {
        const ids = new Map();
        for (const p of profiles) {
          if (p.game_id == null) continue;
          if (!ids.has(p.game)) ids.set(p.game, new Set());
          ids.get(p.game).add(String(p.game_id));
        }
        setGamesMeta(games);
        setMyIds(ids);
      })
      .catch((err) => {
        if (!authFailure(err)) setLoadError(humanError(err));
      });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const gameMeta = gamesMeta?.find((g) => g.key === game) ?? null;
  const bestTable = gameMeta?.score_tables?.find((t) => t.kind === "best") ?? null;

  // Seed song/chart suggestions from the player's own best-table rows.
  useEffect(() => {
    setOwnRows([]);
    if (!gameMeta || !bestTable) return;
    const controller = new AbortController();
    api
      .myScores({ limit: 200, signal: controller.signal })
      .then((d) => {
        setOwnRows(
          (d.items || []).filter((r) => r.game === game && r.table === bestTable.table)
        );
      })
      .catch((err) => {
        if (err?.name !== "AbortError" && !authFailure(err)) setLoadError(humanError(err));
      });
    return () => controller.abort();
  }, [game]); // eslint-disable-line react-hooks/exhaustive-deps

  const selectionValid = game && isInt(song) && isInt(chart);

  // Fetch the bounded leaderboard for exactly the current selection.
  useEffect(() => {
    setBoard(null);
    setBoardError(null);
    if (!selectionValid) return;
    const controller = new AbortController();
    setBoardLoading(true);
    api
      .rankings({ game, song, chart, limit, signal: controller.signal })
      .then((d) => {
        setBoard(d);
        setBoardLoading(false);
      })
      .catch((err) => {
        if (err?.name === "AbortError") return;
        setBoardLoading(false);
        if (!authFailure(err)) setBoardError(humanError(err));
      });
    return () => controller.abort();
  }, [game, song, chart, limit]); // eslint-disable-line react-hooks/exhaustive-deps

  if (loadError) {
    return <PageState kind="error" title="Could not load rankings" description={loadError} />;
  }

  if (!gamesMeta) {
    return <PageState title="Loading leaderboard controls…" />;
  }

  const songField = bestTable?.song_field ?? "song";
  const chartField = bestTable?.chart_field ?? "chart";

  const songIds = [...new Set(ownRows.map((r) => String(r[songField] ?? "")).filter(Boolean))].sort(
    compare
  );
  const chartIds = [
    ...new Set(
      ownRows
        .filter((r) => String(r[songField]) === song)
        .map((r) => String(r[chartField] ?? ""))
        .filter(Boolean)
    ),
  ].sort(compare);

  const icon = game ? gameIcon(game) : null;
  const mine = myIds.get(game) ?? new Set();

  const entryRows = (board?.items || []).map((e, i) => ({
    id: String(i),
    rank: e.rank,
    name: (
      <span className="signal-table__player">
        {e.name ?? "—"}
        {mine.has(String(e.game_id)) && (
          <Tag type="green" size="sm">
            you
          </Tag>
        )}
      </span>
    ),
    score: String(e.score),
    timestamp: fmtDate(e.timestamp),
  }));

  return (
    <div className="signal-page rankings-page">
      <SignalHero
        index="03"
        eyebrow="Competitive field"
        title="Find your place"
        accent="in the field."
        description="Choose one game, song, and chart to resolve a precise leaderboard. Your own identities are marked in the result."
        tone="teal"
        metrics={[
          { label: "Top", value: String(limit).padStart(2, "0") },
          { label: "Entries", value: String(board?.items?.length ?? 0).padStart(2, "0") },
        ]}
        visualLabel="Global rank / personal position"
      />

      <section className="signal-page__body" aria-label="Leaderboard query">
        <SectionHeading
          index="03.A"
          eyebrow="Chart coordinates"
          title="Build a leaderboard"
          description="Suggestions come from your own records. Numeric song and chart IDs can also be entered directly."
        />

        <div className="signal-filter-grid signal-filter-grid--rankings">
          <div className="signal-control">
            <span className="signal-control__step" aria-hidden="true">01</span>
            <Dropdown
              id="ranking-game"
              titleText="Game"
              label="Pick a game"
              items={gamesMeta}
              itemToString={(item) => (item ? item.name : "")}
              selectedItem={gameMeta}
              onChange={({ selectedItem }) =>
                setParams({ game: selectedItem?.key || null, song: null, chart: null })
              }
            />
          </div>
          <div className="signal-control">
            <span className="signal-control__step" aria-hidden="true">02</span>
            <ComboBox
              id="ranking-song"
              titleText="Song"
              placeholder="Pick or type an ID"
              items={songIds}
              allowCustomValue
              disabled={!game}
              selectedItem={song || null}
              onChange={({ selectedItem }) =>
                setParams({ song: selectedItem ? String(selectedItem) : null, chart: null })
              }
              invalid={Boolean(song) && !isInt(song)}
              invalidText="Song id must be a number"
            />
          </div>
          <div className="signal-control">
            <span className="signal-control__step" aria-hidden="true">03</span>
            <ComboBox
              id="ranking-chart"
              titleText="Chart"
              placeholder="Pick or type an ID"
              items={chartIds}
              allowCustomValue
              disabled={!song}
              selectedItem={chart || null}
              onChange={({ selectedItem }) =>
                setParams({ chart: selectedItem ? String(selectedItem) : null })
              }
              invalid={Boolean(chart) && !isInt(chart)}
              invalidText="Chart id must be a number"
            />
          </div>
          <div className="signal-control">
            <span className="signal-control__step" aria-hidden="true">04</span>
            <Dropdown
              id="ranking-limit"
              titleText="Top"
              label="50"
              items={LIMITS}
              itemToString={(item) => (item ? String(item) : "")}
              selectedItem={limit}
              onChange={({ selectedItem }) =>
                setParams({ limit: selectedItem === 50 ? null : selectedItem })
              }
            />
          </div>
        </div>

        <div className="leaderboard-plane">
          <div className="leaderboard-plane__identity">
            <div className="leaderboard-plane__icon">
              {icon ? <img src={icon} alt="" /> : <span aria-hidden="true">03</span>}
            </div>
            <div>
              <p>{selectionValid ? "Resolved chart" : "Awaiting coordinates"}</p>
              <h2>
                {selectionValid
                  ? `${gameMeta?.name ?? game} / ${song}.${chart}`
                  : "Select game, song, and chart"}
              </h2>
            </div>
          </div>

          {!selectionValid && (
            <div className="signal-empty-plane signal-empty-plane--dark">
              <h3>Three coordinates define the field.</h3>
              <p>The leaderboard resolves as soon as game, song, and chart are valid.</p>
            </div>
          )}
          {boardLoading && <InlineLoading description="Loading leaderboard…" />}
          {boardError && (
            <InlineNotification
              kind="error"
              title="Could not load the leaderboard"
              subtitle={boardError}
              hideCloseButton
              lowContrast
            />
          )}
          {board && !boardError && (
            <>
              <div className="signal-table-plane__meta">
                <span>TOP {limit} / {scoreTableMeta(gamesMeta, game, board.table)?.kind ?? board.table}</span>
                <span>{entryRows.length} RANKED</span>
              </div>
              {entryRows.length ? (
                <DataTable rows={entryRows} headers={HEADERS}>
                  {({ rows, headers, getTableProps, getHeaderProps, getRowProps }) => (
                    <TableContainer>
                      <Table {...getTableProps()} size="sm">
                        <TableHead>
                          <TableRow>
                            {headers.map((header) => (
                              <TableHeader key={header.key} {...getHeaderProps({ header })}>
                                {header.header}
                              </TableHeader>
                            ))}
                          </TableRow>
                        </TableHead>
                        <TableBody>
                          {rows.map((row) => (
                            <TableRow key={row.id} {...getRowProps({ row })}>
                              {row.cells.map((cell) => (
                                <TableCell key={cell.id}>{cell.value}</TableCell>
                              ))}
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </TableContainer>
                  )}
                </DataTable>
              ) : (
                <div className="signal-empty-plane signal-empty-plane--dark">
                  <h3>No scores for this chart yet</h3>
                  <p>Be the first to set a record.</p>
                </div>
              )}
            </>
          )}
        </div>
      </section>
    </div>
  );
}

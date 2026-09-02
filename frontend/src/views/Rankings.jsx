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
  Stack,
  InlineLoading,
  InlineNotification,
  SkeletonText,
  SkeletonPlaceholder,
} from "@carbon/react";
import { api, getGames, scoreTableMeta } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { fmtDate, compare, humanError } from "../util.js";

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
    return (
      <InlineNotification
        kind="error"
        title="Could not load rankings"
        subtitle={loadError}
        hideCloseButton
        lowContrast
      />
    );
  }

  if (!gamesMeta) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <SkeletonText heading width="30%" />
        <SkeletonPlaceholder style={{ width: "100%", height: "20rem" }} />
      </Stack>
    );
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
      <span style={{ display: "inline-flex", alignItems: "center", gap: "0.5rem" }}>
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
    <Stack gap={6} style={{ marginTop: "1rem" }}>
      <h1 style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
        Rankings
        {icon && <img src={icon} alt="" width={32} height={32} />}
      </h1>
      <div style={{ display: "flex", gap: "1rem", flexWrap: "wrap", alignItems: "flex-end" }}>
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
          style={{ minWidth: "16rem" }}
        />
        <ComboBox
          id="ranking-song"
          titleText="Song"
          placeholder="song id — pick or type one"
          items={songIds}
          allowCustomValue
          disabled={!game}
          selectedItem={song || null}
          onChange={({ selectedItem }) =>
            setParams({ song: selectedItem ? String(selectedItem) : null, chart: null })
          }
          invalid={Boolean(song) && !isInt(song)}
          invalidText="Song id must be a number"
          style={{ minWidth: "12rem" }}
        />
        <ComboBox
          id="ranking-chart"
          titleText="Chart"
          placeholder="chart id — pick or type one"
          items={chartIds}
          allowCustomValue
          disabled={!song}
          selectedItem={chart || null}
          onChange={({ selectedItem }) =>
            setParams({ chart: selectedItem ? String(selectedItem) : null })
          }
          invalid={Boolean(chart) && !isInt(chart)}
          invalidText="Chart id must be a number"
          style={{ minWidth: "10rem" }}
        />
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
          style={{ minWidth: "7rem" }}
        />
      </div>

      {!selectionValid && (
        <InlineNotification
          kind="info"
          title="Pick a game, song, and chart"
          subtitle="The leaderboard loads once all three are set. Song and chart suggestions come from your own records, but any id can be typed."
          hideCloseButton
          lowContrast
        />
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
          <p style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem" }}>
            {gameMeta?.name ?? board.game} · song {board.song} · chart {board.chart} · top{" "}
            {limit} of {scoreTableMeta(gamesMeta, game, board.table)?.kind ?? board.table}
          </p>
          {entryRows.length ? (
            <DataTable rows={entryRows} headers={HEADERS}>
              {({ rows, headers, getTableProps, getHeaderProps, getRowProps }) => (
                <TableContainer>
                  <Table {...getTableProps()} size="sm">
                    <TableHead>
                      <TableRow>
                        {headers.map((h) => (
                          <TableHeader key={h.key} {...getHeaderProps({ header: h })}>
                            {h.header}
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
            <InlineNotification
              kind="info"
              title="No scores for this chart yet"
              subtitle="Be the first to set a record."
              hideCloseButton
              lowContrast
            />
          )}
        </>
      )}
    </Stack>
  );
}

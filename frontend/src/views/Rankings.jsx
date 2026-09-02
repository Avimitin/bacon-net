import { useEffect, useState } from "react";
import {
  Dropdown,
  DataTable,
  Table,
  TableHead,
  TableRow,
  TableHeader,
  TableBody,
  TableCell,
  TableContainer,
  Tag,
  Tile,
  Stack,
  InlineNotification,
  Search,
  SkeletonText,
  SkeletonPlaceholder,
} from "@carbon/react";
import { api, getGames } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { fmtDate, compare, humanError } from "../util.js";

const HEADERS = [
  { key: "rank", header: "Rank" },
  { key: "name", header: "Player" },
  { key: "chart", header: "Chart" },
  { key: "score", header: "Score" },
  { key: "timestamp", header: "Date" },
];

export default function Rankings() {
  const authFailure = useAuthFailure();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [groupIdx, setGroupIdx] = useState(0);
  const [songQuery, setSongQuery] = useState("");

  useEffect(() => {
    Promise.all([api.rankings(), api.profiles(), getGames()])
      .then(([{ games: rankGames }, { profiles }, gamesMeta]) => {
        setData({ rankGames, myIds: new Set(profiles.map((p) => String(p.game_id))), gamesMeta });
      })
      .catch((err) => {
        if (!authFailure(err)) setError(humanError(err));
      });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (error) {
    return (
      <InlineNotification
        kind="error"
        title="Could not load rankings"
        subtitle={error}
        hideCloseButton
        lowContrast
      />
    );
  }

  if (!data) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <SkeletonText heading width="30%" />
        <SkeletonPlaceholder style={{ width: "100%", height: "20rem" }} />
      </Stack>
    );
  }

  const { rankGames, myIds, gamesMeta } = data;

  if (!rankGames.length) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <h1>Rankings</h1>
        <InlineNotification
          kind="info"
          title="No rankings yet"
          subtitle="Top scores appear here once players set records."
          hideCloseButton
          lowContrast
        />
      </Stack>
    );
  }

  const items = rankGames.map((g, i) => ({
    id: String(i),
    label: `${gamesMeta.find((m) => m.key === g.game)?.name ?? g.game} — ${g.table}`,
  }));
  const group = rankGames[groupIdx] ?? rankGames[0];
  const icon = gameIcon(group.game);

  const songs = new Map();
  for (const e of group.entries || []) {
    const key = String(e.song);
    if (!songs.has(key)) songs.set(key, []);
    songs.get(key).push(e);
  }
  const sortedSongs = [...songs.keys()].sort(compare);
  const matchedSongs = songQuery
    ? sortedSongs.filter((s) => s.toLowerCase().includes(songQuery)).slice(0, 20)
    : [];

  return (
    <Stack gap={6} style={{ marginTop: "1rem" }}>
      <h1 style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
        Rankings
        {icon && <img src={icon} alt="" width={32} height={32} />}
      </h1>
      <Dropdown
        id="ranking-group"
        titleText="Game / best-scores table"
        label="Pick a game and table"
        items={items}
        itemToString={(item) => (item ? item.label : "")}
        selectedItem={items[groupIdx] ?? items[0]}
        onChange={({ selectedItem }) => {
          if (selectedItem) {
            setGroupIdx(Number(selectedItem.id));
            setSongQuery("");
          }
        }}
      />
      {!sortedSongs.length && (
        <InlineNotification
          kind="info"
          title="No entries in this table yet"
          hideCloseButton
          lowContrast
        />
      )}
      {sortedSongs.length > 0 && (
        <Search
          id="ranking-song"
          labelText="Find a song"
          placeholder="type a song id to show its leaderboard…"
          value={songQuery}
          onChange={(e) => setSongQuery(e.target.value.toLowerCase())}
        />
      )}
      {sortedSongs.length > 0 && !songQuery && (
        <InlineNotification
          kind="info"
          title="Search for a song to see its leaderboard"
          subtitle={`${sortedSongs.length} songs in this table — leaderboards render once you narrow down to a song.`}
          hideCloseButton
          lowContrast
        />
      )}
      {songQuery && !matchedSongs.length && (
        <InlineNotification
          kind="info"
          title="No songs match"
          subtitle="Try a different song id."
          hideCloseButton
          lowContrast
        />
      )}
      {matchedSongs.map((song) => {
        const entries = songs
          .get(song)
          .slice()
          .sort((a, b) => a.rank - b.rank);
        const rows = entries.map((e, i) => ({
          id: String(i),
          rank: e.rank,
          name: (
            <span style={{ display: "inline-flex", alignItems: "center", gap: "0.5rem" }}>
              {e.name ?? "—"}
              {myIds.has(String(e.game_id)) && (
                <Tag type="green" size="sm">
                  you
                </Tag>
              )}
            </span>
          ),
          chart: e.chart != null ? String(e.chart) : "—",
          score: String(e.score),
          timestamp: fmtDate(e.timestamp),
        }));
        return (
          <Tile key={song}>
            <h3 style={{ marginBottom: "0.75rem" }}>
              Song <span style={{ fontFamily: "monospace", color: "var(--cds-link-primary)" }}>{song}</span>
            </h3>
            <DataTable rows={rows} headers={HEADERS}>
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
          </Tile>
        );
      })}
    </Stack>
  );
}

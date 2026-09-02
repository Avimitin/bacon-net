import { useEffect, useState } from "react";
import {
  Tabs,
  TabList,
  Tab,
  TabPanels,
  TabPanel,
  ContentSwitcher,
  Switch,
  Search,
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
  InlineNotification,
  SkeletonText,
  SkeletonPlaceholder,
} from "@carbon/react";
import { Checkmark } from "@carbon/icons-react";
import { api, getGames, scoreTableMeta } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { scoreColumns } from "../schema.js";
import { fmtTs, compare, humanError } from "../util.js";

export default function Scores() {
  const authFailure = useAuthFailure();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [gameIdx, setGameIdx] = useState(0);
  const [table, setTable] = useState(null);
  const [filter, setFilter] = useState("");

  useEffect(() => {
    Promise.all([api.myScores(), getGames()])
      .then(([{ games: myGames }, gamesMeta]) => {
        const withData = myGames.filter((g) =>
          Object.values(g.tables || {}).some((rows) => rows.length)
        );
        setData({ withData, gamesMeta });
        if (withData.length) setTable(pickDefaultTable(withData[0], gamesMeta));
      })
      .catch((err) => {
        if (!authFailure(err)) setError(humanError(err));
      });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (error) {
    return (
      <InlineNotification
        kind="error"
        title="Could not load scores"
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

  const { withData, gamesMeta } = data;

  if (!withData.length) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <h1>My scores</h1>
        <InlineNotification
          kind="info"
          title="No scores yet"
          subtitle="Play some charts — your records will land here."
          hideCloseButton
          lowContrast
        />
      </Stack>
    );
  }

  const entry = withData[gameIdx] ?? withData[0];
  const gameMeta = gamesMeta.find((g) => g.key === entry.game);
  const tableNames = Object.keys(entry.tables || {}).filter((t) => entry.tables[t].length);
  const activeTable = tableNames.includes(table) ? table : pickDefaultTable(entry, gamesMeta);

  const selectGame = ({ selectedIndex }) => {
    setGameIdx(selectedIndex);
    setTable(pickDefaultTable(withData[selectedIndex], gamesMeta));
    setFilter("");
  };

  const meta = scoreTableMeta(gamesMeta, entry.game, activeTable) || {};
  const songField = meta.song_field || "music_id";
  const scoreField = meta.score_field || "score";
  const allRows = entry.tables[activeTable] || [];
  const columns = scoreColumns(entry.game, allRows[0]);
  const rowsRaw = allRows
    .filter((r) => {
      if (!filter) return true;
      return columns.some((c) =>
        String(r[c.key] ?? "").toLowerCase().includes(filter)
      );
    })
    .sort((a, b) => {
      const s = compare(a[songField], b[songField]);
      if (s !== 0) return s;
      return compare(b[scoreField], a[scoreField]); // score desc
    });

  const headers = columns.map((c) => ({ key: c.key, header: c.label }));
  const rows = rowsRaw.map((r) => {
    const row = {
      id: String(
        r._id ?? [r[songField], r.chart, r[scoreField], r.timestamp].join(":")
      ),
    };
    for (const c of columns) row[c.key] = renderCell(c, r[c.key]);
    return row;
  });

  return (
    <Stack gap={6} style={{ marginTop: "1rem" }}>
      <h1>My scores</h1>
      <Tabs selectedIndex={gameIdx} onChange={selectGame}>
        <TabList aria-label="Games">
          {withData.map((g) => {
            const gm = gamesMeta.find((x) => x.key === g.game);
            const icon = gameIcon(g.game);
            return (
              <Tab key={g.game}>
                <span style={{ display: "inline-flex", alignItems: "center", gap: "0.5rem" }}>
                  {icon && <img src={icon} alt="" width={32} height={32} />}
                  {gm?.name ?? g.game}
                </span>
              </Tab>
            );
          })}
        </TabList>
        <TabPanels>
          {withData.map((g) => (
            <TabPanel key={g.game}>
              {g.game === entry.game && (
                <Stack gap={4} style={{ paddingTop: "1rem" }}>
                  <ContentSwitcher
                    selectedIndex={Math.max(0, tableNames.indexOf(activeTable))}
                    onChange={(e) => setTable(e.name)}
                  >
                    {tableNames.map((t) => {
                      const m = scoreTableMeta(gamesMeta, entry.game, t);
                      return <Switch key={t} name={t} text={m?.kind ?? t.replace(/^.*?_/, "")} />;
                    })}
                  </ContentSwitcher>
                  <Search
                    id="score-filter"
                    labelText="Filter rows"
                    placeholder="filter by song, score, chart…"
                    value={filter}
                    onChange={(e) => setFilter(e.target.value.toLowerCase())}
                  />
                  {rows.length ? (
                    <DataTable rows={rows} headers={headers}>
                      {({ rows, headers, getTableProps, getHeaderProps, getRowProps }) => (
                        <TableContainer title={gameMeta?.name ?? entry.game}>
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
                      title="Nothing matches"
                      subtitle="Try a different filter or table."
                      hideCloseButton
                      lowContrast
                    />
                  )}
                </Stack>
              )}
            </TabPanel>
          ))}
        </TabPanels>
      </Tabs>
    </Stack>
  );
}

function pickDefaultTable(entry, gamesMeta) {
  const names = Object.keys(entry.tables || {}).filter((t) => entry.tables[t].length);
  const best = names.find(
    (t) => scoreTableMeta(gamesMeta, entry.game, t)?.kind === "best" || t.endsWith("_best")
  );
  return best ?? names[0] ?? null;
}

function renderCell(col, value) {
  if (value == null || value === "") return "—";
  switch (col.kind) {
    case "ts":
      return fmtTs(value);
    case "badge":
      return (
        <Tag type="cool-gray" size="sm">
          {String(value)}
        </Tag>
      );
    case "bool":
      return value ? <Checkmark size={16} aria-label="yes" /> : "—";
    case "pct":
      return `${value}%`;
    default:
      return String(value);
  }
}

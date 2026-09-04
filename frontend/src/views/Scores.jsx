import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router";
import {
  Dropdown,
  Search,
  DataTable,
  Table,
  TableHead,
  TableRow,
  TableHeader,
  TableBody,
  TableCell,
  TableContainer,
  Pagination,
  Tag,
  InlineLoading,
  InlineNotification,
} from "@carbon/react";
import { Checkmark } from "@carbon/icons-react";
import { api, getGames } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { scoreColumns } from "../schema.js";
import { fmtTs, humanError } from "../util.js";
import { PageState, SectionHeading, SignalHero } from "../components/SignalLayout.jsx";

const PAGE_SIZES = [25, 50, 100, 200];
const DEFAULT_PAGE_SIZE = 50;

export default function Scores() {
  const authFailure = useAuthFailure();
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Math.max(1, Number(searchParams.get("page")) || 1);
  const pageSize = PAGE_SIZES.includes(Number(searchParams.get("pageSize")))
    ? Number(searchParams.get("pageSize"))
    : DEFAULT_PAGE_SIZE;
  const gameFilter = searchParams.get("game") || "";
  const filter = (searchParams.get("q") || "").toLowerCase();

  const [gamesMeta, setGamesMeta] = useState(null);
  const [pageData, setPageData] = useState(null); // { items, nextCursor }
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  // Cursor stack: page N is fetched with cursors[N]; page 1 has no cursor.
  const cursors = useRef({ 1: null });

  const setParams = (updates) => {
    const next = new URLSearchParams(searchParams);
    for (const [key, value] of Object.entries(updates)) {
      if (value === "" || value === null) next.delete(key);
      else next.set(key, String(value));
    }
    setSearchParams(next, { replace: true });
  };

  useEffect(() => {
    getGames()
      .then(setGamesMeta)
      .catch((err) => {
        if (!authFailure(err)) setError(humanError(err));
      });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    // A deep-linked page without a known cursor cannot be fetched — restart.
    if (page > 1 && !(page in cursors.current)) {
      setParams({ page: null });
      return;
    }
    const controller = new AbortController();
    setLoading(true);
    setError(null);
    api
      .myScores({ limit: pageSize, cursor: cursors.current[page], signal: controller.signal })
      .then((d) => {
        if (d.next_cursor) cursors.current[page + 1] = d.next_cursor;
        else delete cursors.current[page + 1];
        setPageData(d);
        setLoading(false);
      })
      .catch((err) => {
        if (err?.name === "AbortError") return;
        setLoading(false);
        if (!authFailure(err)) setError(humanError(err));
      });
    return () => controller.abort();
  }, [page, pageSize]); // eslint-disable-line react-hooks/exhaustive-deps

  if (error && !pageData) {
    return <PageState kind="error" title="Could not load scores" description={error} />;
  }

  if (!pageData || !gamesMeta) {
    return <PageState title="Loading score archive…" />;
  }

  const items = pageData.items || [];

  const onPageChange = ({ page: nextPage, pageSize: nextSize }) => {
    if (nextSize !== pageSize) {
      cursors.current = { 1: null }; // page size change invalidates cursors
      setParams({ page: null, pageSize: nextSize === DEFAULT_PAGE_SIZE ? null : nextSize });
    } else if (nextPage !== page) {
      setParams({ page: nextPage === 1 ? null : nextPage });
    }
  };

  // Client-side filters apply to the loaded page only.
  const rowsRaw = items.filter((r) => {
    if (gameFilter && r.game !== gameFilter) return false;
    if (!filter) return true;
    return Object.values(r).some((v) => String(v ?? "").toLowerCase().includes(filter));
  });

  // Columns: union over the games present in the filtered rows.
  const colMap = new Map();
  for (const r of rowsRaw) {
    for (const c of scoreColumns(r.game, r)) {
      if (!colMap.has(c.key)) colMap.set(c.key, c);
    }
  }
  const columns = [...colMap.values()];
  const headers = [
    { key: "game", header: "Game" },
    { key: "table", header: "Table" },
    ...columns.map((c) => ({ key: c.key, header: c.label })),
  ];

  const gameName = (key) => gamesMeta.find((g) => g.key === key)?.name ?? key;
  const tableKind = (gameKey, table) =>
    gamesMeta.find((g) => g.key === gameKey)?.score_tables?.find((t) => t.table === table)?.kind ??
    table;

  const rows = rowsRaw.map((r, i) => {
    const icon = gameIcon(r.game);
    const row = {
      id: `${r.game}:${r.table}:${r.timestamp ?? i}:${i}`,
      game: (
        <span className="signal-table__game">
          {icon && <img src={icon} alt="" width={20} height={20} />}
          {gameName(r.game)}
        </span>
      ),
      table: (
        <Tag type="cool-gray" size="sm">
          {tableKind(r.game, r.table)}
        </Tag>
      ),
    };
    for (const c of columns) row[c.key] = renderCell(c, r[c.key]);
    return row;
  });

  const gameItems = [
    { id: "", label: "All games" },
    ...gamesMeta.map((g) => ({ id: g.key, label: g.name })),
  ];

  return (
    <div className="signal-page scores-page">
      <SignalHero
        index="02"
        eyebrow="Performance archive"
        title="Every play leaves"
        accent="a signal."
        description="Scan your recent records across every connected game, then narrow the loaded page by title, chart, score, or table."
        tone="purple"
        metrics={[
          { label: "Page", value: String(page).padStart(2, "0") },
          { label: "Loaded", value: String(items.length).padStart(2, "0") },
        ]}
        visualLabel="Records / chronological stream"
      />

      <section className="signal-page__body" aria-label="Score archive">
        <SectionHeading
          index="02.A"
          eyebrow="Loaded records"
          title="Score archive"
          description="Filters affect this loaded page only. Pagination requests the next block from the server."
        />
        {error && (
          <InlineNotification
            kind="error"
            title="Could not load this page"
            subtitle={error}
            hideCloseButton
            lowContrast
          />
        )}
        <div className="signal-filter-grid signal-filter-grid--scores">
          <div className="signal-control signal-control--game">
            <Dropdown
              id="score-game-filter"
              titleText="Game"
              label="All games"
              items={gameItems}
              itemToString={(item) => (item ? item.label : "")}
              selectedItem={gameItems.find((g) => g.id === gameFilter) ?? gameItems[0]}
              onChange={({ selectedItem }) => setParams({ game: selectedItem?.id || null })}
            />
          </div>
          <div className="signal-control signal-control--search">
            <Search
              id="score-filter"
              labelText="Filter rows"
              placeholder="Filter by song, score, chart…"
              value={filter}
              onChange={(e) => setParams({ q: e.target.value || null })}
            />
          </div>
        </div>

        <div className="signal-table-plane">
          <div className="signal-table-plane__meta">
            <span>PAGE / {String(page).padStart(2, "0")}</span>
            <span>{rows.length} VISIBLE / {items.length} LOADED</span>
          </div>
          {loading && <InlineLoading description="Loading scores…" />}
          {rows.length ? (
            <DataTable rows={rows} headers={headers}>
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
            !loading && (
              <div className="signal-empty-plane signal-empty-plane--compact">
                <h3>{items.length ? "Nothing matches on this page" : "No scores yet"}</h3>
                <p>
                  {items.length
                    ? "Try a different filter, or move to another page."
                    : "Play some charts — your records will land here."}
                </p>
              </div>
            )
          )}
          <Pagination
            id="scores-pagination"
            page={page}
            pageSize={pageSize}
            pageSizes={PAGE_SIZES}
            pagesUnknown
            isLastPage={!pageData.next_cursor}
            itemsPerPageText="Rows per page"
            backwardText="Previous page"
            forwardText="Next page"
            onChange={onPageChange}
          />
        </div>
      </section>
    </div>
  );
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

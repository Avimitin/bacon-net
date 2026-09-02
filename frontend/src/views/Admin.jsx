import { useEffect, useRef, useState } from "react";
import {
  Tabs,
  TabList,
  Tab,
  TabPanels,
  TabPanel,
  Form,
  PasswordInput,
  TextInput,
  TextArea,
  Button,
  Tag,
  Tile,
  Stack,
  Dropdown,
  Search,
  Modal,
  Pagination,
  DataTable,
  Table,
  TableHead,
  TableRow,
  TableHeader,
  TableBody,
  TableCell,
  TableContainer,
  InlineNotification,
  SkeletonText,
  SkeletonPlaceholder,
} from "@carbon/react";
import { api, tokens } from "../api.js";
import { fmtDate, fmtTs, humanError, parseJsonObject } from "../util.js";

export default function Admin() {
  const [unlocked, setUnlocked] = useState(Boolean(tokens.admin));
  const lock = () => {
    tokens.admin = null;
    setUnlocked(false);
  };

  if (!unlocked) return <Gate onUnlock={() => setUnlocked(true)} />;

  return (
    <Stack gap={6} style={{ marginTop: "1rem" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>Admin</h1>
        <Button kind="ghost" size="sm" onClick={() => { lock(); }}>
          Forget token
        </Button>
      </div>
      <Tabs>
        <TabList aria-label="Admin areas">
          <Tab>Shops</Tab>
          <Tab>Users</Tab>
          <Tab>Tables</Tab>
          <Tab>Docs</Tab>
          <Tab>Cards</Tab>
          <Tab>Audit</Tab>
        </TabList>
        <TabPanels>
          <TabPanel>
            <ShopsPanel onLock={lock} />
          </TabPanel>
          <TabPanel>
            <UsersPanel onLock={lock} />
          </TabPanel>
          <TabPanel>
            <TablesPanel onLock={lock} />
          </TabPanel>
          <TabPanel>
            <DocsPanel onLock={lock} />
          </TabPanel>
          <TabPanel>
            <CardsPanel onLock={lock} />
          </TabPanel>
          <TabPanel>
            <AuditPanel onLock={lock} />
          </TabPanel>
        </TabPanels>
      </Tabs>
    </Stack>
  );
}

function Gate({ onUnlock }) {
  const [value, setValue] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const submit = async (ev) => {
    ev.preventDefault();
    const token = value.trim();
    if (!token) return;
    setError(null);
    setBusy(true);
    tokens.admin = token;
    try {
      await api.tables(); // verify the token before unlocking
      onUnlock();
    } catch (err) {
      tokens.admin = null;
      setError(
        err.status === 401
          ? "Token rejected — enter it again."
          : humanError(err)
      );
      setBusy(false);
    }
  };

  return (
    <Stack gap={6} style={{ marginTop: "1rem", maxWidth: "32rem" }}>
      <h1>Admin</h1>
      <Tile>
        <Stack gap={5}>
          <p style={{ color: "var(--cds-text-secondary)" }}>
            Operator area. The admin token is separate from your player login and is stored in
            this browser only.
          </p>
          <Form onSubmit={submit}>
            <Stack gap={5}>
              <PasswordInput
                id="admin-token"
                labelText="Admin token"
                placeholder="admin bearer token"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                style={{ fontFamily: "monospace" }}
              />
              {error && (
                <InlineNotification
                  kind="error"
                  title="Unlock failed"
                  subtitle={error}
                  hideCloseButton
                  lowContrast
                />
              )}
              <Button type="submit" disabled={busy}>
                {busy ? "Checking…" : "Unlock admin area"}
              </Button>
            </Stack>
          </Form>
        </Stack>
      </Tile>
    </Stack>
  );
}

// Shared admin fetch error handling: a 401 drops the token and re-locks.
function adminCatch(err, onLock, setError) {
  if (err?.status === 401) {
    onLock();
    return;
  }
  setError(humanError(err));
}

function PanelSkeleton() {
  return (
    <Stack gap={4} style={{ paddingTop: "1rem" }}>
      <SkeletonText width="30%" />
      <SkeletonPlaceholder style={{ width: "100%", height: "14rem" }} />
    </Stack>
  );
}

function PanelError({ title, error }) {
  if (!error) return null;
  return (
    <InlineNotification kind="error" title={title} subtitle={error} hideCloseButton lowContrast />
  );
}

// ---------- Shops ----------

const SHOP_HEADERS = [
  { key: "pcbid", header: "PCBID" },
  { key: "opname", header: "Operator" },
  { key: "status", header: "Status" },
  { key: "first_seen", header: "First seen" },
  { key: "actions", header: "Actions" },
];

function ShopsPanel({ onLock }) {
  const [shops, setShops] = useState(null);
  const [error, setError] = useState(null);
  const [confirm, setConfirm] = useState(null); // { action: "permit"|"revoke"|"delete", shop }
  const [confirmError, setConfirmError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [addPcbid, setAddPcbid] = useState("");
  const [addOpname, setAddOpname] = useState("");
  const [addError, setAddError] = useState(null);

  const load = () => {
    api
      .shops()
      .then((d) => setShops(d.shops))
      .catch((err) => adminCatch(err, onLock, setError));
  };
  useEffect(load, []); // eslint-disable-line react-hooks/exhaustive-deps

  const runConfirm = async () => {
    const { action, shop } = confirm;
    setConfirmError(null);
    setBusy(true);
    try {
      if (action === "permit") await api.permitShop(shop.pcbid);
      else if (action === "revoke") await api.revokeShop(shop.pcbid);
      else await api.deleteShop(shop.pcbid);
      setConfirm(null);
      setBusy(false);
      load();
    } catch (err) {
      setBusy(false);
      if (err?.status === 401) onLock();
      else setConfirmError(humanError(err));
    }
  };

  const addShop = async () => {
    const pcbid = addPcbid.trim();
    if (!pcbid) return;
    setAddError(null);
    setBusy(true);
    try {
      await api.createShop(pcbid, addOpname.trim() || undefined);
      setAddOpen(false);
      setAddPcbid("");
      setAddOpname("");
      setBusy(false);
      load();
    } catch (err) {
      setBusy(false);
      if (err?.status === 401) onLock();
      else setAddError(humanError(err));
    }
  };

  if (error) return <PanelError title="Could not load shops" error={error} />;
  if (!shops) return <PanelSkeleton />;

  const rows = shops.map((s) => ({
    id: s.pcbid,
    pcbid: <span style={{ fontFamily: "monospace" }}>{s.pcbid}</span>,
    opname: s.opname ?? "—",
    status: s.permitted ? (
      <Tag type="green" size="md">
        Permitted
      </Tag>
    ) : (
      <Tag type="gray" size="md">
        Pending
      </Tag>
    ),
    first_seen: fmtTs(s.first_seen),
    actions: (
      <span style={{ display: "inline-flex", gap: "0.5rem" }}>
        {s.permitted ? (
          <Button kind="ghost" size="sm" onClick={() => setConfirm({ action: "revoke", shop: s })}>
            Revoke
          </Button>
        ) : (
          <Button kind="primary" size="sm" onClick={() => setConfirm({ action: "permit", shop: s })}>
            Permit
          </Button>
        )}
        <Button
          kind="danger--ghost"
          size="sm"
          onClick={() => setConfirm({ action: "delete", shop: s })}
        >
          Delete
        </Button>
      </span>
    ),
  }));

  const confirmText = confirm
    ? {
        permit: `Permit shop ${confirm.shop.pcbid}? The cabinet will be allowed to connect.`,
        revoke: `Revoke shop ${confirm.shop.pcbid}? The cabinet will no longer be allowed to connect.`,
        delete: `Delete shop ${confirm.shop.pcbid} permanently?`,
      }[confirm.action]
    : "";

  return (
    <Stack gap={5} style={{ paddingTop: "1rem" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h3>Shops</h3>
        <Button onClick={() => setAddOpen(true)}>Add shop</Button>
      </div>
      <p style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem" }}>
        Permitted cabinet PCBIDs. Shops appear as Pending when an unknown cabinet first connects.
      </p>
      {shops.length ? (
        <DataTable rows={rows} headers={SHOP_HEADERS}>
          {({ rows, headers, getTableProps, getHeaderProps, getRowProps }) => (
            <TableContainer>
              <Table {...getTableProps()} size="md">
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
          title="No shops registered"
          subtitle="Add one manually, or wait for a cabinet to connect."
          hideCloseButton
          lowContrast
        />
      )}

      <Modal
        open={confirm !== null}
        danger={confirm?.action === "delete"}
        modalHeading={confirm ? `${capitalize(confirm.action)} shop` : ""}
        primaryButtonText={confirm ? capitalize(confirm.action) : ""}
        secondaryButtonText="Cancel"
        primaryButtonDisabled={busy}
        onRequestClose={() => {
          setConfirm(null);
          setConfirmError(null);
        }}
        onRequestSubmit={runConfirm}
      >
        <p>{confirmText}</p>
        {confirmError && (
          <InlineNotification
            kind="error"
            title="Action failed"
            subtitle={confirmError}
            hideCloseButton
            lowContrast
          />
        )}
      </Modal>

      <Modal
        open={addOpen}
        modalHeading="Add shop"
        primaryButtonText="Add"
        secondaryButtonText="Cancel"
        primaryButtonDisabled={busy || !addPcbid.trim()}
        onRequestClose={() => {
          setAddOpen(false);
          setAddError(null);
        }}
        onRequestSubmit={addShop}
      >
        <Stack gap={5}>
          <TextInput
            id="add-shop-pcbid"
            labelText="PCBID (required)"
            value={addPcbid}
            onChange={(e) => setAddPcbid(e.target.value)}
            style={{ fontFamily: "monospace" }}
          />
          <TextInput
            id="add-shop-opname"
            labelText="Operator name (optional)"
            value={addOpname}
            onChange={(e) => setAddOpname(e.target.value)}
          />
          {addError && (
            <InlineNotification
              kind="error"
              title="Could not add shop"
              subtitle={addError}
              hideCloseButton
              lowContrast
            />
          )}
        </Stack>
      </Modal>
    </Stack>
  );
}

// ---------- Users ----------

const USER_HEADERS = [
  { key: "username", header: "Username" },
  { key: "cards", header: "Cards" },
  { key: "created_at", header: "Created" },
  { key: "status", header: "Status" },
  { key: "actions", header: "Actions" },
];

function UsersPanel({ onLock }) {
  const [users, setUsers] = useState(null);
  const [error, setError] = useState(null);
  const [confirm, setConfirm] = useState(null); // { action: "ban"|"unban", user }
  const [confirmError, setConfirmError] = useState(null);
  const [busy, setBusy] = useState(false);

  const load = () => {
    api
      .users()
      .then((d) => setUsers(d.users))
      .catch((err) => adminCatch(err, onLock, setError));
  };
  useEffect(load, []); // eslint-disable-line react-hooks/exhaustive-deps

  const runConfirm = async () => {
    const { action, user } = confirm;
    setConfirmError(null);
    setBusy(true);
    try {
      if (action === "ban") await api.banUser(user.username);
      else await api.unbanUser(user.username);
      setConfirm(null);
      setBusy(false);
      load();
    } catch (err) {
      setBusy(false);
      if (err?.status === 401) onLock();
      else setConfirmError(humanError(err));
    }
  };

  if (error) return <PanelError title="Could not load users" error={error} />;
  if (!users) return <PanelSkeleton />;

  const rows = users.map((u) => ({
    id: u.username,
    username: u.username,
    cards: (u.cards || []).length ? (
      <span style={{ fontFamily: "monospace", fontSize: "0.875rem" }}>{u.cards.join(", ")}</span>
    ) : (
      "—"
    ),
    created_at: fmtDate(u.created_at),
    status: u.banned ? (
      <Tag type="red" size="md">
        Banned
      </Tag>
    ) : (
      <Tag type="green" size="md">
        Active
      </Tag>
    ),
    actions: u.banned ? (
      <Button kind="ghost" size="sm" onClick={() => setConfirm({ action: "unban", user: u })}>
        Unban
      </Button>
    ) : (
      <Button kind="danger--ghost" size="sm" onClick={() => setConfirm({ action: "ban", user: u })}>
        Ban
      </Button>
    ),
  }));

  return (
    <Stack gap={5} style={{ paddingTop: "1rem" }}>
      <h3>Users</h3>
      {users.length ? (
        <DataTable rows={rows} headers={USER_HEADERS}>
          {({ rows, headers, getTableProps, getHeaderProps, getRowProps }) => (
            <TableContainer>
              <Table {...getTableProps()} size="md">
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
        <InlineNotification kind="info" title="No users yet" hideCloseButton lowContrast />
      )}

      <Modal
        open={confirm !== null}
        danger={confirm?.action === "ban"}
        modalHeading={confirm ? `${capitalize(confirm.action)} user` : ""}
        primaryButtonText={confirm ? capitalize(confirm.action) : ""}
        secondaryButtonText="Cancel"
        primaryButtonDisabled={busy}
        onRequestClose={() => {
          setConfirm(null);
          setConfirmError(null);
        }}
        onRequestSubmit={runConfirm}
      >
        <p>
          {confirm?.action === "ban"
            ? `Ban ${confirm?.user.username}? They will no longer be able to log in.`
            : `Lift the ban on ${confirm?.user.username}?`}
        </p>
        {confirmError && (
          <InlineNotification
            kind="error"
            title="Action failed"
            subtitle={confirmError}
            hideCloseButton
            lowContrast
          />
        )}
      </Modal>
    </Stack>
  );
}

// ---------- Tables ----------

const TABLE_HEADERS = [
  { key: "name", header: "Table" },
  { key: "count", header: "Documents" },
  { key: "actions", header: "Actions" },
];

function TablesPanel({ onLock }) {
  const [tables, setTables] = useState(null);
  const [error, setError] = useState(null);
  const [dropTarget, setDropTarget] = useState(null);
  const [dropError, setDropError] = useState(null);
  const [busy, setBusy] = useState(false);

  const load = () => {
    api
      .tables()
      .then((d) => setTables(d.tables))
      .catch((err) => adminCatch(err, onLock, setError));
  };
  useEffect(load, []); // eslint-disable-line react-hooks/exhaustive-deps

  const drop = async () => {
    setDropError(null);
    setBusy(true);
    try {
      await api.dropTable(dropTarget);
      setDropTarget(null);
      setBusy(false);
      load();
    } catch (err) {
      setBusy(false);
      if (err?.status === 401) onLock();
      else setDropError(humanError(err));
    }
  };

  if (error) return <PanelError title="Could not load tables" error={error} />;
  if (!tables) return <PanelSkeleton />;

  const rows = tables.map((t) => ({
    id: t.name,
    name: <span style={{ fontFamily: "monospace" }}>{t.name}</span>,
    count: `${t.count} doc${t.count === 1 ? "" : "s"}`,
    actions: (
      <Button kind="danger--ghost" size="sm" onClick={() => setDropTarget(t.name)}>
        Drop
      </Button>
    ),
  }));

  return (
    <Stack gap={5} style={{ paddingTop: "1rem" }}>
      <h3>Tables</h3>
      {tables.length ? (
        <DataTable rows={rows} headers={TABLE_HEADERS}>
          {({ rows, headers, getTableProps, getHeaderProps, getRowProps }) => (
            <TableContainer>
              <Table {...getTableProps()} size="md">
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
        <InlineNotification kind="info" title="No tables" hideCloseButton lowContrast />
      )}

      <Modal
        open={dropTarget !== null}
        danger
        modalHeading="Drop table"
        primaryButtonText="Drop"
        secondaryButtonText="Cancel"
        primaryButtonDisabled={busy}
        onRequestClose={() => {
          setDropTarget(null);
          setDropError(null);
        }}
        onRequestSubmit={drop}
      >
        <p>
          Drop table <strong style={{ fontFamily: "monospace" }}>{dropTarget}</strong> and all its
          documents? This cannot be undone.
        </p>
        {dropError && (
          <InlineNotification
            kind="error"
            title="Drop failed"
            subtitle={dropError}
            hideCloseButton
            lowContrast
          />
        )}
      </Modal>
    </Stack>
  );
}

// ---------- Docs ----------

const DOC_HEADERS = [
  { key: "docid", header: "ID" },
  { key: "summary", header: "Summary" },
  { key: "actions", header: "Actions" },
];

function DocsPanel({ onLock }) {
  const [tables, setTables] = useState(null);
  const [table, setTable] = useState(null);
  const [docs, setDocs] = useState(null);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState("");
  const [editing, setEditing] = useState(null); // doc object, or "new"
  const [editorText, setEditorText] = useState("{}");
  const [patchText, setPatchText] = useState("{}");
  const [notice, setNotice] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api
      .tables()
      .then((d) => setTables(d.tables))
      .catch((err) => adminCatch(err, onLock, setError));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const loadDocs = (name) => {
    setDocs(null);
    api
      .docs(name)
      .then((d) => setDocs(d.docs))
      .catch((err) => adminCatch(err, onLock, setError));
  };

  const selectTable = (name) => {
    setTable(name);
    setEditing(null);
    setFilter("");
    setNotice(null);
    loadDocs(name);
  };

  const editorStatus = parseJsonObject(editorText);
  const patchStatus = parseJsonObject(patchText);
  const isNew = editing === "new";

  const startEdit = (doc) => {
    setEditing(doc);
    setEditorText(JSON.stringify(doc, null, 2));
    setPatchText("{}");
    setNotice(null);
  };

  const save = async () => {
    if (!editorStatus.ok) return;
    setNotice(null);
    setBusy(true);
    try {
      const saved = isNew
        ? await api.create(table, editorStatus.value)
        : await api.replace(table, editing._id, editorStatus.value);
      setEditing(saved);
      setEditorText(JSON.stringify(saved, null, 2));
      setNotice({ kind: "success", text: isNew ? "Created." : "Saved (PUT)." });
      setBusy(false);
      loadDocs(table);
    } catch (err) {
      setBusy(false);
      if (err?.status === 401) onLock();
      else setNotice({ kind: "error", text: `Save failed: ${humanError(err)}` });
    }
  };

  const applyPatch = async () => {
    if (!patchStatus.ok) return;
    setNotice(null);
    setBusy(true);
    try {
      const updated = await api.patch(table, editing._id, patchStatus.value);
      setEditing(updated);
      setEditorText(JSON.stringify(updated, null, 2));
      setNotice({ kind: "success", text: "Patch applied." });
      setBusy(false);
      loadDocs(table);
    } catch (err) {
      setBusy(false);
      if (err?.status === 401) onLock();
      else setNotice({ kind: "error", text: `Patch failed: ${humanError(err)}` });
    }
  };

  const deleteDoc = async () => {
    setBusy(true);
    try {
      await api.deleteDoc(table, deleteTarget);
      if (!isNew && editing && String(editing._id) === String(deleteTarget)) setEditing(null);
      setDeleteTarget(null);
      setBusy(false);
      loadDocs(table);
    } catch (err) {
      setBusy(false);
      setDeleteTarget(null);
      if (err?.status === 401) onLock();
      else setNotice({ kind: "error", text: `Delete failed: ${humanError(err)}` });
    }
  };

  if (error) return <PanelError title="Docs" error={error} />;
  if (!tables) return <PanelSkeleton />;

  const tableItems = tables.map((t) => ({ id: t.name, label: `${t.name} (${t.count})` }));
  const q = filter.toLowerCase();
  const matches = docs
    ? docs.filter((d) => !q || JSON.stringify(d).toLowerCase().includes(q))
    : [];
  const rows = matches.map((doc) => ({
    id: String(doc._id),
    docid: <span style={{ fontFamily: "monospace" }}>#{String(doc._id)}</span>,
    summary: summarize(doc),
    actions: (
      <span style={{ display: "inline-flex", gap: "0.5rem" }}>
        <Button kind="ghost" size="sm" onClick={() => startEdit(doc)}>
          Edit
        </Button>
        <Button kind="danger--ghost" size="sm" onClick={() => setDeleteTarget(doc._id)}>
          Delete
        </Button>
      </span>
    ),
  }));

  return (
    <Stack gap={5} style={{ paddingTop: "1rem" }}>
      <h3>Docs</h3>
      <Dropdown
        id="docs-table"
        titleText="Table"
        label="Pick a table"
        items={tableItems}
        itemToString={(item) => (item ? item.label : "")}
        selectedItem={tableItems.find((t) => t.id === table) ?? null}
        onChange={({ selectedItem }) => selectedItem && selectTable(selectedItem.id)}
      />

      {table && (
        <>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <Search
              id="docs-filter"
              labelText="Filter documents"
              placeholder="filter (substring over JSON)…"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            />
            <Button size="sm" onClick={() => startEdit("new")} style={{ marginLeft: "1rem", flexShrink: 0 }}>
              New document
            </Button>
          </div>

          {docs === null ? (
            <SkeletonPlaceholder style={{ width: "100%", height: "12rem" }} />
          ) : matches.length ? (
            <DataTable rows={rows} headers={DOC_HEADERS}>
              {({ rows, headers, getTableProps, getHeaderProps, getRowProps }) => (
                <TableContainer title={table}>
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
              title={docs.length ? "No matches" : "Table is empty"}
              hideCloseButton
              lowContrast
            />
          )}
        </>
      )}

      {editing && (
        <Tile>
          <Stack gap={5}>
            <h3>{isNew ? "New document" : `Document #${editing._id}`}</h3>
            <TextArea
              id="doc-editor"
              labelText="Document JSON"
              rows={16}
              value={editorText}
              onChange={(e) => setEditorText(e.target.value)}
              invalid={!editorStatus.ok}
              invalidText={`invalid JSON: ${editorStatus.error}`}
              helperText={editorStatus.ok ? "valid JSON" : undefined}
              style={{ fontFamily: "monospace" }}
            />
            <div style={{ display: "flex", gap: "1rem" }}>
              <Button onClick={save} disabled={busy || !editorStatus.ok}>
                {isNew ? "Create" : "Save (PUT)"}
              </Button>
              {!isNew && (
                <Button kind="danger" onClick={() => setDeleteTarget(editing._id)}>
                  Delete document
                </Button>
              )}
              <Button kind="ghost" onClick={() => setEditing(null)}>
                Cancel
              </Button>
            </div>

            {!isNew && (
              <>
                <TextArea
                  id="doc-patch"
                  labelText="Merge patch (top-level merge)"
                  rows={6}
                  value={patchText}
                  onChange={(e) => setPatchText(e.target.value)}
                  invalid={!patchStatus.ok}
                  invalidText={`invalid JSON: ${patchStatus.error}`}
                  helperText={patchStatus.ok ? "valid JSON" : undefined}
                  style={{ fontFamily: "monospace" }}
                />
                <div>
                  <Button kind="secondary" onClick={applyPatch} disabled={busy || !patchStatus.ok}>
                    Apply patch (PATCH)
                  </Button>
                </div>
              </>
            )}

            {notice && (
              <InlineNotification
                kind={notice.kind}
                title={notice.kind === "success" ? "Document" : "Error"}
                subtitle={notice.text}
                hideCloseButton
                lowContrast
              />
            )}
          </Stack>
        </Tile>
      )}

      <Modal
        open={deleteTarget !== null}
        danger
        modalHeading="Delete document"
        primaryButtonText="Delete"
        secondaryButtonText="Cancel"
        primaryButtonDisabled={busy}
        onRequestClose={() => setDeleteTarget(null)}
        onRequestSubmit={deleteDoc}
      >
        <p>
          Delete {table} #{deleteTarget}? This cannot be undone.
        </p>
      </Modal>
    </Stack>
  );
}

// ---------- Cards (grouped listing) ----------

function CardsPanel({ onLock }) {
  const [cards, setCards] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    api
      .cardsAll()
      .then((d) => setCards(d.cards))
      .catch((err) => adminCatch(err, onLock, setError));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  if (error) return <PanelError title="Could not load cards" error={error} />;
  if (!cards) return <PanelSkeleton />;

  if (!cards.length) {
    return <InlineNotification kind="info" title="No cards seen yet" hideCloseButton lowContrast />;
  }

  return (
    <Stack gap={5} style={{ paddingTop: "1rem" }}>
      <h3>Cards ({cards.length})</h3>
      {cards.map((c) => (
        <Tile key={c.card}>
          <Stack gap={3}>
            <strong style={{ fontFamily: "monospace" }}>{c.card}</strong>
            <div style={{ display: "flex", flexWrap: "wrap", gap: "0.25rem" }}>
              {(c.entries || []).length ? (
                c.entries.map((e) => (
                  <Tag key={`${e.table}:${e.id}`} type="cool-gray" size="sm">
                    {e.table} #{e.id} · {e.name ?? "—"}
                  </Tag>
                ))
              ) : (
                <span style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem" }}>
                  no profiles
                </span>
              )}
            </div>
          </Stack>
        </Tile>
      ))}
    </Stack>
  );
}

// ---------- Audit trail (cursor-paginated) ----------

const AUDIT_HEADERS = [
  { key: "created_at", header: "When" },
  { key: "actor", header: "Actor" },
  { key: "action", header: "Action" },
  { key: "target", header: "Target" },
  { key: "outcome", header: "Outcome" },
  { key: "request_id", header: "Request" },
];

const AUDIT_PAGE_SIZES = [25, 50, 100, 200];

function AuditPanel({ onLock }) {
  const [events, setEvents] = useState(null);
  const [error, setError] = useState(null);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [nextCursor, setNextCursor] = useState(null);
  const cursors = useRef({ 1: null }); // page -> cursor it was fetched with

  useEffect(() => {
    if (page > 1 && !(page in cursors.current)) {
      setPage(1);
      return;
    }
    setEvents(null);
    api
      .audit({ limit: pageSize, cursor: cursors.current[page] })
      .then((d) => {
        setEvents(d.events || []);
        setNextCursor(d.next_cursor ?? null);
        if (d.next_cursor) cursors.current[page + 1] = d.next_cursor;
        else delete cursors.current[page + 1];
      })
      .catch((err) => adminCatch(err, onLock, setError));
  }, [page, pageSize]); // eslint-disable-line react-hooks/exhaustive-deps

  const onPageChange = ({ page: nextPage, pageSize: nextSize }) => {
    if (nextSize !== pageSize) {
      cursors.current = { 1: null };
      setPageSize(nextSize);
      setPage(1);
    } else {
      setPage(nextPage);
    }
  };

  if (error) return <PanelError title="Could not load the audit trail" error={error} />;
  if (!events) return <PanelSkeleton />;

  const rows = events.map((e) => ({
    id: String(e.id),
    created_at: fmtTs(e.created_at),
    actor: e.actor ?? "—",
    action: (
      <Tag type="cool-gray" size="sm">
        {e.action}
      </Tag>
    ),
    target: <span style={{ fontFamily: "monospace" }}>{e.target ?? "—"}</span>,
    outcome:
      e.outcome === "ok" ? (
        <Tag type="green" size="sm">
          ok
        </Tag>
      ) : (
        <Tag type="red" size="sm">
          {e.outcome ?? "—"}
        </Tag>
      ),
    request_id: (
      <span style={{ fontFamily: "monospace", fontSize: "0.75rem" }}>{e.request_id ?? "—"}</span>
    ),
  }));

  return (
    <Stack gap={5} style={{ paddingTop: "1rem" }}>
      <h3>Audit trail</h3>
      <p style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem" }}>
        Administrative mutations, newest first.
      </p>
      {events.length ? (
        <DataTable rows={rows} headers={AUDIT_HEADERS}>
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
        <InlineNotification kind="info" title="No audit events yet" hideCloseButton lowContrast />
      )}
      <Pagination
        id="audit-pagination"
        page={page}
        pageSize={pageSize}
        pageSizes={AUDIT_PAGE_SIZES}
        pagesUnknown
        isLastPage={!nextCursor}
        itemsPerPageText="Events per page"
        backwardText="Previous page"
        forwardText="Next page"
        onChange={onPageChange}
      />
    </Stack>
  );
}

function summarize(doc) {
  const parts = [];
  for (const [key, value] of Object.entries(doc)) {
    if (key === "_id") continue;
    if (value === null || ["string", "number", "boolean"].includes(typeof value)) {
      parts.push(`${key}: ${JSON.stringify(value)}`);
    }
    if (parts.length >= 4) break;
  }
  return parts.join("  ·  ");
}

function capitalize(s) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

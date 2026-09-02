import { useEffect, useState } from "react";
import { Link, useParams } from "react-router";
import {
  TextInput,
  Button,
  Tile,
  Tag,
  Stack,
  Tabs,
  TabList,
  Tab,
  TabPanels,
  TabPanel,
  Toggle,
  Dropdown,
  NumberInput,
  TextArea,
  InlineNotification,
  SkeletonText,
  SkeletonPlaceholder,
  Grid,
  Column,
} from "@carbon/react";
import { api, getGames, gameForProfileTable } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { humanError, parseJsonObject } from "../util.js";
import { IIDX_FIELDS } from "../schema.js";

export default function Settings() {
  const { table, docId } = useParams();
  const authFailure = useAuthFailure();
  const [doc, setDoc] = useState(null);
  const [game, setGame] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [pin, setPin] = useState("");
  const [work, setWork] = useState({});
  const [versions, setVersions] = useState([]);
  const [activeIdx, setActiveIdx] = useState(0);
  const [jsonText, setJsonText] = useState("{}");
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    Promise.all([api.profile(table, docId), getGames()])
      .then(([docData, games]) => {
        setDoc(docData);
        setGame(gameForProfileTable(games, table));
        setPin(String(docData.pin ?? ""));
        const clone = structuredClone(docData.version || {});
        setWork(clone);
        const vers = Object.keys(clone).sort((a, b) => Number(a) - Number(b));
        setVersions(vers);
        const idx = Math.max(0, vers.length - 1);
        setActiveIdx(idx);
        if (vers[idx] != null) setJsonText(JSON.stringify(clone[vers[idx]] ?? {}, null, 2));
      })
      .catch((err) => {
        if (!authFailure(err)) setLoadError(humanError(err));
      });
  }, [table, docId]); // eslint-disable-line react-hooks/exhaustive-deps

  if (loadError) {
    return (
      <InlineNotification
        kind="error"
        title="Could not load profile"
        subtitle={loadError}
        hideCloseButton
        lowContrast
      />
    );
  }

  if (!doc) {
    return (
      <Stack gap={6} style={{ marginTop: "1rem" }}>
        <SkeletonText heading width="40%" />
        <SkeletonPlaceholder style={{ width: "100%", height: "10rem" }} />
        <SkeletonPlaceholder style={{ width: "100%", height: "16rem" }} />
      </Stack>
    );
  }

  const activeVer = versions[activeIdx];
  const settings = activeVer != null ? work[activeVer] : null;
  const isIIDX = game?.key === "iidx";
  const icon = game ? gameIcon(game.key) : null;
  const jsonStatus = parseJsonObject(jsonText);

  const setField = (key, value) => {
    const next = { ...work, [activeVer]: { ...work[activeVer], [key]: value } };
    setWork(next);
    setJsonText(JSON.stringify(next[activeVer], null, 2));
  };

  const selectVersion = ({ selectedIndex }) => {
    setActiveIdx(selectedIndex);
    const ver = versions[selectedIndex];
    setJsonText(JSON.stringify(work[ver] ?? {}, null, 2));
  };

  const prettyPrint = () => {
    if (jsonStatus.ok) setJsonText(JSON.stringify(jsonStatus.value, null, 2));
  };

  const save = async () => {
    setNotice(null);
    if (pin && !/^\d{4}$/.test(pin)) {
      setNotice({ kind: "error", text: "PIN must be exactly 4 digits." });
      return;
    }
    let workToSave = work;
    if (activeVer != null && work[activeVer] != null && typeof work[activeVer] === "object") {
      const serialized = JSON.stringify(work[activeVer], null, 2);
      if (jsonText.trim() !== serialized.trim()) {
        // the user typed into the advanced editor — adopt it
        if (!jsonStatus.ok) {
          setNotice({ kind: "error", text: `Fix the advanced JSON first — it does not parse (${jsonStatus.error}).` });
          return;
        }
        workToSave = { ...work, [activeVer]: jsonStatus.value };
        setWork(workToSave);
      }
    }

    const patch = {};
    if (pin !== String(doc.pin ?? "")) patch.pin = pin; // always the 4-digit string
    if (JSON.stringify(workToSave) !== JSON.stringify(doc.version || {})) {
      patch.version = workToSave; // server merges per version key — send the whole map
    }

    if (!Object.keys(patch).length) {
      setNotice({ kind: "info", text: "No changes to save." });
      return;
    }

    setBusy(true);
    try {
      const updated = await api.patchProfile(table, docId, patch);
      const nextDoc = { ...doc, ...updated };
      setDoc(nextDoc);
      setWork(structuredClone(nextDoc.version || {}));
      setNotice({ kind: "success", text: "Saved." });
    } catch (err) {
      if (!authFailure(err)) setNotice({ kind: "error", text: `Save failed: ${humanError(err)}` });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Stack gap={7} style={{ marginTop: "1rem" }}>
      <div>
        <p>
          <Link to="/">← dashboard</Link>
          <span style={{ color: "var(--cds-text-secondary)", marginLeft: "1rem" }}>
            {game?.name ?? table} · profile #{docId}
          </span>
        </p>
        <h1 style={{ display: "flex", alignItems: "center", gap: "0.75rem" }}>
          Profile settings
          {icon && <img src={icon} alt="" width={36} height={36} />}
          {game && (
            <Tag type="magenta" size="sm">
              {game.key}
            </Tag>
          )}
        </h1>
      </div>

      <Tile>
        <Stack gap={4}>
          <h3>Quick edit</h3>
          <Grid narrow>
            <Column sm={4} md={4} lg={6}>
              <TextInput
                id="profile-name"
                labelText="Player name"
                value={profileName(work) ?? "—"}
                readOnly
                helperText="Set by the game — not editable here."
              />
            </Column>
            <Column sm={4} md={4} lg={6}>
              <TextInput
                id="profile-pin"
                labelText="PIN"
                value={pin}
                maxLength={4}
                inputMode="numeric"
                invalid={Boolean(pin) && !/^\d{4}$/.test(pin)}
                invalidText="PIN must be exactly 4 digits"
                onChange={(e) => setPin(e.target.value)}
                style={{ fontFamily: "monospace" }}
              />
            </Column>
          </Grid>
          <p style={{ color: "var(--cds-text-secondary)", fontSize: "0.875rem", fontFamily: "monospace" }}>
            card {doc.card}
          </p>
        </Stack>
      </Tile>

      {versions.length ? (
        <Tile>
          <Stack gap={4}>
            <h3>Per-version settings</h3>
            <Tabs selectedIndex={activeIdx} onChange={selectVersion}>
              <TabList aria-label="Game versions">
                {versions.map((v) => (
                  <Tab key={v}>ver {v}</Tab>
                ))}
              </TabList>
              <TabPanels>
                {versions.map((v) => (
                  <TabPanel key={v}>
                    {v === activeVer &&
                      (settings != null && typeof settings === "object" ? (
                        <Stack gap={5} style={{ paddingTop: "1rem" }}>
                          {isIIDX && (
                            <Grid narrow>
                              {IIDX_FIELDS.filter((f) => f.key in settings).map((f) => (
                                <Column key={f.key} sm={4} md={4} lg={5}>
                                  <IidxField def={f} value={settings[f.key]} onChange={setField} />
                                </Column>
                              ))}
                            </Grid>
                          )}
                          {!isIIDX && (
                            <p style={{ color: "var(--cds-text-secondary)" }}>
                              No curated form for this game — use the JSON editor below.
                            </p>
                          )}
                          <div>
                            <div style={{ display: "flex", justifyContent: "flex-end", marginBottom: "0.25rem" }}>
                              <Button kind="ghost" size="sm" onClick={prettyPrint}>
                                Pretty-print
                              </Button>
                            </div>
                            <TextArea
                              id="version-json"
                              labelText={`Advanced profile JSON (version ${v})`}
                              rows={14}
                              value={jsonText}
                              onChange={(e) => setJsonText(e.target.value)}
                              invalid={!jsonStatus.ok}
                              invalidText={`invalid JSON: ${jsonStatus.error}`}
                              helperText={jsonStatus.ok ? "valid JSON" : undefined}
                              style={{ fontFamily: "monospace" }}
                            />
                          </div>
                        </Stack>
                      ) : (
                        <p style={{ color: "var(--cds-text-secondary)", paddingTop: "1rem" }}>
                          No settings for this version.
                        </p>
                      ))}
                  </TabPanel>
                ))}
              </TabPanels>
            </Tabs>
          </Stack>
        </Tile>
      ) : (
        <Tile>
          <p style={{ color: "var(--cds-text-secondary)" }}>This profile has no version data.</p>
        </Tile>
      )}

      <div>
        <Button onClick={save} disabled={busy}>
          {busy ? "Saving…" : "Save changes"}
        </Button>
      </div>

      {notice && (
        <InlineNotification
          kind={notice.kind === "info" ? "info" : notice.kind}
          title={notice.kind === "success" ? "Settings" : notice.kind === "info" ? "Settings" : "Error"}
          subtitle={notice.text}
          hideCloseButton
          lowContrast
        />
      )}
    </Stack>
  );
}

function profileName(versions) {
  const entries = Object.entries(versions || {})
    .filter(([k, v]) => v && typeof v === "object")
    .sort(([a], [b]) => Number(a) - Number(b));
  const latest = entries[entries.length - 1];
  return latest ? (latest[1].name ?? latest[1].djname ?? null) : null;
}

function IidxField({ def, value, onChange }) {
  const [numberInvalid, setNumberInvalid] = useState(false);
  if (def.type === "bool") {
    return (
      <Toggle
        id={`iidx-${def.key}`}
        labelText={def.label}
        toggled={Boolean(value)}
        onToggle={(checked) => onChange(def.key, checked)}
      />
    );
  }
  if (def.type === "select") {
    const items = Object.entries(def.options).map(([v, label]) => ({ value: Number(v), label }));
    return (
      <Dropdown
        id={`iidx-${def.key}`}
        titleText={def.label}
        label={def.label}
        items={items}
        itemToString={(item) => (item ? item.label : "")}
        selectedItem={items.find((i) => i.value === Number(value)) ?? items[0]}
        onChange={({ selectedItem }) => selectedItem && onChange(def.key, selectedItem.value)}
      />
    );
  }
  return (
    <NumberInput
      id={`iidx-${def.key}`}
      label={def.label}
      value={Number(value ?? 0)}
      step={def.step === "any" ? 0.1 : 1}
      invalid={numberInvalid}
      invalidText="Enter a number"
      onChange={(e, { value: v }) => {
        const n = Number(v);
        if (v !== "" && Number.isFinite(n)) {
          setNumberInvalid(false);
          onChange(def.key, n);
        } else {
          setNumberInvalid(true);
        }
      }}
    />
  );
}

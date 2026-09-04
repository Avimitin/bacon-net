import { useEffect, useState } from "react";
import { Link, useParams } from "react-router";
import {
  TextInput,
  Button,
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
  Grid,
  Column,
} from "@carbon/react";
import { ArrowLeft, Save } from "@carbon/icons-react";
import { api, getGames, gameForProfileTable } from "../api.js";
import { useAuthFailure } from "../session.jsx";
import { gameIcon } from "../gameIcons.js";
import { humanError, parseJsonObject } from "../util.js";
import { IIDX_FIELDS } from "../schema.js";
import { PageState, SectionHeading, SignalHero } from "../components/SignalLayout.jsx";

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
    return <PageState kind="error" title="Could not load profile" description={loadError} />;
  }

  if (!doc) {
    return <PageState title="Loading profile controls…" />;
  }

  const activeVer = versions[activeIdx];
  const settings = activeVer != null ? work[activeVer] : null;
  const isIIDX = game?.key === "iidx";
  const icon = game ? gameIcon(game.key) : null;
  const jsonStatus = parseJsonObject(jsonText);
  const activeSerialized =
    activeVer != null && work[activeVer] != null
      ? JSON.stringify(work[activeVer], null, 2).trim()
      : "{}";
  const hasChanges =
    pin !== String(doc.pin ?? "") ||
    JSON.stringify(work) !== JSON.stringify(doc.version || {}) ||
    jsonText.trim() !== activeSerialized;

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
    <div className="signal-page settings-page">
      <SignalHero
        index="P.01"
        eyebrow="Profile controls"
        title="Tune your"
        accent="player profile."
        description={`Adjust account-facing controls for ${game?.name ?? table}. Game-owned identity fields remain read-only.`}
        tone="red"
        action={
          <Button as={Link} to="/" kind="tertiary" renderIcon={ArrowLeft}>
            Dashboard
          </Button>
        }
        metrics={[
          { label: "Profile", value: `#${docId}` },
          { label: "Versions", value: String(versions.length).padStart(2, "0") },
        ]}
        visualLabel="Profile / version / preferences"
      />

      <div className="profile-identity-strip">
        <div className="profile-identity-strip__icon">
          {icon ? <img src={icon} alt="" /> : <span>{(game?.key ?? table).slice(0, 2)}</span>}
        </div>
        <div>
          <p>Connected game</p>
          <strong>{game?.name ?? table}</strong>
        </div>
        <dl>
          <div>
            <dt>Profile</dt>
            <dd>#{docId}</dd>
          </div>
          <div>
            <dt>Card</dt>
            <dd>{doc.card}</dd>
          </div>
        </dl>
      </div>

      <div className="signal-page__body settings-layout">
        <section className="settings-panel" aria-label="Quick edit">
          <SectionHeading
            index="P.01.A"
            eyebrow="Account-facing"
            title="Quick edit"
            description="PIN is the only identity control that can be changed outside the game."
          />
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
                className="signal-mono-input"
              />
            </Column>
          </Grid>
        </section>

        <section className="settings-panel settings-panel--versions" aria-label="Per-version settings">
          <SectionHeading
            index="P.01.B"
            eyebrow="Game-facing"
            title="Per-version settings"
            description="Each release keeps its own preferences. Choose a version before editing."
          />
          {versions.length ? (
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
                        <Stack gap={5} className="settings-version-form">
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
                            <p className="signal-form-note">
                              No curated form for this game — use the JSON editor below.
                            </p>
                          )}
                          <div className="settings-json-editor">
                            <div className="settings-json-editor__action">
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
                              className="signal-json-input"
                            />
                          </div>
                        </Stack>
                      ) : (
                        <p className="signal-form-note settings-version-form">
                          No settings for this version.
                        </p>
                      ))}
                  </TabPanel>
                ))}
              </TabPanels>
            </Tabs>
          ) : (
            <div className="signal-empty-plane signal-empty-plane--compact">
              <h3>No version data</h3>
              <p>This profile has not reported any per-version settings.</p>
            </div>
          )}
        </section>

        <div className="settings-save-bar">
          <div>
            <span className={`settings-save-bar__state${hasChanges ? " is-dirty" : ""}`} aria-hidden="true" />
            <p>{hasChanges ? "Unsaved changes" : "Profile synchronized"}</p>
          </div>
          <Button onClick={save} disabled={busy} renderIcon={Save}>
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
      </div>
    </div>
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

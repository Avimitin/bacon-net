// Per-game score column definitions and curated IIDX settings fields.
// Game/table identity itself comes from GET /account/api/games; this file only
// holds presentation metadata the server cannot know.

export const SCORE_COLUMNS = {
  iidx: [
    { key: "music_id", label: "Song", kind: "song" },
    { key: "chart_id", label: "Chart", kind: "badge" },
    { key: "ex_score", label: "EX Score", kind: "num" },
    { key: "pgreat_num", label: "PGREAT", kind: "num" },
    { key: "great_num", label: "GREAT", kind: "num" },
    { key: "clear_flg", label: "Clear", kind: "badge" },
    { key: "miss_count", label: "Miss", kind: "num" },
    { key: "play_style", label: "Style", kind: "badge" },
    { key: "timestamp", label: "Played", kind: "ts" },
  ],
  ddr: [
    { key: "mcode", label: "Song", kind: "song" },
    { key: "difficulty", label: "Diff", kind: "badge" },
    { key: "score", label: "Score", kind: "num" },
    { key: "exscore", label: "EX", kind: "num" },
    { key: "lamp", label: "Lamp", kind: "badge" },
    { key: "rank", label: "Rank", kind: "badge" },
    { key: "maxcombo", label: "Combo", kind: "num" },
    { key: "timestamp", label: "Played", kind: "ts" },
  ],
  sdvx: [
    { key: "music_id", label: "Song", kind: "song" },
    { key: "music_type", label: "Type", kind: "badge" },
    { key: "score", label: "Score", kind: "num" },
    { key: "exscore", label: "EX", kind: "num" },
    { key: "clear_type", label: "Clear", kind: "badge" },
    { key: "score_grade", label: "Grade", kind: "badge" },
    { key: "max_chain", label: "Chain", kind: "num" },
    { key: "timestamp", label: "Played", kind: "ts" },
  ],
  gitadora: [
    { key: "musicid", label: "Song", kind: "song" },
    { key: "seq", label: "Chart", kind: "badge" },
    { key: "perc", label: "Percent", kind: "pct" },
    { key: "skill", label: "Skill", kind: "num" },
    { key: "rank", label: "Rank", kind: "badge" },
    { key: "combo", label: "Combo", kind: "num" },
    { key: "clear", label: "Clear", kind: "bool" },
    { key: "fullcombo", label: "FC", kind: "bool" },
    { key: "timestamp", label: "Played", kind: "ts" },
  ],
  drs: [
    { key: "music_id", label: "Song", kind: "song" },
    { key: "music_type", label: "Type", kind: "badge" },
    { key: "score", label: "Score", kind: "num" },
    { key: "rank", label: "Rank", kind: "badge" },
    { key: "combo", label: "Combo", kind: "num" },
    { key: "timestamp", label: "Played", kind: "ts" },
  ],
  nostalgia: [
    { key: "music_index", label: "Song", kind: "song" },
    { key: "sheet_type", label: "Sheet", kind: "badge" },
    { key: "score", label: "Score", kind: "num" },
    { key: "grade", label: "Grade", kind: "badge" },
    { key: "combo", label: "Combo", kind: "num" },
    { key: "clear_flag", label: "Clear", kind: "badge" },
    { key: "timestamp", label: "Played", kind: "ts" },
  ],
};

export function scoreColumns(gameKey, sampleRow) {
  const known = SCORE_COLUMNS[gameKey];
  if (known) return known;
  if (!sampleRow) return [];
  return Object.keys(sampleRow)
    .filter((k) => k !== "_id" && k !== "card")
    .map((k) => ({ key: k, label: k, kind: k === "timestamp" ? "ts" : "text" }));
}

// Curated IIDX per-version settings. key matches the field name inside
// profile.version["<ver>"]. type: bool (toggle), number (float ok), select.
export const IIDX_FIELDS = [
  { key: "mode", label: "Play mode", type: "select", options: { 0: "SP", 1: "DP" } },
  { key: "pmode", label: "Side", type: "select", options: { 0: "P1", 1: "P2" } },
  { key: "rtype", label: "Frame type", type: "select", options: { 0: "frame", 1: "turntable side" } },
  { key: "turntable", label: "Turntable", type: "bool" },
  { key: "s_auto_scrach", label: "SP auto-scratch", type: "bool" },
  { key: "d_auto_scrach", label: "DP auto-scratch", type: "bool" },
  { key: "s_disp_judge", label: "SP judge display", type: "select", options: { 0: "off", 1: "on" } },
  { key: "d_disp_judge", label: "DP judge display", type: "select", options: { 0: "off", 1: "on" } },
  { key: "s_hispeed", label: "SP hi-speed", type: "number", step: "any" },
  { key: "d_hispeed", label: "DP hi-speed", type: "number", step: "any" },
  { key: "lift", label: "Lift", type: "number" },
  { key: "s_notes", label: "SP notes", type: "number", step: "any" },
  { key: "d_notes", label: "DP notes", type: "number", step: "any" },
  { key: "s_timing", label: "SP timing", type: "number", step: "any" },
  { key: "d_timing", label: "DP timing", type: "number", step: "any" },
  { key: "s_gno", label: "SP gauge", type: "number" },
  { key: "d_gno", label: "DP gauge", type: "number" },
  { key: "judge_pos", label: "Judge position", type: "number" },
  { key: "lightning_setting_headphone_vol", label: "Headphone volume", type: "number" },
  { key: "lightning_setting_brightness_bg", label: "Background brightness", type: "number" },
  { key: "lightning_setting_assistant_chara", label: "Assistant character", type: "number" },
];

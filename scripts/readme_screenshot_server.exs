alias BaconNet.Accounts
alias BaconNet.{Audit, DB, Repo, Tenancy}

import Ecto.Changeset, only: [change: 2]

# Rebuild and serve the isolated synthetic dataset used by the README gallery.
# This script never touches the normal dev/test databases and binds its HTTP
# listener to loopback only. Stop it with Ctrl-C after capturing the images.
root = Path.expand("..", __DIR__)
http_port = System.get_env("BACON_SCREENSHOT_PORT", "8000") |> String.to_integer()
database_port = System.get_env("BACON_SCREENSHOT_DB_PORT", "55434") |> String.to_integer()

database_dir =
  System.get_env("BACON_SCREENSHOT_DB_DIR", "/tmp/bacon-net-pg-readme-screenshots")

webui_dir = Path.join(root, "frontend/dist")

unless File.exists?(Path.join(webui_dir, "index.html")) do
  raise "frontend bundle not found; run `npm --prefix frontend run build` first"
end

Logger.configure(level: :warning)

Application.put_env(:bacon_net, BaconNet.Repo,
  local_cluster: true,
  env: :readme_screenshots,
  port: database_port,
  database: "bacon_net_readme_screenshots",
  data_dir: database_dir,
  pool_size: 5
)

Application.put_env(:bacon_net, :port, http_port)
Application.put_env(:bacon_net, :public_url, "http://127.0.0.1:#{http_port}")
Application.put_env(:bacon_net, :admin_token, "readme-demo-admin")
Application.put_env(:bacon_net, :webui_dir, webui_dir)
Application.put_env(:bacon_net, :verbose_log, false)
Application.put_env(:bacon_net, :announce_boot, false)
Application.put_env(:bacon_net, :start_server, false)
Application.put_env(:bacon_net, :migrate_on_start, true)

{:ok, _} = Application.ensure_all_started(:bacon_net)

Ecto.Adapters.SQL.query!(
  Repo,
  """
  TRUNCATE TABLE
    audit_events, wallet_entries, wallets, outbox_events, idempotency_keys,
    score_stats, best_scores, play_attempts, cabinets, shops, networks,
    account_cards, account_sessions, accounts, documents
  RESTART IDENTITY CASCADE
  """,
  []
)

fixture_time = ~U[2026-09-03 03:30:00.000000Z]
fixture_epoch = DateTime.to_unix(fixture_time)

{:ok, account, _token, _expires_at} =
  Accounts.register("neonkite", "readme-demo-only", display_name: "Neon Kite")

account =
  account
  |> change(
    admin: true,
    inserted_at: DateTime.add(fixture_time, -102 * 86_400, :second),
    updated_at: fixture_time
  )
  |> Repo.update!()

{:ok, _} = Accounts.bind_card(account, "E0040123456789AB", "1234-5678-9012-3456")
{:ok, _} = Accounts.bind_card(account, "E0040FEDCBA98765", "9876-5432-1098-7654")

insert_all = fn table, docs -> Enum.each(docs, &DB.insert(table, &1)) end

iidx_settings = %{
  "djname" => "NEONKITE",
  "mode" => 0,
  "pmode" => 0,
  "rtype" => 0,
  "turntable" => true,
  "s_auto_scrach" => false,
  "d_auto_scrach" => false,
  "s_disp_judge" => 1,
  "d_disp_judge" => 1,
  "s_hispeed" => 3.25,
  "d_hispeed" => 2.75,
  "lift" => 220,
  "s_notes" => 9.3,
  "d_notes" => 8.1,
  "s_timing" => 1,
  "d_timing" => 0,
  "s_gno" => 2,
  "d_gno" => 1,
  "judge_pos" => 0,
  "lightning_setting_headphone_vol" => 12,
  "lightning_setting_brightness_bg" => 7,
  "lightning_setting_assistant_chara" => 3
}

insert_all.("iidx_profile", [
  %{
    "card" => "E0040123456789AB",
    "iidx_id" => 40_001_234,
    "pin" => "2468",
    "version" => %{
      "31" => Map.put(iidx_settings, "djname", "NEONKITE"),
      "32" => Map.merge(iidx_settings, %{"s_hispeed" => 3.0, "lift" => 205}),
      "33" => iidx_settings
    }
  },
  %{
    "card" => "E004000000000101",
    "iidx_id" => 40_001_235,
    "pin" => "1111",
    "version" => %{"33" => %{"djname" => "BYTEBLOOM"}}
  },
  %{
    "card" => "E004000000000102",
    "iidx_id" => 40_001_236,
    "pin" => "2222",
    "version" => %{"33" => %{"djname" => "LUNAARC"}}
  },
  %{
    "card" => "E004000000000103",
    "iidx_id" => 40_001_237,
    "pin" => "3333",
    "version" => %{"33" => %{"djname" => "ECHOSTEP"}}
  },
  %{
    "card" => "E004000000000104",
    "iidx_id" => 40_001_238,
    "pin" => "4444",
    "version" => %{"33" => %{"djname" => "PIXELWAVE"}}
  },
  %{
    "card" => "E004000000000105",
    "iidx_id" => 40_001_239,
    "pin" => "5555",
    "version" => %{"33" => %{"djname" => "MOONBYTE"}}
  }
])

insert_all.("ddr_profile", [
  %{
    "card" => "E0040123456789AB",
    "ddr_id" => 51_004_210,
    "pin" => "2468",
    "version" => %{
      "20" => %{"name" => "NEONKITE"},
      "21" => %{"name" => "NEONKITE"},
      "22" => %{"name" => "NEONKITE"}
    }
  }
])

insert_all.("sdvx_profile", [
  %{
    "card" => "E0040FEDCBA98765",
    "sdvx_id" => 61_220_314,
    "pin" => "1357",
    "version" => %{"6" => %{"name" => "NEONKITE"}, "7" => %{"name" => "NEONKITE"}}
  }
])

insert_all.("gitadora_profile", [
  %{
    "card" => "E0040FEDCBA98765",
    "gitadora_id" => 71_300_082,
    "pin" => "1357",
    "version" => %{
      "8" => %{"name" => "NEONKITE"},
      "9" => %{"name" => "NEONKITE"},
      "10" => %{"name" => "NEONKITE"}
    }
  }
])

now = fixture_epoch

iidx_history = [
  {1207, 3, 2148, 997, 154, 2, 18},
  {1045, 2, 1894, 881, 132, 3, 23},
  {2312, 3, 2321, 1080, 161, 4, 9},
  {1729, 1, 1670, 778, 114, 3, 31},
  {3114, 4, 2488, 1165, 158, 5, 5},
  {2650, 3, 2206, 1030, 146, 4, 14},
  {908, 2, 1762, 820, 122, 3, 27},
  {3401, 3, 2350, 1098, 154, 4, 11},
  {1207, 3, 2175, 1012, 151, 3, 15},
  {1986, 2, 2014, 941, 132, 4, 20},
  {2844, 3, 2260, 1055, 150, 4, 13},
  {1502, 1, 1588, 741, 106, 3, 38}
]

iidx_history
|> Enum.with_index()
|> Enum.map(fn {{song, chart, score, pgreat, great, clear, miss}, index} ->
  %{
    "iidx_id" => 40_001_234,
    "music_id" => song,
    "chart_id" => chart,
    "ex_score" => score,
    "pgreat_num" => pgreat,
    "great_num" => great,
    "clear_flg" => clear,
    "miss_count" => miss,
    "play_style" => "SP",
    "timestamp" => now - index * 5_400
  }
end)
|> then(&insert_all.("iidx_scores", &1))

ranking_rows = [
  {40_001_235, 2396, 4, now - 1_800},
  {40_001_236, 2284, 7, now - 3_600},
  {40_001_234, 2175, 15, now - 7_200},
  {40_001_237, 2108, 22, now - 10_800},
  {40_001_238, 2026, 28, now - 14_400},
  {40_001_239, 1971, 34, now - 18_000}
]

ranking_rows
|> Enum.map(fn {player, score, miss, timestamp} ->
  %{
    "iidx_id" => player,
    "music_id" => 1207,
    "chart_id" => 3,
    "ex_score" => score,
    "pgreat_num" => div(score, 2),
    "great_num" => rem(score, 2),
    "clear_flg" => if(miss < 10, do: 4, else: 3),
    "miss_count" => miss,
    "play_style" => "SP",
    "timestamp" => timestamp
  }
end)
|> then(&insert_all.("iidx_scores_best", &1))

insert_all.("ddr_scores", [
  %{
    "ddr_id" => 51_004_210,
    "mcode" => 340,
    "difficulty" => 4,
    "score" => 986_420,
    "exscore" => 1842,
    "lamp" => "FC",
    "rank" => "AAA",
    "maxcombo" => 612,
    "timestamp" => now - 12_000
  }
])

insert_all.("sdvx_scores", [
  %{
    "sdvx_id" => 61_220_314,
    "music_id" => 1884,
    "music_type" => 3,
    "score" => 9_874_216,
    "exscore" => 4821,
    "clear_type" => "UC",
    "score_grade" => "S",
    "max_chain" => 1934,
    "timestamp" => now - 15_000
  }
])

insert_all.("drummania_scores", [
  %{
    "gitadora_id" => 71_300_082,
    "musicid" => 785,
    "seq" => 2,
    "perc" => 96.48,
    "skill" => 182.3,
    "rank" => "SS",
    "combo" => 744,
    "clear" => true,
    "fullcombo" => false,
    "timestamp" => now - 18_000
  }
])

insert_all.("webui_users", [
  %{
    "username" => "neonkite",
    "cards" => ["E0040123456789AB", "E0040FEDCBA98765"],
    "created_at" => now - 8_812_800,
    "banned" => false
  },
  %{
    "username" => "bytebloom",
    "cards" => ["E004000000000101"],
    "created_at" => now - 7_084_800,
    "banned" => false
  },
  %{
    "username" => "lunaarc",
    "cards" => ["E004000000000102"],
    "created_at" => now - 5_184_000,
    "banned" => false
  },
  %{
    "username" => "echostep",
    "cards" => ["E004000000000103"],
    "created_at" => now - 3_456_000,
    "banned" => false
  },
  %{
    "username" => "pixelwave",
    "cards" => ["E004000000000104"],
    "created_at" => now - 1_728_000,
    "banned" => true
  }
])

{:ok, _} = Tenancy.permit("PCBNEON001", "Neon Harbor · IIDX floor")
{:ok, _} = Tenancy.permit("PCBNEON002", "Neon Harbor · rhythm floor")
{:ok, _} = Tenancy.permit("PCBMETRO01", "Metro Pulse · east wing")
{:ok, _} = Tenancy.permit("PCBORBIT01", "Orbit Arcade · main hall")
:ok = Tenancy.register_pending("PCBNEW0001")
{:ok, _} = Tenancy.permit("PCBMAINT01", "Workshop cabinet")
:ok = Tenancy.revoke("PCBMAINT01")

Repo.update_all(BaconNet.Tenancy.Cabinet,
  set: [inserted_at: fixture_time, updated_at: fixture_time]
)

for attrs <- [
      %{
        actor: "demo-admin",
        action: "shop.permit",
        target: "PCBNEON001",
        outcome: "ok",
        request_id: "demo-req-001",
        metadata: %{"label" => "Neon Harbor · IIDX floor"}
      },
      %{
        actor: "demo-admin",
        action: "shop.permit",
        target: "PCBMETRO01",
        outcome: "ok",
        request_id: "demo-req-002",
        metadata: %{"label" => "Metro Pulse · east wing"}
      },
      %{
        actor: "demo-admin",
        action: "user.ban",
        target: "pixelwave",
        outcome: "ok",
        request_id: "demo-req-003",
        metadata: %{}
      },
      %{
        actor: "demo-admin",
        action: "doc.update",
        target: "iidx_profile:1",
        outcome: "ok",
        request_id: "demo-req-004",
        metadata: %{"table" => "iidx_profile"}
      }
    ] do
  {:ok, _} = Audit.record(attrs)
end

Repo.update_all(BaconNet.Audit.Event, set: [created_at: fixture_time])

{:ok, _server} =
  Bandit.start_link(plug: BaconNet.Router, ip: {127, 0, 0, 1}, port: http_port)

IO.puts("README_SCREENSHOT_SERVER_READY http://127.0.0.1:#{http_port}/webui/")
Process.sleep(:infinity)

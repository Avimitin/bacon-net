defmodule BaconNet.Telemetry do
  @moduledoc """
  Metrics definitions and a minimal in-process reporter.

  `metrics/0` holds the `Telemetry.Metrics` definitions; `init/1` attaches a
  handler per metric that folds every event into an ETS table of counters
  and gauges, and `render/0` dumps the table in Prometheus text exposition
  format (served at GET /metrics).

  Covered signals: HTTP request count/duration by route class, Ecto repo
  query count/duration, malformed-request decode rejects, and cabinet
  guard rejections by reason.
  """

  use GenServer

  import Telemetry.Metrics

  @table :bacon_net_metrics

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "All Telemetry.Metrics definitions tracked by this reporter."
  def metrics do
    [
      counter("bacon_net_http_requests_total",
        event_name: [:bacon_net, :http, :request],
        measurement: :count,
        tags: [:route_class, :status]
      ),
      sum("bacon_net_http_request_duration_ms_total",
        event_name: [:bacon_net, :http, :request],
        measurement: fn m -> System.convert_time_unit(m.duration, :native, :millisecond) end,
        tags: [:route_class]
      ),
      counter("bacon_net_repo_queries_total",
        event_name: [:bacon_net, :repo, :query],
        measurement: fn _ -> 1 end
      ),
      sum("bacon_net_repo_query_duration_ms_total",
        event_name: [:bacon_net, :repo, :query],
        measurement: fn m ->
          System.convert_time_unit(m[:total_time] || 0, :native, :millisecond)
        end
      ),
      counter("bacon_net_decode_rejected_total",
        event_name: [:bacon_net, :decode, :rejected],
        measurement: :count
      ),
      counter("bacon_net_cabinet_rejected_total",
        event_name: [:bacon_net, :cabinet, :rejected],
        measurement: :count,
        tags: [:reason]
      )
    ]
  end

  @doc "Render all counters/gauges in Prometheus text exposition format."
  def render do
    case :ets.whereis(@table) do
      :undefined ->
        ""

      _ ->
        @table
        |> :ets.tab2list()
        |> Enum.sort()
        |> Enum.map_join("\n", &render_row/1)
        |> Kernel.<>("\n")
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])

    for metric <- metrics() do
      id = {__MODULE__, metric.name}
      :telemetry.detach(id)
      :telemetry.attach(id, metric.event_name, &__MODULE__.handle_event/4, metric)
    end

    {:ok, %{}}
  end

  @doc false
  def handle_event(_event, measurements, metadata, metric) do
    value = measurement_value(metric.measurement, measurements)

    tags =
      metric.tags
      |> Enum.map(&{&1, Map.get(metadata, &1)})
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.sort()

    key = {prom_name(metric), tags}

    case type_of(metric) do
      :counter -> :ets.update_counter(@table, key, {3, value}, {key, :counter, 0})
      :gauge -> :ets.insert(@table, {key, :gauge, value})
    end

    :ok
  end

  ## Internals

  defp measurement_value(fun, measurements) when is_function(fun, 1), do: fun.(measurements)

  defp measurement_value(measurement, measurements) when is_atom(measurement),
    do: Map.get(measurements, measurement, 0)

  defp measurement_value(number, _) when is_number(number), do: number

  defp type_of(%Telemetry.Metrics.LastValue{}), do: :gauge
  defp type_of(_), do: :counter

  defp prom_name(metric) do
    metric.name |> Enum.join(".") |> String.replace(".", "_")
  end

  defp render_row({{name, tags}, _type, value}) do
    "#{name}#{render_tags(tags)} #{value}"
  end

  defp render_tags([]), do: ""

  defp render_tags(tags) do
    inner =
      tags
      |> Enum.map_join(",", fn {k, v} -> ~s(#{k}="#{escape(to_string(v))}") end)

    "{#{inner}}"
  end

  defp escape(s) do
    s |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
  end
end

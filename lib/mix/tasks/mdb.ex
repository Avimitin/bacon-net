defmodule Mix.Tasks.Mdb do
  @moduledoc """
  IIDX music_data.bin tool (utils/musicdata_tool.py CLI counterpart).

      mix mdb --input music_data.bin --output songs.json --extract
      mix mdb --input songs.json --output music_data.bin --create
      mix mdb --input old.bin --output new.bin --merge [--diff]
  """

  use Mix.Task

  alias BaconNet.MusicdataTool

  @shortdoc "Extract/create/merge IIDX music_data.bin files"

  @impl true
  def run(args) do
    {opts, _argv, _} =
      OptionParser.parse(args,
        strict: [input: :string, output: :string, extract: :boolean, create: :boolean,
                 merge: :boolean, diff: :boolean]
      )

    input = Keyword.get(opts, :input) || Mix.raise("--input is required")
    output = Keyword.get(opts, :output) || Mix.raise("--output is required")

    cond do
      opts[:extract] ->
        MusicdataTool.extract_file(input, output)

      opts[:create] ->
        MusicdataTool.create_file(input, output, nil)

      opts[:merge] ->
        MusicdataTool.merge_files(input, output, output, Keyword.get(opts, :diff, false))

      true ->
        Mix.raise("You must specify either --extract or --create or --merge")
    end
  end
end

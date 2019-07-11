defmodule Absinthe do
  @moduledoc """
  Documentation for Pngconverter.
  """

  alias Absinthe.CLI
  alias Absinthe.Files

  @doc """
  Absinthe

  ## Examples

      iex> Absinthe.main(args)
      []
  """
  def main(args) do
    opts = CLI.parse(args)
    IO.inspect(opts)
    files = Files.get_files(opts)
    IO.inspect(files)

    Files.parse_files(files)
  end
end
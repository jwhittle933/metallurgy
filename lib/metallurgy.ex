defmodule Metallurgy do
  @moduledoc """
  Documentation for Metallurgy

  Entry point for application
  """

  alias Metallurgy.CLI
  alias Metallurgy.Files

  @doc """
  Metallurgy Main
  """
  def main(args) do
    opts = CLI.parse(args)
    opts |> Files.get_file_list() |> IO.inspect()

    IO.inspect(opts)
  end
end

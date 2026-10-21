defmodule Refract.JSON.Objects do
  @moduledoc false

  alias Refract.JSON.Text

  @spec encode(Enumerable.t(), [String.t()] | nil) :: Enumerable.t()

  def encode(rows, nil) do
    Stream.transform(rows, nil, fn
      row, nil ->
        header = row |> Map.keys() |> Enum.sort()

        {[object(row, header)], header}

      row, header ->
        {[object(row, header)], header}
    end)
  end

  def encode(rows, header), do: Stream.map(rows, &object(&1, header))

  @spec validate_header([String.t()] | nil) :: :ok

  def validate_header(nil), do: :ok
  def validate_header(header), do: validate_header(header, header)

  defp validate_header([], _header), do: :ok

  defp validate_header([name | names], header) when is_binary(name),
    do: validate_header(names, header)

  defp validate_header(_names, header) do
    raise ArgumentError, "header must be a list of names, got: #{inspect(header)}"
  end

  defp object(row, header),
    do: Text.iodata({:object, Enum.map(header, &{&1, Map.fetch!(row, &1)})})
end

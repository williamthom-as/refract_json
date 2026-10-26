defmodule Refract.JSON.Objects do
  @moduledoc false

  alias Refract.JSON.Text
  alias Refract.Writer

  @spec encode(Enumerable.t(), [String.t()] | nil) :: Enumerable.t()

  def encode(rows, header) do
    rows
    |> Writer.cells(header)
    |> Stream.transform(nil, fn
      header, nil -> {[], header}
      values, header -> {[object(header, values)], header}
    end)
  end

  @spec validate_header([String.t()] | nil) :: :ok

  def validate_header(nil), do: :ok
  def validate_header(header), do: validate_header(header, header)

  defp validate_header([], _header), do: :ok

  defp validate_header([name | names], header) when is_binary(name),
    do: validate_header(names, header)

  defp validate_header(_names, header) do
    raise ArgumentError, "header must be a list of names, got: #{inspect(header)}"
  end

  defp object(header, values), do: Text.iodata({:object, Enum.zip(header, values)})
end

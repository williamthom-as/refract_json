defmodule Refract.JSON.Document do
  @moduledoc false

  alias Refract.JSON.Decode
  alias Refract.JSON.Records

  @type at :: [String.t()]

  @spec arrays(Decode.value()) :: [at()]

  def arrays(document) when is_list(document), do: [[]]
  def arrays({:object, pairs}), do: in_object(pairs, [])
  def arrays(_document), do: []

  @spec records(Decode.value(), at() | nil, String.t() | nil) ::
          {:ok, at(), [Decode.value()]}
          | {:error,
             :no_records
             | {:unknown_at, at()}
             | {:not_records, at()}
             | {:not_keyed, at()}
             | {:parse_error, String.t()}}

  def records(document, nil, nil), do: document |> arrays() |> first_records(document)
  def records(document, nil, keyed), do: records(document, [], keyed)
  def records(document, at, keyed), do: document |> fetch(at, at) |> as_records(at, keyed)

  defp first_records([], {:object, _pairs} = document), do: {:ok, [], [document]}
  defp first_records([], _document), do: {:error, :no_records}
  defp first_records([at | _arrays], document), do: records(document, at, nil)

  defp in_object(pairs, path),
    do: Enum.flat_map(pairs, fn {key, value} -> in_value(value, path ++ [key]) end)

  defp in_value([first | _values], path) when is_list(first), do: [path]
  defp in_value([{:object, _pairs} | _values], path), do: [path]
  defp in_value({:object, pairs}, path), do: in_object(pairs, path)
  defp in_value(_value, _path), do: []

  defp fetch(value, [], _at), do: {:ok, value}

  defp fetch({:object, pairs}, [key | keys], at),
    do: pairs |> List.keyfind(key, 0) |> fetch_next(keys, at)

  defp fetch(_value, _keys, at), do: {:error, {:unknown_at, at}}

  defp fetch_next({_key, value}, keys, at), do: fetch(value, keys, at)
  defp fetch_next(nil, _keys, at), do: {:error, {:unknown_at, at}}

  defp as_records({:ok, records}, at, nil) when is_list(records), do: {:ok, at, records}
  defp as_records({:ok, {:object, _pairs} = record}, at, nil), do: {:ok, at, [record]}
  defp as_records({:ok, _value}, at, nil), do: {:error, {:not_records, at}}

  defp as_records({:ok, {:object, pairs}}, at, keyed) do
    with {:ok, records} <- keyed_records(pairs, keyed), do: {:ok, at, records}
  end

  defp as_records({:ok, _value}, at, _keyed), do: {:error, {:not_keyed, at}}
  defp as_records({:error, _reason} = error, _at, _keyed), do: error

  defp keyed_records(pairs, keyed) do
    pairs
    |> Enum.map(fn {_key, value} -> Records.expect(value, :object) end)
    |> Enum.with_index(1)
    |> Enum.find(fn {check, _index} -> check != :ok end)
    |> keyed_records(pairs, keyed)
  end

  defp keyed_records(nil, pairs, keyed) do
    {:ok, Enum.map(pairs, fn {key, {:object, fields}} -> {:object, [{keyed, key} | fields]} end)}
  end

  defp keyed_records({{:error, detail}, index}, _pairs, _keyed),
    do: {:error, {:parse_error, "entry #{index} #{detail}"}}
end

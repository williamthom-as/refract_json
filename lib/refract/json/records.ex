defmodule Refract.JSON.Records do
  @moduledoc false

  alias Refract.JSON.Decode
  alias Refract.JSON.Text

  @type layout :: :objects | :arrays | :empty

  @type kind :: :object | :array

  @type pairs :: [{String.t(), term()}]

  @type unnest :: {[String.t()], %{String.t() => String.t()}} | nil

  @spec lines([Decode.value()], unnest()) ::
          {:ok, [[term()]]} | {:error, {:parse_error, String.t()}}

  def lines([], _unnest), do: {:ok, []}

  def lines([{:object, _pairs} | _elements] = elements, unnest), do: objects(elements, unnest)
  def lines(elements, {_path, _keep} = unnest), do: objects(elements, unnest)

  def lines([first | _elements] = elements, nil) when is_list(first),
    do: each(elements, :array, &{:ok, cells(&1)})

  def lines([first | _elements], nil), do: first |> start() |> at_element(1)

  @spec layout([Decode.value()]) :: layout()

  def layout([]), do: :empty
  def layout([{:object, _pairs} | _elements]), do: :objects
  def layout([_first | _elements]), do: :arrays

  @spec nested([Decode.value()]) :: [[String.t()]]

  def nested(records) do
    records
    |> Stream.flat_map(&nested_in(&1, []))
    |> Enum.uniq()
  end

  @spec start(Decode.value()) :: {:ok, kind()} | {:error, String.t()}

  def start({:object, _pairs}), do: {:ok, :object}
  def start(element) when is_list(element), do: {:ok, :array}
  def start(element), do: {:error, "is #{name(kind(element))}, expected an object or an array"}

  @spec expect(Decode.value(), kind()) :: :ok | {:error, String.t()}

  def expect(element, kind), do: same_kind(kind(element), kind)

  @spec rows(Decode.value(), unnest()) :: {:ok, [pairs()]} | {:error, String.t()}

  def rows(element, nil) do
    with {:ok, pairs} <- record(element), do: {:ok, [pairs]}
  end

  def rows(element, {path, keep}) do
    with {:ok, parent} <- record(element),
         {:ok, children} <- children(element, path, path) do
      kept = Enum.map(keep, fn {name, column} -> {name, kept_cell(parent, column)} end)

      children
      |> Enum.map(&child(&1, Enum.join(path, "."), kept))
      |> collect()
    end
  end

  @spec cells([Decode.value()]) :: [term()]

  def cells(values), do: Enum.map(values, &cell/1)

  @spec header(Enumerable.t()) :: [String.t()]

  def header(rows) do
    rows
    |> Stream.flat_map(&Enum.map(&1, fn {key, _cell} -> key end))
    |> Enum.uniq()
  end

  @spec line(pairs(), [String.t()]) :: [term()]

  def line(pairs, header) do
    cells = Map.new(pairs)

    Enum.map(header, &Map.get(cells, &1, ""))
  end

  @spec unnest([String.t()] | nil, %{String.t() => String.t()}) :: unnest()

  def unnest(nil, _keep), do: nil
  def unnest(path, keep), do: {path, keep}

  @spec validate_unnest([String.t()] | nil, %{String.t() => String.t()}) :: :ok

  def validate_unnest(nil, keep) when keep == %{}, do: :ok

  def validate_unnest(nil, _keep) do
    raise ArgumentError, "keep needs unnest, the child array its columns are carried into"
  end

  def validate_unnest([_key | _keys] = unnest, keep) do
    validate_path(unnest, unnest)
    validate_keep(keep)
  end

  def validate_unnest(unnest, _keep) do
    raise ArgumentError, "unnest must be a list of keys, got: #{inspect(unnest)}"
  end

  defp validate_path([], _unnest), do: :ok
  defp validate_path([key | keys], unnest) when is_binary(key), do: validate_path(keys, unnest)

  defp validate_path(_keys, unnest) do
    raise ArgumentError, "unnest must be a list of keys, got: #{inspect(unnest)}"
  end

  defp validate_keep(keep) when is_map(keep), do: validate_keep(Map.to_list(keep), keep)
  defp validate_keep(keep), do: validate_keep(keep, keep)

  defp validate_keep([], _keep), do: :ok

  defp validate_keep([{name, column} | pairs], keep) when is_binary(name) and is_binary(column),
    do: validate_keep(pairs, keep)

  defp validate_keep(_pairs, keep) do
    raise ArgumentError,
          "keep must be a map of child column names to parent columns, got: #{inspect(keep)}"
  end

  defp objects(elements, unnest) do
    with {:ok, rows} <- each(elements, :object, &rows(&1, unnest)) do
      {:ok, rows |> Enum.concat() |> table()}
    end
  end

  defp table(rows), do: rows |> header() |> table(rows)

  defp table([], _rows), do: []
  defp table(header, rows), do: [header | Enum.map(rows, &line(&1, header))]

  defp each(elements, kind, fun) do
    elements
    |> Enum.with_index(1)
    |> Enum.reduce_while([], &each_element(&1, &2, kind, fun))
    |> each_result()
  end

  defp each_element({element, index}, acc, kind, fun) do
    with :ok <- expect(element, kind),
         {:ok, value} <- fun.(element) do
      {:cont, [value | acc]}
    else
      error -> {:halt, at_element(error, index)}
    end
  end

  defp each_result({:error, _reason} = error), do: error
  defp each_result(values), do: {:ok, Enum.reverse(values)}

  defp at_element({:error, detail}, index),
    do: {:error, {:parse_error, "element #{index} #{detail}"}}

  defp same_kind(kind, kind), do: :ok
  defp same_kind(found, expected), do: {:error, "is #{name(found)}, expected #{name(expected)}"}

  defp record({:object, pairs}) do
    pairs
    |> flatten("")
    |> unique_keys()
  end

  defp unique_keys(pairs) do
    keys = Enum.map(pairs, &elem(&1, 0))

    unique_keys(pairs, keys -- Enum.uniq(keys))
  end

  defp unique_keys(pairs, []), do: {:ok, pairs}

  defp unique_keys(_pairs, [key | _keys]),
    do: {:error, "has the key #{inspect(key)} more than once"}

  defp children({:object, pairs}, [key | keys], path),
    do: pairs |> List.keyfind(key, 0) |> children_next(keys, path)

  defp children(values, [], _path) when is_list(values), do: {:ok, values}
  defp children(nil, _keys, _path), do: {:ok, []}

  defp children(value, _keys, path) do
    {:error, "has #{name(kind(value))} at #{Enum.join(path, ".")}, expected an array"}
  end

  defp children_next({_key, value}, keys, path), do: children(value, keys, path)
  defp children_next(nil, _keys, _path), do: {:ok, []}

  defp kept_cell(parent, column), do: parent |> List.keyfind(column, 0) |> kept_value()

  defp kept_value({_column, cell}), do: cell
  defp kept_value(nil), do: ""

  defp child({:object, _pairs} = child, _key, kept) do
    with {:ok, pairs} <- record(child), do: unique_keys(kept ++ pairs)
  end

  defp child(value, key, kept), do: unique_keys(kept ++ [{key, cell(value)}])

  defp collect(results) do
    results
    |> Enum.reduce_while([], fn
      {:ok, pairs}, rows -> {:cont, [pairs | rows]}
      {:error, _detail} = error, _rows -> {:halt, error}
    end)
    |> each_result()
  end

  defp nested_in({:object, pairs}, path), do: Enum.flat_map(pairs, &nested_pair(&1, path))
  defp nested_in(_element, _path), do: []

  defp nested_pair({key, [_first | _values]}, path), do: [path ++ [key]]
  defp nested_pair({key, {:object, _pairs} = object}, path), do: nested_in(object, path ++ [key])
  defp nested_pair(_pair, _path), do: []

  defp flatten(pairs, prefix),
    do: Enum.flat_map(pairs, fn {key, value} -> flatten_value(prefix <> key, value) end)

  defp flatten_value(key, {:object, []} = empty), do: [{key, cell(empty)}]
  defp flatten_value(key, {:object, pairs}), do: flatten(pairs, key <> ".")
  defp flatten_value(key, value), do: [{key, cell(value)}]

  defp cell(nil), do: ""
  defp cell({:object, _pairs} = value), do: Text.encode(value)
  defp cell(value) when is_list(value), do: Text.encode(value)
  defp cell(value), do: value

  defp kind({:object, _pairs}), do: :object
  defp kind(value) when is_list(value), do: :array
  defp kind(value) when is_binary(value), do: :string
  defp kind(value) when is_boolean(value), do: :boolean
  defp kind(nil), do: :null
  defp kind(_number), do: :number

  defp name(:object), do: "an object"
  defp name(:array), do: "an array"
  defp name(:string), do: "a string"
  defp name(:boolean), do: "a boolean"
  defp name(:null), do: "null"
  defp name(:number), do: "a number"
end

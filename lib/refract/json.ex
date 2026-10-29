defmodule Refract.JSON do
  @moduledoc """
  json reader and writer for refract. reads one array from a document: an array of objects (keys
  become the header in first seen order) or an array of arrays (lines as they are).
  nested objects flatten to dotted keys, arrays inside a record are their json text.
  cells come back as native values: text, integers, `Decimal` numbers, booleans, `""` for null or
  a missing key. a document that is an object holds its records under keys, `at:` picks them,
  default the first records array, else the object is one record (`at: []` reads a detail
  response holding an array as one record). `keyed: "id"` reads an object of objects as records,
  each key in that column. `unnest: ["lines"]` reads the child array inside each record as the
  table, `keep: %{"order_id" => "id"}` carries parent columns into every child row. writes an array with an object per line, keys in header
  order, `Decimal` as exact numbers, dates and times as iso text, nil as null.

      {:ok, rows} = Refract.JSON.stream("orders.json")
      {:ok, result} = Refract.JSON.classify("export.json", shapes, at: ["data", "items"])
      {:ok, rows} = Refract.JSON.stream({:string, products_body}, keyed: "product_id")
      {:ok, lines} = Refract.JSON.stream(page, at: ["data"], unnest: ["lines"], keep: %{"order_id" => "id"})
      {:ok, [{["customers"], {:ok, result}} | _arrays]} = Refract.JSON.classify_arrays("crm.json", shapes)
      :ok = Refract.JSON.write(rows, "out/orders.json", header: ["sku", "total"])
  """

  use Refract.Reader
  use Refract.Writer

  alias Refract.JSON.Decode
  alias Refract.JSON.Document
  alias Refract.JSON.Objects
  alias Refract.JSON.Records

  @type open_opt ::
          {:at, Document.at() | nil}
          | {:keyed, String.t() | nil}
          | {:unnest, [String.t()] | nil}
          | {:keep, %{String.t() => String.t()}}

  @type encode_opt :: {:header, [String.t()] | nil}

  @spec extension() :: String.t()

  @impl Refract.Writer
  def extension, do: "json"

  @spec extensions() :: [String.t()]

  @impl Refract.Reader
  def extensions, do: ["json"]

  @spec indexing() :: :records

  @impl Refract.Reader
  def indexing, do: :records

  @spec open(Refract.source(), [open_opt()]) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl Refract.Reader
  def open(source, opts) do
    opts = Keyword.validate!(opts, at: nil, keyed: nil, unnest: nil, keep: %{})
    at = Keyword.fetch!(opts, :at)
    keyed = Keyword.fetch!(opts, :keyed)
    unnest = Keyword.fetch!(opts, :unnest)
    keep = Keyword.fetch!(opts, :keep)

    validate_at(at)
    validate_keyed(keyed)
    Records.validate_unnest(unnest, keep)

    with {:ok, document} <- document(source),
         {:ok, _at, records} <- Document.records(document, at, keyed) do
      Records.lines(records, Records.unnest(unnest, keep))
    end
  end

  @spec facts(Refract.source(), [open_opt()]) :: {:ok, map()} | {:error, term()}

  @impl Refract.Reader
  def facts(source, opts) do
    opts = Keyword.validate!(opts, at: nil, keyed: nil, unnest: nil, keep: %{})
    at = Keyword.fetch!(opts, :at)
    keyed = Keyword.fetch!(opts, :keyed)
    unnest = Keyword.fetch!(opts, :unnest)
    keep = Keyword.fetch!(opts, :keep)

    validate_at(at)
    validate_keyed(keyed)
    Records.validate_unnest(unnest, keep)

    with {:ok, document} <- document(source),
         {:ok, at, records} <- Document.records(document, at, keyed),
         {:ok, _lines} <- Records.lines(records, Records.unnest(unnest, keep)) do
      {:ok,
       %{
         layout: Records.layout(records),
         at: at,
         arrays: Document.arrays(document),
         records: length(records),
         nested: Records.nested(records),
         unnest: unnest
       }}
    end
  end

  @spec arrays(Refract.source(), [{:at, Document.at() | nil}]) ::
          {:ok, [Document.at()]} | {:error, term()}

  def arrays(source, opts) do
    opts = Keyword.validate!(opts, at: nil)
    at = Keyword.fetch!(opts, :at)

    validate_at(at)

    with {:ok, document} <- document(source) do
      array_paths(document, at)
    end
  end

  @spec classify_arrays(Refract.source(), [Refract.Shape.t() | module()], keyword()) ::
          {:ok, [{Document.at(), {:ok, Refract.Classify.Result.t()} | {:error, term()}}]}
          | {:error, term()}

  def classify_arrays(source, shapes, opts \\ []) do
    {at_opts, classify_opts} = Keyword.split(opts, [:at])

    with {:ok, arrays} <- arrays(source, at_opts) do
      {:ok,
       Enum.map(arrays, &{&1, classify(source, shapes, Keyword.put(classify_opts, :at, &1))})}
    end
  end

  @spec encode(Enumerable.t(), [encode_opt()]) :: Enumerable.t()

  @impl Refract.Writer
  def encode(rows, opts) do
    opts = Keyword.validate!(opts, header: nil)
    header = Keyword.fetch!(opts, :header)

    Objects.validate_header(header)

    rows
    |> Objects.encode(header)
    |> Stream.transform(fn -> :first end, &element/2, &end_of_array/1, fn _position -> :ok end)
  end

  defp element(object, :first), do: {[["[\n", object]], :rest}
  defp element(object, :rest), do: {[[",\n", object]], :rest}

  defp end_of_array(:first), do: {["[]\n"], :first}
  defp end_of_array(:rest), do: {["\n]\n"], :rest}

  defp validate_at(nil), do: :ok
  defp validate_at(at), do: validate_at(at, at)

  defp validate_at([], _at), do: :ok
  defp validate_at([key | keys], at) when is_binary(key), do: validate_at(keys, at)

  defp validate_at(_keys, at) do
    raise ArgumentError, "at must be a list of keys, got: #{inspect(at)}"
  end

  defp validate_keyed(nil), do: :ok
  defp validate_keyed(keyed) when is_binary(keyed) and keyed != "", do: :ok

  defp validate_keyed(keyed) do
    raise ArgumentError, "keyed must be a column name, got: #{inspect(keyed)}"
  end

  defp array_paths(document, nil), do: {:ok, Document.arrays(document)}

  defp array_paths(document, at) do
    with {:ok, at, _records} <- Document.records(document, at, nil), do: {:ok, [at]}
  end

  defp document(source) do
    with {:ok, json} <- read(source), do: Decode.decode(json)
  end

  defp read(path) when is_binary(path), do: File.read(path)
  defp read({:string, json}), do: {:ok, json}
  defp read({:stream, chunks}), do: {:ok, chunks |> Enum.to_list() |> IO.iodata_to_binary()}
  defp read(source), do: {:error, {:unsupported_source, source}}
end

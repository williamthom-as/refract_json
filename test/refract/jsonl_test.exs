defmodule Refract.JSONLTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify.Result
  alias Refract.Errors.ParseError
  alias Refract.Grid
  alias Refract.JSONL
  alias Refract.Shape
  alias Refract.Table

  @fixtures Path.expand("../fixtures", __DIR__)

  defp fixture(name), do: Path.join(@fixtures, name)

  defp cells!(source, opts \\ []) do
    {:ok, raw} = JSONL.open(source, opts)

    Enum.to_list(raw)
  end

  defp invoice do
    Shape.new(
      name: "invoice",
      spec:
        Table.spec(
          header: [columns: %{"sku" => ["sku"], "item" => ["item"], "total" => ["total"]}],
          row: [match: %{"sku" => :integer, "total" => :number}]
        )
    )
  end

  describe "open/2 records" do
    test "a key first seen on the last line is kept, blank lines are skipped" do
      assert cells!(fixture("orders.jsonl")) == [
               ["sku", "item", "total", "discount"],
               [78_632_478, "apple", Decimal.new("3.5"), ""],
               [78_632_479, "pear", Decimal.new("4.25"), ""],
               [78_632_480, "fig", 2, Decimal.new("0.5")]
             ]
    end

    test "records flatten as in a json document" do
      jsonl = ~s({"id": 1, "address": {"city": "Perth"}, "tags": ["a"], "note": null}\n)

      assert cells!({:string, jsonl}) == [
               ["id", "address.city", "tags", "note"],
               [1, "Perth", ~s(["a"]), ""]
             ]
    end

    test "scan: reads keys from the first records only" do
      assert {:ok, raw} = JSONL.open(fixture("orders.jsonl"), scan: 2)
      assert Enum.take(raw, 1) == [["sku", "item", "total"]]
    end

    test "scan: a later record with a new key raises naming the key and line" do
      {:ok, raw} = JSONL.open(fixture("orders.jsonl"), scan: 2)

      error = assert_raise ParseError, fn -> Enum.to_list(raw) end
      assert error.message =~ "line 4"
      assert error.message =~ ~s("discount")
    end

    test "columns: gives the header outright" do
      columns = ["total", "sku", "item", "discount"]

      assert [^columns, first | _lines] = cells!(fixture("orders.jsonl"), columns: columns)
      assert first == [Decimal.new("3.5"), 78_632_478, "apple", ""]
    end

    test "columns: a record with a key outside them raises" do
      {:ok, raw} = JSONL.open(fixture("orders.jsonl"), columns: ["sku", "item", "total"])

      error = assert_raise ParseError, fn -> Enum.to_list(raw) end
      assert error.message =~ "line 4"
    end

    test "a flattened key that clashes with another key is a parse error naming the line" do
      jsonl = ~s({"id": 1}\n{"a.b": 1, "a": {"b": 2}}\n)

      assert {:error, {:parse_error, message}} = JSONL.open({:string, jsonl}, [])
      assert message =~ "line 2"
    end

    test "an array line among records is a parse error naming the line" do
      assert {:error, {:parse_error, message}} =
               JSONL.open({:string, ~s({"id": 1}\n["id"]\n)}, [])

      assert message =~ "line 2"
    end
  end

  describe "open/2 unnest" do
    defp orders do
      {:string,
       ~s({"id": 7, "lines": [{"sku": 1, "qty": 3}, {"sku": 2, "qty": 1}]}\n) <>
         ~s({"id": 8, "lines": []}\n) <>
         ~s({"id": 9, "lines": [{"sku": 1, "qty": 2, "note": "late"}]}\n)}
    end

    test "unnest: streams the child rows of every line, keep: carries parent columns" do
      assert cells!(orders(), unnest: ["lines"], keep: %{"order_id" => "id"}) == [
               ["order_id", "sku", "qty", "note"],
               [7, 1, 3, ""],
               [7, 2, 1, ""],
               [9, 1, 2, "late"]
             ]
    end

    test "scan: counts lines, not child rows" do
      {:ok, raw} = JSONL.open(orders(), unnest: ["lines"], keep: %{"order_id" => "id"}, scan: 2)

      error = assert_raise ParseError, fn -> Enum.to_list(raw) end
      assert error.message =~ "line 3"
      assert error.message =~ ~s("note")
    end

    test "no child rows at all gives no lines" do
      assert cells!({:string, ~s({"id": 1, "lines": []}\n)}, unnest: ["lines"]) == []
    end

    test "unnest: over array lines is a parse error" do
      assert {:error, {:parse_error, message}} =
               JSONL.open({:string, ~s(["a"]\n)}, unnest: ["lines"])

      assert message =~ "line 1 is an array, expected an object"
    end

    test "keep: needs unnest:" do
      assert_raise ArgumentError, ~r/keep/, fn ->
        JSONL.open(orders(), keep: %{"order_id" => "id"})
      end
    end
  end

  describe "open/2 arrays" do
    test "array lines are lines of cells as they are" do
      assert cells!(fixture("cells.jsonl")) == [
               ["Tax Invoice"],
               [],
               ["sku", "item", "total"],
               [78_632_478, "apple", Decimal.new("3.5")],
               [78_632_479, "pear", Decimal.new("4.25")]
             ]
    end

    test "an object line among arrays raises naming the line" do
      {:ok, raw} = JSONL.open({:string, ~s(["id"]\n{"id": 1}\n)}, [])

      error = assert_raise ParseError, fn -> Enum.to_list(raw) end
      assert error.message =~ "line 2"
    end
  end

  describe "open/2 bad lines" do
    test "a bad line is a parse error naming the line" do
      assert {:error, {:parse_error, message}} =
               JSONL.open({:string, ~s({"id": 1}\n{"id": \n{"id": 3}\n)}, [])

      assert message =~ "line 2"
    end

    test "a bad line past the scan raises while streaming" do
      {:ok, raw} = JSONL.open({:string, ~s({"id": 1}\n{"id": 2}\n{"id"\n)}, scan: 1)

      error = assert_raise ParseError, fn -> Enum.to_list(raw) end
      assert error.message =~ "line 3"
    end

    test "a line that is a plain value is a parse error" do
      assert {:error, {:parse_error, message}} = JSONL.open({:string, "3\n"}, [])
      assert message =~ "line 1"
    end

    test "two values on one line is a parse error" do
      assert {:error, {:parse_error, _message}} =
               JSONL.open({:string, ~s({"id": 1} {"id": 2}\n)}, [])
    end

    test "parse errors do not show the content" do
      assert {:error, {:parse_error, message}} =
               JSONL.open({:string, ~s({"secret": "hunter2"} x\n)}, [])

      refute message =~ "hunter2"
    end
  end

  describe "open/2 sources" do
    test "lines split across chunks" do
      chunks = fixture("orders.jsonl") |> File.read!() |> chunk(7)

      assert cells!({:stream, chunks}) == cells!(fixture("orders.jsonl"))
    end

    test "crlf line endings" do
      assert cells!({:string, ~s({"id": 1}\r\n{"id": 2}\r\n)}) == [["id"], [1], [2]]
    end

    test "a last line without a newline" do
      assert cells!({:string, ~s({"id": 1}\n{"id": 2})}) == [["id"], [1], [2]]
    end

    test "a byte order mark is skipped" do
      assert cells!({:string, "﻿" <> ~s({"id": 1}\n)}) == [["id"], [1]]
    end

    test "an empty source gives no lines" do
      assert cells!({:string, ""}) == []
      assert cells!({:string, "\n\n"}) == []
    end

    test "a missing file is an error straight away" do
      assert {:error, :enoent} = JSONL.open(fixture("missing.jsonl"), [])
    end

    test "an unsupported source is an error" do
      assert {:error, {:unsupported_source, :bills}} = JSONL.open(:bills, [])
    end
  end

  describe "open/2 options" do
    test "scan: must be a positive integer" do
      for scan <- [0, -1, :all, 1.5] do
        assert_raise ArgumentError, ~r/scan/, fn ->
          JSONL.open(fixture("orders.jsonl"), scan: scan)
        end
      end
    end

    test "columns: must be a list of names" do
      for columns <- ["sku", ["sku", 1], [:sku]] do
        assert_raise ArgumentError, ~r/columns/, fn ->
          JSONL.open(fixture("orders.jsonl"), columns: columns)
        end
      end
    end

    test "unknown options raise" do
      assert_raise ArgumentError, ~r/colour/, fn ->
        JSONL.open(fixture("orders.jsonl"), colour: :blue)
      end
    end
  end

  describe "facts/2" do
    test "the layout of the lines" do
      assert {:ok, %{layout: :objects}} = JSONL.facts(fixture("orders.jsonl"), [])
      assert {:ok, %{layout: :arrays}} = JSONL.facts(fixture("cells.jsonl"), [])
      assert {:ok, %{layout: :empty}} = JSONL.facts({:string, "\n"}, [])
    end
  end

  describe "reader functions" do
    test "stream gives row maps under the header" do
      assert {:ok, rows} = JSONL.stream(fixture("orders.jsonl"))

      assert [%{"sku" => 78_632_478, "discount" => ""} | _rows] = Enum.to_list(rows)
    end

    test "locate finds a table below a title in array lines" do
      assert {:ok, table} = JSONL.locate(fixture("cells.jsonl"), invoice().spec)
      assert table.header_row == 3
      assert length(Enum.to_list(table.rows)) == 2
    end

    test "classify matches records" do
      assert {:ok, %Result{verdict: :match} = result} =
               JSONL.classify(fixture("orders.jsonl"), [invoice()])

      assert %{layout: :objects} = result.file.format
    end

    test "classify gives a parse error for a bad line" do
      assert {:error, {:parse_error, _message}} =
               JSONL.classify({:string, ~s({"sku": 1}\nnope\n)}, [invoice()])
    end

    test "load builds a grid of the cells" do
      assert {:ok, grid} = JSONL.load(fixture("cells.jsonl"))
      assert Grid.cell(grid, "B4") == "apple"
    end

    test "extensions" do
      assert JSONL.extensions() == ["jsonl", "ndjson"]
    end
  end

  defp chunk(binary, size) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(size)
    |> Enum.map(&:binary.list_to_bin/1)
  end
end

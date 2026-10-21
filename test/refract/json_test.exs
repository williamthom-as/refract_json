defmodule Refract.JSONTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.Classify.Result
  alias Refract.Grid
  alias Refract.JSON
  alias Refract.Shape
  alias Refract.Table

  @fixtures Path.expand("../fixtures", __DIR__)

  defp fixture(name), do: Path.join(@fixtures, name)

  defp cells!(source, opts \\ []) do
    {:ok, raw} = JSON.open(source, opts)

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

  describe "open/2 layouts" do
    test "an array of objects gives a header line then a line per object" do
      assert cells!({:string, ~s([{"id": 1, "name": "alice"}, {"id": 2, "name": "bob"}])}) == [
               ["id", "name"],
               [1, "alice"],
               [2, "bob"]
             ]
    end

    test "the header holds every key in first seen order" do
      assert cells!(fixture("late_key.json")) == [
               ["sku", "item", "discount"],
               [78_632_478, "apple", ""],
               [78_632_479, "pear", ""],
               [78_632_480, "fig", Decimal.new("0.5")]
             ]
    end

    test "keys keep document order, not sorted order" do
      assert [["b", "a"] | _lines] = cells!({:string, ~s([{"b": 1, "a": 2}])})
    end

    test "an array of arrays gives its lines as they are" do
      assert cells!(fixture("offset.json")) == [
               ["Tax Invoice"],
               [],
               ["sku", "item", "total"],
               [78_632_478, "apple", Decimal.new("3.5")],
               [78_632_479, "pear", Decimal.new("4.25")]
             ]
    end

    test "an empty array gives no lines" do
      assert cells!({:string, "[]"}) == []
    end

    test "an element unlike the first is a parse error naming its position" do
      for json <- [~s([{"a": 1}, 2]), ~s([{"a": 1}, ["a"]]), ~s([["a"], {"a": 1}])] do
        assert {:error, {:parse_error, message}} = JSON.open({:string, json}, [])
        assert message =~ "element 2"
      end
    end

    test "an array of plain values is a parse error" do
      assert {:error, {:parse_error, message}} = JSON.open({:string, "[1, 2]"}, [])
      assert message =~ "element 1"
    end
  end

  describe "open/2 cells" do
    test "cells come back as native values" do
      assert cells!(fixture("types.json")) == [
               [
                 "name",
                 "amount",
                 "account",
                 "count",
                 "rate",
                 "flag",
                 "note",
                 "tags",
                 "address.city",
                 "address.geo.lat",
                 "extra"
               ],
               [
                 "alice",
                 Decimal.new("1.50"),
                 123_456_789_012,
                 3,
                 Decimal.new("2.5e3"),
                 true,
                 "",
                 ~s(["a","b"]),
                 "Perth",
                 Decimal.new("-31.95"),
                 ""
               ],
               [
                 "bob",
                 Decimal.new("-2.25"),
                 7,
                 0,
                 Decimal.new("0.1"),
                 false,
                 "",
                 "[]",
                 "Hobart",
                 "",
                 "{}"
               ]
             ]
    end

    test "numbers keep every digit" do
      assert [["amount"], [amount]] = cells!({:string, ~s([{"amount": 0.10000000000000000001}])})
      assert Decimal.equal?(amount, Decimal.new("0.10000000000000000001"))
    end

    test "objects inside an array keep their key order as text" do
      assert [["items"], [~s([{"b":1,"a":null}])]] =
               cells!({:string, ~s([{"items": [{"b": 1, "a": null}]}])})
    end

    test "nested values in an array line are their json text" do
      assert cells!({:string, ~s([["a", [1, 2], {"b": true}, null]])}) == [
               ["a", "[1,2]", ~s({"b":true}), ""]
             ]
    end

    test "a flattened key that clashes with another key is a parse error" do
      json = ~s([{"id": 1}, {"a.b": 1, "a": {"b": 2}}])

      assert {:error, {:parse_error, message}} = JSON.open({:string, json}, [])
      assert message =~ "element 2"
      assert message =~ ~s("a.b")
    end
  end

  describe "open/2 at" do
    test "an object reads its first records array by default" do
      assert [["sku", "item", "total"] | _lines] = cells!(fixture("envelope.json"))
    end

    test "at: picks a records array by its keys" do
      assert [["order", "customer", "total"] | _lines] =
               cells!(fixture("two_arrays.json"), at: ["orders"])
    end

    test "at: reaches into nested objects" do
      json = ~s({"result": {"count": 1, "items": [{"id": 1}]}})

      assert cells!({:string, json}, at: ["result", "items"]) == [["id"], [1]]
    end

    test "records nested in objects are found by default" do
      assert cells!({:string, ~s({"result": {"items": [{"id": 1}]}})}) == [["id"], [1]]
    end

    test "at: [] is the document itself" do
      assert cells!({:string, ~s([{"id": 1}])}, at: []) == [["id"], [1]]
    end

    test "at: naming an empty array gives no lines" do
      assert cells!(fixture("envelope.json"), at: ["errors"]) == []
    end

    test "an unknown at is an error" do
      for at <- [["missing"], ["data", "sku"], ["meta", "page", "x"]] do
        assert {:error, {:unknown_at, ^at}} = JSON.open(fixture("envelope.json"), at: at)
      end
    end

    test "at: naming a plain value is an error" do
      assert {:error, {:not_records, ["meta", "page"]}} =
               JSON.open(fixture("envelope.json"), at: ["meta", "page"])
    end

    test "a document that is a plain value has no records" do
      for json <- ["3", ~s("text"), "null"] do
        assert {:error, :no_records} = JSON.open({:string, json}, [])
      end
    end

    test "at: that is not a list of keys raises" do
      for at <- ["data", [:data], ["data", 1]] do
        assert_raise ArgumentError, ~r/at/, fn -> JSON.open(fixture("envelope.json"), at: at) end
      end
    end

    test "unknown options raise" do
      assert_raise ArgumentError, ~r/colour/, fn ->
        JSON.open(fixture("envelope.json"), colour: :blue)
      end
    end
  end

  describe "open/2 single objects" do
    test "a document that is one object reads as one record" do
      json = ~s({"id": 2, "name": "test", "address": {"city": "Perth"}, "tags": [1]})

      assert cells!({:string, json}) == [
               ["id", "name", "address.city", "tags"],
               [2, "test", "Perth", "[1]"]
             ]
    end

    test "at: [] reads an object holding a records array as one record" do
      json = ~s({"id": 2, "addresses": [{"city": "Perth"}]})

      assert cells!({:string, json}) == [["city"], ["Perth"]]
      assert cells!({:string, json}, at: []) == [["id", "addresses"], [2, ~s([{"city":"Perth"}])]]
    end

    test "at: naming an object reads it as one record" do
      assert cells!(fixture("envelope.json"), at: ["meta"]) == [["page", "warnings"], [1, "[]"]]
    end

    test "facts for one object" do
      assert {:ok, %{layout: :objects, at: [], arrays: [], records: 1}} =
               JSON.facts({:string, ~s({"id": 2})}, [])
    end
  end

  describe "open/2 keyed" do
    test "keyed: reads an object of objects as records, each key in a column" do
      json = ~s({"1": {"name": "apple", "price": 1.5}, "2": {"name": "pear"}})

      assert cells!({:string, json}, keyed: "product_id") == [
               ["product_id", "name", "price"],
               ["1", "apple", Decimal.new("1.5")],
               ["2", "pear", ""]
             ]
    end

    test "keyed: reads the object at: names" do
      json = ~s({"meta": {}, "data": {"a": {"n": 1}, "b": {"n": 2}}})

      assert cells!({:string, json}, at: ["data"], keyed: "key") == [
               ["key", "n"],
               ["a", 1],
               ["b", 2]
             ]
    end

    test "keyed: reads the whole document by default, arrays inside values stay cells" do
      json = ~s({"1": {"tags": [{"x": 1}]}})

      assert cells!({:string, json}, keyed: "id") == [["id", "tags"], ["1", ~s([{"x":1}])]]
    end

    test "an empty keyed object gives no lines" do
      assert cells!({:string, "{}"}, keyed: "id") == []
    end

    test "a value already holding the key column is a parse error" do
      json = ~s({"1": {"product_id": 1}})

      assert {:error, {:parse_error, message}} = JSON.open({:string, json}, keyed: "product_id")
      assert message =~ ~s("product_id")
    end

    test "a value that is not an object is a parse error that does not show the key" do
      json = ~s({"a": {"n": 1}, "secret-id": 3})

      assert {:error, {:parse_error, message}} = JSON.open({:string, json}, keyed: "id")
      assert message =~ "entry 2"
      refute message =~ "secret-id"
    end

    test "keyed: on something that is not an object is an error" do
      assert {:error, {:not_keyed, []}} = JSON.open({:string, ~s([{"id": 1}])}, keyed: "id")

      assert {:error, {:not_keyed, ["data"]}} =
               JSON.open(fixture("envelope.json"), at: ["data"], keyed: "id")
    end

    test "keyed: must be a name" do
      for keyed <- [:id, 1, ""] do
        assert_raise ArgumentError, ~r/keyed/, fn ->
          JSON.open({:string, "{}"}, keyed: keyed)
        end
      end
    end
  end

  describe "open/2 unnest" do
    defp keep, do: %{"order_id" => "id", "customer_id" => "customer.id"}

    test "unnest: reads the child array of every record, keep: carries parent columns" do
      assert cells!(fixture("orders_page.json"), unnest: ["lines"], keep: keep()) == [
               ["customer_id", "order_id", "id", "sku", "qty", "discount.code"],
               [2, 7, 1, 78_632_478, 3, ""],
               [2, 7, 2, 78_632_479, 1, ""],
               [2, 9, 3, 78_632_478, 2, "TEN"]
             ]
    end

    test "without keep: the child rows stand alone" do
      assert [["id", "sku", "qty", "discount.code"] | _lines] =
               cells!(fixture("orders_page.json"), unnest: ["lines"])
    end

    test "an empty, null or missing child array gives no rows for that record" do
      json =
        ~s([{"id": 1, "lines": []}, {"id": 2, "lines": null}, {"id": 3}, {"id": 4, "lines": [{"n": 1}]}])

      assert cells!({:string, json}, unnest: ["lines"], keep: %{"order_id" => "id"}) == [
               ["order_id", "n"],
               [4, 1]
             ]
    end

    test "no child rows at all gives no lines" do
      assert cells!({:string, ~s([{"id": 1, "lines": []}])}, unnest: ["lines"]) == []
    end

    test "an array of plain values gives one column named after its key" do
      assert cells!(fixture("orders_page.json"), unnest: ["tags"], keep: %{"order_id" => "id"}) ==
               [["order_id", "tags"], [7, "new"], [7, "gift"]]
    end

    test "plain values deeper in take the dotted path as their column" do
      json = ~s([{"id": 1, "detail": {"tags": ["a", "b"]}}])

      assert cells!({:string, json}, unnest: ["detail", "tags"]) == [
               ["detail.tags"],
               ["a"],
               ["b"]
             ]
    end

    test "unnest: reaches through nested objects" do
      json = ~s([{"id": 1, "detail": {"items": [{"x": 1}, {"x": 2}]}}])

      assert cells!({:string, json}, unnest: ["detail", "items"], keep: %{"parent" => "id"}) ==
               [["parent", "x"], [1, 1], [1, 2]]
    end

    test "a kept parent column that is missing is blank" do
      json = ~s([{"lines": [{"n": 1}]}])

      assert cells!({:string, json}, unnest: ["lines"], keep: %{"order_id" => "id"}) == [
               ["order_id", "n"],
               ["", 1]
             ]
    end

    test "a kept name clashing with a child key is a parse error naming the record" do
      assert {:error, {:parse_error, message}} =
               JSON.open(fixture("orders_page.json"), unnest: ["lines"], keep: %{"id" => "id"})

      assert message =~ "element 1"
      assert message =~ ~s("id")
    end

    test "a child value that is not an array is a parse error" do
      assert {:error, {:parse_error, message}} =
               JSON.open({:string, ~s([{"lines": [{"n": 1}]}, {"lines": "x"}])},
                 unnest: ["lines"]
               )

      assert message =~ "element 2"
      assert message =~ "lines"
    end

    test "unnest: over arrays of arrays is a parse error" do
      assert {:error, {:parse_error, message}} =
               JSON.open({:string, ~s([["a"]])}, unnest: ["lines"])

      assert message =~ "element 1 is an array, expected an object"
    end

    test "a single object with a child array" do
      json = ~s({"id": 2, "addresses": [{"city": "Perth"}, {"city": "Hobart"}]})

      assert cells!({:string, json},
               at: [],
               unnest: ["addresses"],
               keep: %{"customer_id" => "id"}
             ) == [["customer_id", "city"], [2, "Perth"], [2, "Hobart"]]
    end

    test "keyed objects with a child array" do
      json = ~s({"1": {"name": "apple", "barcodes": [{"code": "a1"}, {"code": "a2"}]}})

      assert cells!({:string, json},
               keyed: "product_id",
               unnest: ["barcodes"],
               keep: %{"product_id" => "product_id"}
             ) == [["product_id", "code"], ["1", "a1"], ["1", "a2"]]
    end

    test "locate renames a child table with a spec" do
      spec =
        Table.spec(
          header: [columns: %{"order_id" => ["order_id"], "sku" => ["sku"], "qty" => ["qty"]}]
        )

      assert {:ok, table} =
               JSON.locate(fixture("orders_page.json"), spec,
                 unnest: ["lines"],
                 keep: %{"order_id" => "id"}
               )

      assert [%{"order_id" => 7, "sku" => 78_632_478, "qty" => 3} | _rows] =
               Enum.to_list(table.rows)
    end

    test "classify a child table against a line shape" do
      line =
        Shape.new(
          name: "order_line",
          spec:
            Table.spec(
              header: [columns: %{"order_id" => ["order_id"], "sku" => ["sku"], "qty" => ["qty"]}],
              row: [match: %{"sku" => :integer, "qty" => :integer}]
            )
        )

      assert {:ok, %Result{verdict: :match} = result} =
               JSON.classify(fixture("orders_page.json"), [line],
                 unnest: ["lines"],
                 keep: %{"order_id" => "id"}
               )

      assert %{unnest: ["lines"]} = result.file.format
    end

    test "facts list the child arrays inside records" do
      assert {:ok, %{nested: [["lines"], ["tags"]], unnest: nil}} =
               JSON.facts(fixture("orders_page.json"), [])
    end

    test "unnest: must be a list of keys, keep: a map of names, keep: needs unnest:" do
      for opts <- [
            [unnest: []],
            [unnest: "lines"],
            [unnest: ["lines", 1]],
            [unnest: ["lines"], keep: ["id"]],
            [unnest: ["lines"], keep: %{"order_id" => :id}],
            [keep: %{"order_id" => "id"}]
          ] do
        assert_raise ArgumentError, fn -> JSON.open(fixture("orders_page.json"), opts) end
      end
    end
  end

  describe "open/2 sources" do
    test "a document in a string" do
      assert [["id"], [1]] = cells!({:string, ~s([{"id": 1}])})
    end

    test "a document in a stream of chunks" do
      chunks = fixture("envelope.json") |> File.stream!(16) |> Enum.to_list()

      assert cells!({:stream, chunks}) == cells!(fixture("envelope.json"))
    end

    test "a byte order mark is skipped" do
      assert [["id"], [1]] = cells!({:string, "﻿" <> ~s([{"id": 1}])})
    end

    test "a missing file is an error" do
      assert {:error, :enoent} = JSON.open(fixture("missing.json"), [])
    end

    test "a file that is not json is a parse error", %{tmp_dir: dir} do
      path = Path.join(dir, "notes.json")
      File.write!(path, "id,name\n1,alice\n")

      assert {:error, {:parse_error, _message}} = JSON.open(path, [])
    end

    test "a cut off document is a parse error" do
      assert {:error, {:parse_error, _message}} = JSON.open({:string, ~s([{"id": 1})}, [])
    end

    test "text after the document is a parse error" do
      assert {:error, {:parse_error, _message}} = JSON.open({:string, ~s([{"id": 1}] [])}, [])
    end

    test "parse errors do not show the content" do
      assert {:error, {:parse_error, message}} =
               JSON.open({:string, ~s([{"secret": "hunter2"} x])}, [])

      refute message =~ "hunter2"
    end

    test "an unsupported source is an error" do
      assert {:error, {:unsupported_source, :bills}} = JSON.open(:bills, [])
    end
  end

  describe "facts/2" do
    test "an array of objects at the top" do
      assert {:ok, %{layout: :objects, at: [], arrays: [[]], records: 3}} =
               JSON.facts(fixture("late_key.json"), [])
    end

    test "an array of arrays" do
      assert {:ok, %{layout: :arrays, records: 5}} = JSON.facts(fixture("offset.json"), [])
    end

    test "every records array in an object, and the one read" do
      assert {:ok, %{at: ["customers"], arrays: [["customers"], ["orders"]]}} =
               JSON.facts(fixture("two_arrays.json"), [])

      assert {:ok, %{at: ["orders"], layout: :objects, records: 2}} =
               JSON.facts(fixture("two_arrays.json"), at: ["orders"])
    end

    test "an empty records array" do
      assert {:ok, %{layout: :empty, at: ["errors"], records: 0}} =
               JSON.facts(fixture("envelope.json"), at: ["errors"])
    end
  end

  describe "arrays/2" do
    test "every records array in document order" do
      assert {:ok, [["customers"], ["orders"]]} = JSON.arrays(fixture("two_arrays.json"), [])
    end

    test "an array at the top is the document itself" do
      assert {:ok, [[]]} = JSON.arrays(fixture("late_key.json"), [])
    end

    test "at: narrows to one" do
      assert {:ok, [["orders"]]} = JSON.arrays(fixture("two_arrays.json"), at: ["orders"])
    end

    test "an unknown at is an error" do
      assert {:error, {:unknown_at, ["nope"]}} =
               JSON.arrays(fixture("two_arrays.json"), at: ["nope"])
    end

    test "a document without a records array has none" do
      assert {:ok, []} = JSON.arrays({:string, ~s({"meta": {}})}, [])
    end
  end

  describe "classify_arrays/3" do
    defp customer do
      Shape.new(
        name: "customer",
        spec: Table.spec(header: [columns: %{"customer" => ["customer"], "name" => ["name"]}])
      )
    end

    defp verdicts(arrays) do
      for {at, {:ok, %Result{verdict: verdict, shape: shape}}} <- arrays,
          do: {at, verdict, verdict == :match && shape.name}
    end

    test "classifies every records array of a document" do
      assert {:ok, arrays} = JSON.classify_arrays(fixture("two_arrays.json"), [customer()])

      assert verdicts(arrays) == [
               {["customers"], :match, "customer"},
               {["orders"], :unknown, false}
             ]
    end

    test "each result names its array" do
      assert {:ok, arrays} = JSON.classify_arrays(fixture("two_arrays.json"), [customer()])

      for {at, {:ok, result}} <- arrays, do: assert(result.file.format.at == at)
    end

    test "at: narrows to one, classify options apply to each" do
      assert {:ok, [{["orders"], {:ok, %Result{verdict: :unknown}}}]} =
               JSON.classify_arrays(fixture("two_arrays.json"), [customer()], at: ["orders"])

      assert {:ok, [{["customers"], {:ok, %Result{verdict: :match}}} | _orders]} =
               JSON.classify_arrays(fixture("two_arrays.json"), [customer()], min_score: 1.0)
    end

    test "a document that cannot be read is an error" do
      assert {:error, {:parse_error, _message}} =
               JSON.classify_arrays({:string, "[1,"}, [customer()])
    end
  end

  describe "reader functions" do
    test "stream gives row maps under the header" do
      assert {:ok, rows} = JSON.stream(fixture("late_key.json"))

      assert Enum.to_list(rows) == [
               %{"sku" => 78_632_478, "item" => "apple", "discount" => ""},
               %{"sku" => 78_632_479, "item" => "pear", "discount" => ""},
               %{"sku" => 78_632_480, "item" => "fig", "discount" => Decimal.new("0.5")}
             ]
    end

    test "locate finds a table below a title in an array of arrays" do
      assert {:ok, table} = JSON.locate(fixture("offset.json"), invoice().spec)
      assert table.header_row == 3

      assert Enum.to_list(table.rows) == [
               %{"sku" => 78_632_478, "item" => "apple", "total" => Decimal.new("3.5")},
               %{"sku" => 78_632_479, "item" => "pear", "total" => Decimal.new("4.25")}
             ]
    end

    test "classify matches records inside an envelope and names the array" do
      assert {:ok, %Result{verdict: :match} = result} =
               JSON.classify(fixture("envelope.json"), [invoice()])

      assert %{at: ["data"], layout: :objects} = result.file.format
    end

    test "classify reads the array at: names" do
      assert {:ok, %Result{verdict: :unknown}} =
               JSON.classify(fixture("two_arrays.json"), [invoice()], at: ["customers"])
    end

    test "classify gives a parse error for a document that is not json", %{tmp_dir: dir} do
      path = Path.join(dir, "notes.json")
      File.write!(path, "id,name\n")

      assert {:error, {:parse_error, _message}} = JSON.classify(path, [invoice()])
    end

    test "load builds a grid of the cells" do
      assert {:ok, grid} = JSON.load(fixture("offset.json"))
      assert Grid.cell(grid, "B4") == "apple"
    end

    test "extensions" do
      assert JSON.extensions() == ["json"]
    end
  end
end

defmodule Refract.JSONWriteTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.JSONL

  defp cells!(reader, path) do
    {:ok, raw} = reader.open(path, [])

    Enum.to_list(raw)
  end

  defp types do
    %{
      "text" => "say \"hi\"\né",
      "decimal" => Decimal.new("3.50"),
      "integer" => 7,
      "float" => 1.5,
      "day" => ~D[2026-10-21],
      "at" => ~N[2026-10-21 09:30:00],
      "utc" => ~U[2026-10-21 09:30:00Z],
      "time" => ~T[09:30:00],
      "flag" => true,
      "blank" => nil,
      "list" => [1, "a"]
    }
  end

  @header [
    "text",
    "decimal",
    "integer",
    "float",
    "day",
    "at",
    "utc",
    "time",
    "flag",
    "blank",
    "list"
  ]

  @read_back [
    "say \"hi\"\né",
    Decimal.new("3.50"),
    7,
    Decimal.new("1.5"),
    "2026-10-21",
    "2026-10-21T09:30:00",
    "2026-10-21T09:30:00Z",
    "09:30:00",
    true,
    "",
    ~s([1,"a"])
  ]

  for writer <- [Refract.JSON, Refract.JSONL] do
    describe "#{inspect(writer)} write/3" do
      @writer writer

      test "native values read back with their types", %{tmp_dir: dir} do
        path = Path.join(dir, "types.#{@writer.extension()}")

        assert :ok = @writer.write([types()], path, header: @header)
        assert cells!(@writer, path) == [@header, @read_back]
      end

      test "decimals are written as numbers with every digit", %{tmp_dir: dir} do
        path = Path.join(dir, "amounts.#{@writer.extension()}")

        assert :ok = @writer.write([%{"amount" => Decimal.new("0.10000000000000000001")}], path)
        assert File.read!(path) =~ ~s("amount":0.10000000000000000001)
      end

      test "keys are written in header order", %{tmp_dir: dir} do
        path = Path.join(dir, "order.#{@writer.extension()}")

        assert :ok = @writer.write([%{"a" => 1, "b" => 2}], path, header: ["b", "a"])
        assert File.read!(path) =~ ~s({"b":2,"a":1})
      end

      test "a row without a header key raises", %{tmp_dir: dir} do
        path = Path.join(dir, "missing.#{@writer.extension()}")

        assert_raise KeyError, fn -> @writer.write([%{"a" => 1}], path, header: ["a", "b"]) end
        assert File.ls!(dir) == []
      end

      test "a cell json cannot hold raises without the value", %{tmp_dir: dir} do
        path = Path.join(dir, "bad.#{@writer.extension()}")

        for cell <- [Decimal.new("Infinity"), Decimal.new("NaN"), %{"secret" => "hunter2"}, {1}] do
          error =
            assert_raise ArgumentError, fn -> @writer.write([%{"a" => cell}], path) end

          refute error.message =~ "hunter2"
        end
      end

      test "rows are written lazily", %{tmp_dir: dir} do
        path = Path.join(dir, "many.#{@writer.extension()}")
        rows = Stream.map(1..5_000, &%{"id" => &1})

        assert :ok = @writer.write(rows, path)
        assert length(cells!(@writer, path)) == 5_001
      end

      test "header: must be a list of names", %{tmp_dir: dir} do
        path = Path.join(dir, "x.#{@writer.extension()}")

        for header <- ["id", [:id], ["id", 1]] do
          assert_raise ArgumentError, ~r/header/, fn ->
            @writer.write([%{"id" => 1}], path, header: header)
          end
        end
      end

      test "unknown options raise", %{tmp_dir: dir} do
        assert_raise ArgumentError, ~r/colour/, fn ->
          @writer.write([%{"id" => "1"}], Path.join(dir, "x.#{@writer.extension()}"),
            colour: :blue
          )
        end
      end
    end
  end

  describe "Refract.JSON write/3 layout" do
    test "an array with an object per line", %{tmp_dir: dir} do
      path = Path.join(dir, "out.json")

      assert :ok = Refract.JSON.write([%{"id" => 1}, %{"id" => 2}], path)
      assert File.read!(path) == ~s([\n{"id":1},\n{"id":2}\n]\n)
    end

    test "no rows writes an empty array, header or not", %{tmp_dir: dir} do
      path = Path.join(dir, "empty.json")

      assert :ok = Refract.JSON.write([], path)
      assert File.read!(path) == "[]\n"

      assert :ok = Refract.JSON.write([], path, header: ["id"])
      assert File.read!(path) == "[]\n"
    end

    test "the output is json any parser reads", %{tmp_dir: dir} do
      path = Path.join(dir, "types.json")

      :ok = Refract.JSON.write([types(), types()], path, header: @header)

      assert [first, _second] = :json.decode(File.read!(path))
      assert first["decimal"] == 3.5
      assert first["text"] == "say \"hi\"\né"
    end

    test "extension" do
      assert Refract.JSON.extension() == "json"
    end
  end

  describe "Refract.JSONL write/3 layout" do
    test "an object per line", %{tmp_dir: dir} do
      path = Path.join(dir, "out.jsonl")

      assert :ok = JSONL.write([%{"id" => 1}, %{"id" => 2}], path)
      assert File.read!(path) == ~s({"id":1}\n{"id":2}\n)
    end

    test "no rows writes an empty file", %{tmp_dir: dir} do
      path = Path.join(dir, "empty.jsonl")

      assert :ok = JSONL.write([], path, header: ["id"])
      assert File.read!(path) == ""
    end

    test "every line is json any parser reads", %{tmp_dir: dir} do
      path = Path.join(dir, "types.jsonl")

      :ok = JSONL.write([types(), types()], path, header: @header)

      for line <- path |> File.read!() |> String.split("\n", trim: true) do
        assert %{"flag" => true, "blank" => :null} = :json.decode(line)
      end
    end

    test "extension" do
      assert JSONL.extension() == "jsonl"
    end
  end
end

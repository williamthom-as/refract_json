defmodule Refract.E2E.SimpleJoinsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.JSON
  alias Refract.JSONL
  alias Refract.Query

  @golden Path.expand("../../fixtures/golden/simple_joins", __DIR__)

  test "names from json and ages from json lines join on identifier", %{tmp_dir: dir} do
    {:ok, names} = JSON.stream(Path.join(@golden, "names.json"))
    {:ok, ages} = JSONL.stream(Path.join(@golden, "ages.jsonl"))

    query = Query.open!(engine: Refract.Query.DuckDB)

    :ok = Query.table(query, "names", names, columns: ["identifier", "name"])
    :ok = Query.table(query, "ages", ages, columns: ["identifier", "age"])

    result =
      Query.run!(
        query,
        "SELECT identifier, n.name, a.age FROM names n JOIN ages a USING (identifier) ORDER BY identifier"
      )

    out = Path.join(dir, "joined.csv")
    :ok = CSV.write(result.rows, out, header: result.columns)

    assert File.read!(out) == File.read!(Path.join(@golden, "expected.csv"))
  end
end

defmodule Refract.JSONProfileTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.JSON
  alias Refract.JSONL
  alias Refract.Profile
  alias Refract.Profile.Cluster
  alias Refract.Profile.Column
  alias Refract.Profile.Variant
  alias Refract.Shape
  alias Refract.Table

  defp ledger do
    Shape.new(
      name: "ledger",
      spec:
        Table.spec(
          header: [columns: %{"account" => ["account"], "cost_centre" => ["cost_centre"]}]
        )
    )
  end

  defp record(cost_centre),
    do: Jason.encode!(%{"account" => "A-1", "cost_centre" => cost_centre})

  defp write(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  test "spellings group, lines count records after the header row", %{tmp_dir: dir} do
    path =
      write(
        dir,
        "ledger.json",
        "[" <> Enum.map_join(["north", "North", "north"], ",", &record/1) <> "]"
      )

    assert {:ok, %{columns: %{"cost_centre" => column}}} = JSON.profile(path, ledger())

    assert %Column{
             clusters: [
               %Cluster{
                 variants: [
                   %Variant{value: "north", count: 2, lines: [2, 4]},
                   %Variant{value: "North", count: 1, lines: [3]}
                 ]
               }
             ]
           } = column
  end

  test "jsonl records profile the same way", %{tmp_dir: dir} do
    path = write(dir, "ledger.jsonl", Enum.map_join(["north", "NORTH"], "\n", &record/1) <> "\n")

    assert {:ok, %{columns: %{"cost_centre" => %Column{clusters: [cluster]}}}} =
             JSONL.profile(path, ledger())

    assert Enum.map(cluster.variants, & &1.value) == ["north", "NORTH"]
  end

  test "child rows are profiled through unnest and keep", %{tmp_dir: dir} do
    orders =
      Jason.encode!(%{
        "orders" => [
          %{
            "account" => "A-1",
            "lines" => [%{"cost_centre" => "north"}, %{"cost_centre" => "North"}]
          },
          %{"account" => "A-2", "lines" => [%{"cost_centre" => "NORTH"}]}
        ]
      })

    path = write(dir, "orders.json", orders)

    assert {:ok, %{rows: 3, columns: %{"cost_centre" => %Column{clusters: [cluster]}}}} =
             JSON.profile(path, ledger(), unnest: ["lines"], keep: %{"account" => "account"})

    assert Enum.map(cluster.variants, & &1.value) == ["north", "North", "NORTH"]
  end

  test "a folder mixing json and jsonl profiles as one", %{tmp_dir: dir} do
    json = write(dir, "1_jan.json", "[" <> record("north") <> "]")
    jsonl = write(dir, "2_feb.jsonl", record("North") <> "\n")

    assert {:ok, %{results: %{{"ledger", 1} => result}, skipped: []}} =
             Profile.folder(dir, [ledger()], readers: [JSON, JSONL])

    assert %{columns: %{"cost_centre" => %Column{clusters: [%Cluster{variants: variants}]}}} =
             result

    assert Enum.map(variants, & &1.files) == [%{json => [2]}, %{jsonl => [2]}]
  end
end

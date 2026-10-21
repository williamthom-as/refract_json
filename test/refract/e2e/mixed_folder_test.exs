defmodule Refract.E2E.MixedFolderTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.Classify
  alias Refract.Classify.Result
  alias Refract.CSV
  alias Refract.JSON
  alias Refract.JSONL
  alias Refract.Shape
  alias Refract.Table

  defp shapes do
    [
      Shape.new(
        name: "invoice",
        spec:
          Table.spec(
            header: [columns: %{"sku" => ["sku"], "item" => ["item"], "total" => ["total"]}],
            row: [match: %{"sku" => :integer, "total" => :number}]
          )
      ),
      Shape.new(
        name: "aws_bill",
        spec:
          Table.spec(
            header: [columns: %{"account" => ["account"], "cost" => ["cost"]}],
            row: [match: %{"account" => ~r/^\d{12}$/, "cost" => :number}]
          )
      ),
      Shape.new(
        name: "customer",
        spec: Table.spec(header: [columns: %{"customer" => ["customer"], "name" => ["name"]}])
      ),
      Shape.new(
        name: "order",
        spec:
          Table.spec(
            header: [
              columns: %{"order" => ["order"], "customer" => ["customer"], "total" => ["total"]}
            ],
            row: [match: %{"total" => :number}]
          )
      )
    ]
  end

  defp invoices,
    do: [
      %{"sku" => 78_632_478, "item" => "apple", "total" => Decimal.new("3")},
      %{"sku" => 12_319_082, "item" => "pear", "total" => Decimal.new("9.5")}
    ]

  defp bills, do: [%{"account" => 123_456_789_012, "cost" => Decimal.new("1.25")}]

  defp readers, do: [JSON, JSONL, CSV]

  test "csv, json and json lines files classify against one shape set", %{tmp_dir: dir} do
    for writer <- readers() do
      :ok = writer.write(invoices(), Path.join(dir, "invoice.#{writer.extension()}"))
      :ok = writer.write(bills(), Path.join(dir, "aws_bill.#{writer.extension()}"))
    end

    {:ok, results} = Classify.folder(dir, shapes(), readers: readers())

    assert results
           |> Enum.map(fn {path, {:ok, %Result{verdict: verdict, shape: shape}}} ->
             {Path.basename(path), verdict, shape.name}
           end) == [
             {"aws_bill.csv", :match, "aws_bill"},
             {"aws_bill.json", :match, "aws_bill"},
             {"aws_bill.jsonl", :match, "aws_bill"},
             {"invoice.csv", :match, "invoice"},
             {"invoice.json", :match, "invoice"},
             {"invoice.jsonl", :match, "invoice"}
           ]
  end

  test "a folder classifies one table per file, documents with more arrays drill in", %{
    tmp_dir: dir
  } do
    File.cp!(Path.expand("../../fixtures/two_arrays.json", __DIR__), Path.join(dir, "crm.json"))
    :ok = CSV.write(bills(), Path.join(dir, "aws_bill.csv"))

    {:ok, results} = Classify.folder(dir, shapes(), readers: readers())

    drilled =
      Enum.flat_map(results, fn
        {path, {:ok, %Result{file: %{format: %{arrays: [_one, _two | _rest]}}}}} ->
          {:ok, arrays} = JSON.classify_arrays(path, shapes())
          for {at, {:ok, result}} <- arrays, do: {Path.basename(path), at, result.shape.name}

        {path, {:ok, result}} ->
          [{Path.basename(path), nil, result.shape.name}]
      end)

    assert drilled == [
             {"aws_bill.csv", nil, "aws_bill"},
             {"crm.json", ["customers"], "customer"},
             {"crm.json", ["orders"], "order"}
           ]
  end

  test "scan: on a folder reader entry reads keys from the first records", %{tmp_dir: dir} do
    :ok = JSONL.write(invoices(), Path.join(dir, "invoice.jsonl"))

    {:ok, results} = Classify.folder(dir, shapes(), readers: [{JSONL, scan: 1}])

    assert [{_path, {:ok, %Result{verdict: :match}}}] = Enum.to_list(results)
  end
end

defmodule Refract.E2E.APIStitchTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 10_000

  alias Refract.CSV
  alias Refract.JSON
  alias Refract.Query
  alias Refract.Table

  @api Path.expand("../../fixtures/api", __DIR__)

  defp body(name), do: {:string, File.read!(Path.join(@api, name))}

  defp locate!(body, spec, opts) do
    {:ok, table} = JSON.locate(body, spec, opts)

    table
  end

  test "order pages, customer details and a product map stitch into one table", %{tmp_dir: dir} do
    pages = [body("orders_1.json"), body("orders_2.json")]
    customers = [body("customer_2.json"), body("customer_5.json")]

    order_spec =
      Table.spec(header: [columns: %{"order_id" => ["id"], "customer_id" => ["customer.id"]}])

    line_spec =
      Table.spec(
        header: [columns: %{"order_id" => ["order_id"], "sku" => ["sku"], "qty" => ["qty"]}]
      )

    customer_spec = Table.spec(header: [columns: %{"customer_id" => ["id"], "name" => ["name"]}])

    product_spec =
      Table.spec(
        header: [columns: %{"sku" => ["sku"], "product" => ["name"], "price" => ["price"]}]
      )

    orders = Table.concat(Enum.map(pages, &locate!(&1, order_spec, at: ["data"])))

    lines =
      pages
      |> Enum.map(
        &locate!(&1, line_spec, at: ["data"], unnest: ["lines"], keep: %{"order_id" => "id"})
      )
      |> Table.concat()

    customers = Table.concat(Enum.map(customers, &locate!(&1, customer_spec, at: [])))
    products = locate!(body("products.json"), product_spec, keyed: "sku")

    query = Query.open!(engine: Refract.Query.DuckDB)

    :ok = Query.table(query, "orders", orders)
    :ok = Query.table(query, "lines", lines)
    :ok = Query.table(query, "customers", customers)
    :ok = Query.table(query, "products", products)

    result =
      Query.run!(query, """
      SELECT order_id, c.name AS customer, sku, p.product, l.qty,
             CAST(p.price AS DECIMAL(10, 2)) * CAST(l.qty AS INTEGER) AS total
      FROM lines l
      JOIN orders o USING (order_id)
      JOIN customers c USING (customer_id)
      JOIN products p USING (sku)
      ORDER BY order_id, sku
      """)

    out = Path.join(dir, "stitched.csv")
    :ok = CSV.write(result.rows, out, header: result.columns)

    assert File.read!(out) == File.read!(Path.join(@api, "expected.csv"))
  end

  test "a customer detail holding an array needs at: [] to read as the customer" do
    spec = Table.spec(header: [columns: %{"customer_id" => ["id"], "name" => ["name"]}])

    assert {:error, {:header_not_found, _miss}} = JSON.locate(body("customer_2.json"), spec)
    assert {:ok, _table} = JSON.locate(body("customer_2.json"), spec, at: [])
  end
end

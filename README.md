# refract_json

json and json lines reader and writer for [refract](https://github.com/williamthom-as/refract_core).

- `Refract.JSON` reads `.json`: an array of objects, an array of arrays, or records inside an object (`at:`)
- `Refract.JSONL` reads `.jsonl` / `.ndjson`, streamed line by line (`scan:`, `columns:`)
- both write: an object per row, keys in header order, exact decimals
- nested objects flatten to dotted keys, arrays inside a record are their json text
- a document with several records arrays: `Refract.JSON.arrays/2`, `Refract.JSON.classify_arrays/3`

```elixir
{:ok, rows} = Refract.JSON.stream("export.json", at: ["data"])
{:ok, results} = Refract.Classify.folder("inbox", shapes, readers: [Refract.JSON, Refract.JSONL])
:ok = Refract.JSONL.write(rows, "out/orders.jsonl", header: ["sku", "total"])
```

## Install

```elixir
{:refract_json, github: "williamthom-as/refract_json", tag: "v0.1.0"}
```

## Development

against local checkouts: `REFRACT_PATH=../refract REFRACT_DUCKDB_PATH=../refract_duckdb mix test`

## License

Apache-2.0, see [LICENSE](LICENSE).

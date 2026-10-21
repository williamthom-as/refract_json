defmodule Refract.Conformance.JSONLReaderTest do
  use Refract.Test.ReaderCase,
    reader: Refract.JSONL,
    build: fn rows, dir ->
      path = Path.join(dir, "source.jsonl")

      File.write!(path, Enum.map(rows, &[JSON.encode!(&1), "\n"]))

      path
    end
end

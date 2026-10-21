defmodule Refract.Conformance.JSONReaderTest do
  use Refract.Test.ReaderCase,
    reader: Refract.JSON,
    build: fn rows, dir ->
      path = Path.join(dir, "source.json")

      File.write!(path, JSON.encode!(rows))

      path
    end
end

defmodule Refract.Conformance.JSONWriterTest do
  use Refract.Test.WriterCase,
    writer: Refract.JSON,
    read: fn path ->
      {:ok, raw} = Refract.JSON.open(path, [])

      Enum.to_list(raw)
    end
end

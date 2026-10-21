defmodule Refract.Conformance.JSONLWriterTest do
  use Refract.Test.WriterCase,
    writer: Refract.JSONL,
    read: fn path ->
      {:ok, raw} = Refract.JSONL.open(path, [])

      Enum.to_list(raw)
    end
end

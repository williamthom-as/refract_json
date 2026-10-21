defmodule Refract.JSON.Decode do
  @moduledoc false

  @type value ::
          String.t()
          | integer()
          | Decimal.t()
          | boolean()
          | nil
          | [value()]
          | {:object, [{String.t(), value()}]}

  @spec decode(binary()) :: {:ok, value()} | {:error, {:parse_error, String.t()}}

  def decode(json) do
    json
    |> strip_bom()
    |> JSON.decode(:ok, float: &Decimal.new/1, object_finish: &object/2)
    |> decoded()
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, json::binary>>), do: json
  defp strip_bom(json), do: json

  defp object(pairs, acc), do: {{:object, Enum.reverse(pairs)}, acc}

  defp decoded({value, :ok, ""}), do: {:ok, value}
  defp decoded({_value, :ok, _rest}), do: parse_error("unexpected text after the json value")

  defp decoded({:error, {:unexpected_end, position}}),
    do: parse_error("unexpected end of input at byte #{position}")

  defp decoded({:error, {:invalid_byte, position, _byte}}),
    do: parse_error("invalid byte at byte #{position}")

  defp decoded({:error, {:unexpected_sequence, position, _sequence}}),
    do: parse_error("unexpected sequence at byte #{position}")

  defp parse_error(message), do: {:error, {:parse_error, message}}
end

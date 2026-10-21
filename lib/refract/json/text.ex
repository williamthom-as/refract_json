defmodule Refract.JSON.Text do
  @moduledoc false

  alias Refract.JSON.Decode

  @type value ::
          Decode.value()
          | float()
          | Date.t()
          | NaiveDateTime.t()
          | DateTime.t()
          | Time.t()

  @spec encode(value()) :: String.t()

  def encode(value), do: value |> iodata() |> IO.iodata_to_binary()

  @spec iodata(value()) :: iodata()

  def iodata(nil), do: "null"
  def iodata(value) when is_boolean(value), do: Atom.to_string(value)
  def iodata(value) when is_integer(value), do: Integer.to_string(value)
  def iodata(value) when is_float(value), do: Float.to_string(value)
  def iodata(%Decimal{coef: coef} = value) when is_integer(coef), do: Decimal.to_string(value)
  def iodata(%Date{} = value), do: value |> Date.to_iso8601() |> iodata()
  def iodata(%NaiveDateTime{} = value), do: value |> NaiveDateTime.to_iso8601() |> iodata()
  def iodata(%DateTime{} = value), do: value |> DateTime.to_iso8601() |> iodata()
  def iodata(%Time{} = value), do: value |> Time.to_iso8601() |> iodata()
  def iodata(value) when is_binary(value), do: JSON.encode_to_iodata!(value)
  def iodata(values) when is_list(values), do: ["[", joined(values, &iodata/1), "]"]
  def iodata({:object, pairs}), do: ["{", joined(pairs, &pair/1), "}"]

  def iodata(%Decimal{}) do
    raise ArgumentError, "cannot write an infinite or not a number decimal as json"
  end

  def iodata(%module{}) do
    raise ArgumentError, "cannot write a #{inspect(module)} as json"
  end

  def iodata(_value) do
    raise ArgumentError, "cannot write a map, tuple, atom, pid, reference or function as json"
  end

  defp pair({key, value}), do: [JSON.encode_to_iodata!(key), ":", iodata(value)]

  defp joined(values, fun), do: values |> Enum.map(fun) |> Enum.intersperse(",")
end

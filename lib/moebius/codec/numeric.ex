defmodule Moebius.Codec.Numeric do
  @moduledoc false
  # An epgsql codec for `numeric` that decodes to Decimal and encodes from Decimal,
  # integers, floats or numeric strings. Without it, epgsql returns numeric as text.
  #
  # Postgres's binary numeric is base 10,000:
  #   ndigits::16, weight::signed-16, sign::16, dscale::16, then ndigits 16-bit digits
  # value = sum(digit[i] * 10000^(weight - i)); dscale is the number of decimal places.

  @behaviour :epgsql_codec

  @positive 0x0000
  @negative 0x4000
  @nan 0xC000
  @pos_inf 0xD000
  @neg_inf 0xF000

  @doc false
  # PostgreSQL numeric supports 131,072 digits before the decimal point and 16,383
  # after it. Check before encoding: bit syntax truncates overflowing integers.
  def representable?(%Decimal{sign: sign, coef: coef})
      when sign in [-1, 1] and coef in [:NaN, :inf],
      do: true

  def representable?(%Decimal{sign: sign, coef: coef, exp: exp})
      when sign in [-1, 1] and is_integer(coef) and coef >= 0 and is_integer(exp) do
    exp >= -16_383 and
      (coef == 0 or byte_size(Integer.to_string(coef)) + exp <= 131_072)
  end

  def representable?(_), do: false

  @impl true
  def init(_opts, _sock), do: []

  @impl true
  def names, do: [:numeric]

  @impl true
  def decode(<<_::16, _::signed-16, @nan::16, _::16, _::binary>>, :numeric, _),
    do: Decimal.new("NaN")

  def decode(<<_::16, _::signed-16, @pos_inf::16, _::16, _::binary>>, :numeric, _),
    do: Decimal.new("Infinity")

  def decode(<<_::16, _::signed-16, @neg_inf::16, _::16, _::binary>>, :numeric, _),
    do: Decimal.new("-Infinity")

  def decode(
        <<ndigits::16, weight::signed-16, sign::16, dscale::16, digits::binary>>,
        :numeric,
        _
      ) do
    coef = for <<digit::16 <- digits>>, reduce: 0, do: (acc -> acc * 10_000 + digit)
    exp = (weight - ndigits + 1) * 4
    {coef, exp} = rescale(coef, exp, -dscale)
    Decimal.new(if(sign == @negative, do: -1, else: 1), coef, exp)
  end

  # Postgres keeps exactly dscale decimal places, so match it: 12.5 with dscale 2 is 12.50
  defp rescale(0, _exp, target), do: {0, target}
  defp rescale(coef, exp, target) when exp > target, do: {coef * pow10(exp - target), target}
  defp rescale(coef, exp, target) when exp < target, do: {div(coef, pow10(target - exp)), target}
  defp rescale(coef, exp, _target), do: {coef, exp}

  @impl true
  def encode(%Decimal{coef: :NaN}, :numeric, _), do: <<0::16, 0::16, @nan::16, 0::16>>

  def encode(%Decimal{coef: :inf, sign: 1}, :numeric, _),
    do: <<0::16, 0::16, @pos_inf::16, 0::16>>

  def encode(%Decimal{coef: :inf}, :numeric, _), do: <<0::16, 0::16, @neg_inf::16, 0::16>>

  def encode(%Decimal{sign: sign, coef: coef, exp: exp}, :numeric, _) do
    dscale = max(0, -exp)

    if dscale > 16_383, do: raise(ArgumentError, "numeric scale exceeds PostgreSQL's range")

    sign = if sign == -1, do: @negative, else: @positive

    case coef do
      0 ->
        <<0::16, 0::16, @positive::16, dscale::16>>

      _ ->
        # line the digits up on a base-10,000 boundary, then split them
        pad = Integer.mod(exp, 4)

        {digits, exp} =
          coef |> Kernel.*(pow10(pad)) |> base_10000([]) |> drop_trailing_zeros(exp - pad)

        weight = length(digits) - 1 + div(exp, 4)

        unless weight in -32_768..32_767 and length(digits) <= 65_535,
          do: raise(ArgumentError, "numeric value exceeds PostgreSQL's binary format")

        [
          <<length(digits)::16, weight::signed-16, sign::16, dscale::16>>
          | for(d <- digits, do: <<d::16>>)
        ]
    end
  end

  def encode(value, :numeric, state) when is_integer(value),
    do: encode(Decimal.new(value), :numeric, state)

  def encode(value, :numeric, state) when is_float(value),
    do: encode(Decimal.from_float(value), :numeric, state)

  def encode(value, :numeric, state) when is_binary(value),
    do: encode(Decimal.new(value), :numeric, state)

  @impl true
  def decode_text(value, _type, _), do: value

  defp base_10000(0, acc), do: acc
  defp base_10000(n, acc), do: base_10000(div(n, 10_000), [rem(n, 10_000) | acc])

  defp drop_trailing_zeros(digits, exp) do
    {zeros, rest} = digits |> Enum.reverse() |> Enum.split_while(&(&1 == 0))
    {Enum.reverse(rest), exp + 4 * length(zeros)}
  end

  defp pow10(0), do: 1
  defp pow10(n), do: Integer.pow(10, n)
end

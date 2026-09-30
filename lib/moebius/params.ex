defmodule Moebius.Params do
  @moduledoc false
  # Checks parameters against the types Postgres parsed for a statement, before they reach
  # epgsql. epgsql encodes inside the connection process, so a wrong type there crashes the
  # connection. Here it is a plain {:error, %Moebius.Error{}} naming the parameter.
  #
  # JSON is encoded here too, for the same reason: a value Jason can't encode would
  # otherwise raise inside the connection.

  alias Moebius.Error

  @integers [:int2, :int4, :int8]
  @floats [:float4, :float8]
  @texts [:text, :varchar, :bpchar, :name, :bytea]
  # 32 hex digits, with or without the usual hyphens; epgsql's codec crashes on anything else
  @uuid ~r/\A[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}\z/
  @temporal %{
    date: [Date],
    time: [Time],
    timestamp: [NaiveDateTime, DateTime],
    timestamptz: [DateTime, NaiveDateTime]
  }

  def check(types, params) when length(types) != length(params) do
    {:error,
     %Error{
       name: :bad_parameter,
       message: "the statement expects #{length(types)} parameters but got #{length(params)}"
     }}
  end

  def check(types, params), do: check(types, params, 1, [])

  # one pass, no intermediate lists: this runs for every parameter of every query
  defp check([], [], _n, acc), do: {:ok, :lists.reverse(acc)}

  defp check([type | types], [value | values], n, acc) do
    case cast(type, value) do
      {:ok, value} -> check(types, values, n + 1, [value | acc])
      :error -> {:error, mismatch(n, type, value)}
    end
  end

  defp cast(_type, nil), do: {:ok, nil}
  defp cast(type, value) when type in @integers and is_integer(value), do: {:ok, value}
  defp cast(type, value) when type in @floats and is_number(value), do: {:ok, value}

  defp cast(type, value)
       when type in @floats and value in [:nan, :plus_infinity, :minus_infinity],
       do: {:ok, value}

  defp cast(:numeric, %Decimal{} = value), do: {:ok, value}
  defp cast(:numeric, value) when is_number(value), do: {:ok, value}

  defp cast(:numeric, value) when is_binary(value) do
    case Decimal.parse(value) do
      {_decimal, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp cast(:bool, value) when is_boolean(value), do: {:ok, value}
  defp cast(type, value) when type in @texts and is_binary(value), do: {:ok, value}
  defp cast(:char, value) when is_binary(value) or is_integer(value), do: {:ok, value}

  defp cast(:uuid, value) when is_binary(value) do
    if Regex.match?(@uuid, value), do: {:ok, value}, else: :error
  end

  defp cast(type, value) when type in [:json, :jsonb] do
    case Jason.encode_to_iodata(value) do
      {:ok, json} -> {:ok, {:moebius_json, json}}
      {:error, _} -> :error
    end
  end

  defp cast(type, %module{} = value) when is_map_key(@temporal, type) do
    if module in @temporal[type], do: {:ok, value}, else: :error
  end

  defp cast(type, value) when is_map_key(@temporal, type) and is_tuple(value), do: {:ok, value}

  defp cast(type, value) when is_map_key(@temporal, type) and value in [:infinity, :"-infinity"],
    do: {:ok, value}

  defp cast({:array, type}, values) when is_list(values), do: cast_list(type, values, [])

  defp cast(type, _value) when type in @integers or type in @floats or type in @texts,
    do: :error

  defp cast(type, _value) when type in [:numeric, :bool, :char, :uuid, :json, :jsonb], do: :error
  defp cast(type, _value) when is_map_key(@temporal, type), do: :error
  defp cast({:array, _type}, _value), do: :error

  # anything else (inet, intervals, ranges, types epgsql doesn't know) goes through as is
  defp cast(_type, value), do: {:ok, value}

  # arrays can nest: [[1, 2], [3, 4]]
  defp cast_list(_type, [], acc), do: {:ok, Enum.reverse(acc)}

  defp cast_list(type, [value | rest], acc) when is_list(value) do
    with {:ok, inner} <- cast_list(type, value, []), do: cast_list(type, rest, [inner | acc])
  end

  defp cast_list(type, [value | rest], acc) do
    with {:ok, value} <- cast(type, value), do: cast_list(type, rest, [value | acc])
  end

  defp mismatch(n, type, value) do
    %Error{
      name: :bad_parameter,
      message: "parameter $#{n} must be #{type_name(type)}, got: #{inspect(value, limit: 5)}"
    }
  end

  defp type_name({:array, type}), do: "#{type_name(type)}[]"
  defp type_name({:unknown_oid, oid}), do: "type #{oid}"
  defp type_name(type), do: Atom.to_string(type)
end

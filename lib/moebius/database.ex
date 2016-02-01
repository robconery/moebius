defmodule Moebius.Database do

  defmacro __using__(_opts) do
    quote location: :keep do

      @name __MODULE__

      def start_link(opts) do
        opts = Keyword.new [opts]
        opts
          |> Keyword.put_new(:name, @name)
          |> Keyword.put_new(:extensions, [{Postgrex.Extensions.JSON, library: Poison}])
          |> Moebius.Database.start_link

      end

      def run(sql) when is_binary(sql), do: run(sql, [])
      def run(sql, params) when is_binary(sql) do
        %Moebius.QueryCommand{sql: sql, params: params} |> execute
      end

      def run(cmd), do: single(cmd)
      def run(cmd, %DBConnection{} = conn), do: single(cmd, conn)

      def all(sql) when is_binary(sql), do: all(sql, [])
      def all(sql, params) when is_binary(sql) do
        %Moebius.QueryCommand{sql: sql, params: params} |> execute
      end

      def all(%Moebius.QueryCommand{} = cmd), do: execute(cmd)
      def all(%Moebius.QueryCommand{} = cmd, %DBConnection{} = conn), do: execute(cmd, %DBConnection{} = conn)



      def execute(cmd) do
        %{cmd | conn: @name}
          |> Moebius.Database.execute
          |> Moebius.Transformer.to_list
      end

      def execute(cmd, %DBConnection{} = conn) do
        Moebius.Database.execute(cmd, conn)
          |> Moebius.Transformer.to_list
      end

      def single(cmd) do
        %{cmd | conn: @name}
          |> Moebius.Database.execute
          |> Moebius.Transformer.to_single
      end

      def single(cmd, %DBConnection{} = conn) do
        Moebius.Database.execute(cmd,conn)
          |> Moebius.Transformer.to_single
      end

      def transaction(fun) do
        try do
          {:ok, conn} = Postgrex.transaction(@name, fun)
          conn
        catch
          e, reason -> {:error, reason.message}
        end
      end

    end
  end

  def start_link(opts) do
    Postgrex.start_link(opts)
  end


  def execute(cmd) do
    case Postgrex.query(cmd.conn, cmd.sql, cmd.params) do
      {:ok, result} -> {:ok, result}
      {:error, err} -> {:error, err.postgres.message}
    end

  end

  @doc """
  Executes a command for a given transaction specified with `pid`. If the execution fails,
  it will be caught in `Query.transaction/1` and reported back using `{:error, err}`.
  """
  def execute(cmd, %DBConnection{} = conn) do

    case Postgrex.query(conn, cmd.sql, cmd.params) do
      {:ok, result} ->
        {:ok, result}
      {:error, err} ->
        Postgrex.query conn, "ROLLBACK", []
        #this will get caught by the transactor
        raise err.postgres.message
        #{:error, err.postgres.message}
    end
  end


end

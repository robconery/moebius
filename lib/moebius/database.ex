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

      def run(%Moebius.QueryCommand{} = cmd), do: single(cmd)
      def run(%Moebius.QueryCommand{} = cmd, %DBConnection{} = conn), do: single(cmd, conn)

      def run(%Moebius.DocumentCommand{} = cmd), do: single(cmd)

      def single(sql) when is_binary(sql), do: single(sql, [])
      def single(sql, params) when is_binary(sql) do
        %Moebius.QueryCommand{sql: sql, params: params} |> single
      end

      def all(sql) when is_binary(sql), do: all(sql, [])
      def all(sql, params) when is_binary(sql) do
        %Moebius.QueryCommand{sql: sql, params: params} |> execute
      end

      def all(%Moebius.QueryCommand{} = cmd), do: execute(cmd)
      def all(%Moebius.QueryCommand{} = cmd, %DBConnection{} = conn), do: execute(cmd, %DBConnection{} = conn)

      def execute(%Moebius.DocumentCommand{sql: nil} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.DocumentQuery.select
          |> Moebius.Database.execute
          |> Moebius.Transformer.from_json
      end
      
      def execute(%Moebius.DocumentCommand{} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.Database.execute
          |> Moebius.Transformer.from_json
      end

      def execute(%Moebius.QueryCommand{} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.Database.execute
          |> Moebius.Transformer.to_list
      end

      def execute(%Moebius.QueryCommand{} = cmd, %DBConnection{} = conn) do
        Moebius.Database.execute(cmd, conn)
          |> Moebius.Transformer.to_list
      end

      def single(%Moebius.QueryCommand{} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.Database.execute
          |> Moebius.Transformer.to_single
      end

      def single(%Moebius.DocumentCommand{} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.DocumentQuery.select
          |> Moebius.Database.execute
          |> Moebius.Transformer.from_json(:single)
      end

      def single(%Moebius.QueryCommand{} = cmd, %DBConnection{} = conn) do
        Moebius.Database.execute(cmd,conn)
          |> Moebius.Transformer.to_single
      end

      def find(%Moebius.QueryCommand{} = cmd, id) do
        sql = "select * from #{cmd.table_name} where id=#{id}"
        %{cmd | sql: sql} |> single
      end

      def find(%Moebius.DocumentCommand{} = cmd, id) do
        sql = "select id, #{cmd.json_field}::text from #{cmd.table_name} where id=#{id}"
        %{cmd | sql: sql} |> single
      end

      def transaction(fun) do
        try do
          {:ok, conn} = Postgrex.transaction(@name, fun)
          conn
        catch
          e, reason -> {:error, reason.message}
        end
      end

      def save(%Moebius.DocumentCommand{} = cmd, doc) when is_list(doc), do: save(cmd, Enum.into(doc, %{}))
      def save(%Moebius.DocumentCommand{} = cmd, doc) do
        res =
        %{cmd | conn: @name}
          |> Moebius.DocumentQuery.decide_command(doc)
          |> Moebius.Database.execute
          |> Moebius.Transformer.from_json(:single)

        case res do
          {:error, err} -> create_document_table(cmd, doc) |> save(Map.delete(doc, :id))
          res -> update_search(res, cmd) && res
        end
      end

      defp create_document_table(%Moebius.DocumentCommand{} = cmd, _) do
        sql = """
        create table #{cmd.table_name}(
          id serial primary key not null,
          body jsonb not null,
          search tsvector,
          created_at timestamptz not null default now(),
          updated_at timestamptz
        );
        """

        %Moebius.QueryCommand{conn: @name, sql: sql} |> execute
        %Moebius.QueryCommand{conn: @name, sql: "create index idx_#{cmd.table_name}_search on #{cmd.table_name} using GIN(search);"} |> execute
        %Moebius.QueryCommand{conn: @name, sql: "create index idx_#{cmd.table_name} on #{cmd.table_name} using GIN(body jsonb_path_ops);"} |> execute

        cmd
      end


      defp update_search({:error, err}, cmd), do: {:error, err}
      defp update_search([], _),  do: []
      defp update_search(query_result, cmd) do

        if length(cmd.search_fields) > 0 do
          terms = Enum.map_join(cmd.search_fields, ", ' ', ", &"body -> '#{Atom.to_string(&1)}'")
          sql = "update #{cmd.table_name} set search = to_tsvector(concat(#{terms})) where id=#{query_result.id}"

          %Moebius.QueryCommand{sql: sql}
            |> execute

        end

        query_result
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

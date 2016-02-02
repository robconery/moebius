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
        %Moebius.QueryCommand{sql: sql, params: params} |> run
      end

      def run(%Moebius.QueryCommand{type: :insert} = cmd), do: execute(cmd) |> Moebius.Transformer.to_single
      def run(%Moebius.QueryCommand{type: :update} = cmd), do: execute(cmd) |> Moebius.Transformer.to_single
      def run(%Moebius.QueryCommand{type: :delete} = cmd), do: execute(cmd) |> Moebius.Transformer.to_single
      def run(%Moebius.QueryCommand{type: :count} = cmd), do: execute(cmd) |> Moebius.Transformer.to_single

      def run(%Moebius.QueryCommand{type: :insert} = cmd, %DBConnection{} = conn), do: execute(cmd, conn) |> Moebius.Transformer.to_single
      def run(%Moebius.QueryCommand{type: :update} = cmd, %DBConnection{} = conn), do: execute(cmd, conn) |> Moebius.Transformer.to_single
      def run(%Moebius.QueryCommand{type: :delete} = cmd, %DBConnection{} = conn), do: execute(cmd, conn) |> Moebius.Transformer.to_single

      def run(%Moebius.QueryCommand{} = cmd), do: execute(cmd) |> Moebius.Transformer.to_list
      def run(%Moebius.QueryCommand{} = cmd, %DBConnection{} = conn), do: execute(cmd, conn) |> Moebius.Transformer.to_list

      def run(%Moebius.DocumentCommand{sql: nil} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.DocumentQuery.select
          |> Moebius.Database.execute
          |> Moebius.Transformer.from_json
      end

      def run(%Moebius.DocumentCommand{} = cmd) do
         execute(cmd)
          |> Moebius.Transformer.from_json
      end

      def first(%Moebius.DocumentCommand{} = cmd) do
        Moebius.DocumentQuery.select(cmd)
          |> execute
          |> Moebius.Transformer.from_json(:single)
      end

      def first(%Moebius.QueryCommand{sql: nil} = cmd) do
        Moebius.Query.select(cmd)
          |> execute
          |> Moebius.Transformer.to_single
      end

      def first(%Moebius.QueryCommand{} = cmd) do
        cmd
          |> execute
          |> Moebius.Transformer.to_single
      end

      def find(%Moebius.QueryCommand{} = cmd, id) do
        sql = "select * from #{cmd.table_name} where id=#{id}"
        %{cmd | sql: sql}
          |> execute
          |> Moebius.Transformer.to_single
      end

      def find(%Moebius.DocumentCommand{} = cmd, id) do
        sql = "select id, #{cmd.json_field}::text from #{cmd.table_name} where id=#{id}"
        %{cmd | sql: sql}
          |> execute
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


      defp execute(%Moebius.DocumentCommand{sql: nil} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.DocumentQuery.select
          |> Moebius.Database.execute
      end

      defp execute(%Moebius.DocumentCommand{} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.Database.execute
      end

      defp execute(%Moebius.QueryCommand{sql: nil} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.Query.select
          |> Moebius.Database.execute

      end

      defp execute(%Moebius.QueryCommand{} = cmd) do
        %{cmd | conn: @name}
          |> Moebius.Database.execute
      end

      defp execute(%Moebius.QueryCommand{} = cmd, %DBConnection{} = conn), do: Moebius.Database.execute(cmd, conn)


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


  def parse_connection_args, do: raise "Please specify a connection in your config"
  def parse_connection_args(args) when is_list(args), do: args

  def parse_connection_args(""), do: []
  def parse_connection_args(url) when is_binary(url) do
    info = url |> URI.decode() |> URI.parse()

    if is_nil(info.host) do
      raise "Invalid URL: host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise "Invalid URL: path should be a database name"
    end

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    #strip off any nils
    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end

end

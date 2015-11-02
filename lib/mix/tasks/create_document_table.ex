defmodule Mix.Tasks.Moebius.CreateDocumentTable do

  use Mix.Task
  import Moebius.Query

  def run(args) do
    Application.ensure_all_started(:moebius)

    table_name = List.first(args)

    """
        create table #{table_name}(
          id serial primary key not null,
          body jsonb not null,
          search tsvector,
          created_at timestamptz not null default now(),
          updated_at timestamptz
        );
    """
      |> Moebius.Query.run

    "create index idx_#{table_name}_search on #{table_name} using GIN(search);" |> Moebius.Query.run
    "create index idx_#{table_name} on #{table_name} using GIN(body jsonb_path_ops);" |> Moebius.Query.run

  end

end

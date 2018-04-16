defmodule QueryTest do
  use ExUnit.Case 
  import Moebius
  setup_all do
    "drop table if exists customers" |> run
    "create table customers(
      id serial primary key,
      email text not null unique,
      name text 
    )" |> run
    "insert into customers(email) values ('basics@test.com')" |> run
    :ok
  end
  describe "API basics" do
    test "a simple select from a table" do
       res = table(:customers) |> all |> IO.inspect 
       case res do
         {:ok, customers} -> assert length(customers) > 0
         {:error, err} -> flunk err
       end
    end
  end
end
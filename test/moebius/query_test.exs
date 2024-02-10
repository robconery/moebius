defmodule Moebius.QueryTest do
  use ExUnit.Case
  import Moebius.Query

  test "single column default (ASC) sort" do
    cmd = db(:users) |> sort(:id)

    assert cmd.order == " order by id asc"
  end

  test "single column ASC sort" do
    cmd = db(:users) |> sort(:id, :asc)

    assert cmd.order == " order by id asc"
  end

  test "single column DESC sort" do
    cmd = db(:users) |> sort(:id, :desc)

    assert cmd.order == " order by id desc"
  end

  test "multiple column sort" do
    cmd = db(:users) |> sort(id: :desc, email: :asc)

    assert cmd.order == " order by id desc, email asc"
  end
end

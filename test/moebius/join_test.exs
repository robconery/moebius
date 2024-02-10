defmodule Moebius.JoinTest do
  use ExUnit.Case
  import Moebius.Query

  test "a basic join" do
    cmd =
      db(:customer)
      |> join(:order)
      |> select

    assert cmd.sql ==
             "select * from customer inner join order on customer.id = order.customer_id;"
  end

  test "using singular table names" do
    cmd =
      db("customer")
      |> join("order")
      |> select

    assert cmd.sql ==
             "select * from customer inner join order on customer.id = order.customer_id;"
  end

  test "custom primary key" do
    cmd =
      db("customer")
      |> join("order", primary_key: :customer_id)
      |> select

    assert cmd.sql ==
             "select * from customer inner join order on customer.customer_id = order.customer_id;"
  end

  test "custom foreign key" do
    cmd =
      db("customer")
      |> join("order", foreign_key: :customer_number)
      |> select

    assert cmd.sql ==
             "select * from customer inner join order on customer.id = order.customer_number;"
  end

  test "multiple joins" do
    cmd =
      db(:customer)
      |> join(:order, on: :customer)
      |> join(:item, on: :order)
      |> select

    assert cmd.sql ==
             "select * from customer" <>
               " inner join order on customer.id = order.customer_id" <>
               " inner join item on order.id = item.order_id;"
  end

  test "outer joins" do
    cmd =
      db(:customer)
      |> join(:order, join: :left)
      |> select

    assert cmd.sql ==
             "select * from customer" <>
               " left join order on customer.id = order.customer_id;"

    cmd =
      db(:customer)
      |> join(:order, join: :right)
      |> select

    assert cmd.sql ==
             "select * from customer" <>
               " right join order on customer.id = order.customer_id;"

    cmd =
      db(:customer)
      |> join(:order, join: :full)
      |> select

    assert cmd.sql ==
             "select * from customer" <>
               " full join order on customer.id = order.customer_id;"

    cmd =
      db(:customer)
      |> join(:order, join: :cross)
      |> select

    assert cmd.sql ==
             "select * from customer" <>
               " cross join order on customer.id = order.customer_id;"
  end

  test "join with USING" do
    cmd =
      db(:t1)
      |> join(:t2, using: [:num, :name])
      |> select

    assert cmd.sql ==
             "select * from t1" <>
               " inner join t2 using (num, name);"
  end
end

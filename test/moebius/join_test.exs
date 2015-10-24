defmodule Moebius.JoinTest do

  use ExUnit.Case
  import Moebius.Query

  test "a basic join" do
    cmd = db(:customers)
        |> join(:orders)
        |> select_command

    assert cmd.sql ==
      "select * from customers inner join orders on customers.id = orders.customer_id;"
  end

  test "using singular table names" do
    cmd = db("customer")
        |> join("order")
        |> select_command

    assert cmd.sql ==
      "select * from customer inner join order on customer.id = order.customer_id;"
  end

  test "custom primary key" do
    cmd = db("customer")
        |> join("order", primary_key: :customer_id)
        |> select_command

    assert cmd.sql ==
      "select * from customer inner join order on customer.customer_id = order.customer_id;"
  end

  test "custom foreign key" do
    cmd = db("customer")
        |> join("order", foreign_key: :customer_number)
        |> select_command

    assert cmd.sql ==
      "select * from customer inner join order on customer.id = order.customer_number;"
  end

  test "multiple joins" do
    cmd = db(:customers)
        |> join(:orders, on: :customers)
        |> join(:items, on: :orders)
        |> select_command

    assert cmd.sql ==
      "select * from customers" <>
      " inner join orders on customers.id = orders.customer_id" <>
      " inner join items on orders.id = items.order_id;"
  end

  test "outer joins" do
    cmd = db(:customers)
        |> join(:orders, join: :left)
        |> select_command

    assert cmd.sql ==
      "select * from customers" <>
      " left join orders on customers.id = orders.customer_id;"

    cmd = db(:customers)
        |> join(:orders, join: :right)
        |> select_command

    assert cmd.sql ==
      "select * from customers" <>
      " right join orders on customers.id = orders.customer_id;"

    cmd = db(:customers)
        |> join(:orders, join: :full)
        |> select_command

    assert cmd.sql ==
      "select * from customers" <>
      " full join orders on customers.id = orders.customer_id;"

    cmd = db(:customers)
        |> join(:orders, join: :cross)
        |> select_command

    assert cmd.sql ==
      "select * from customers" <>
      " cross join orders on customers.id = orders.customer_id;"
  end

  test "join with USING" do
    cmd = db(:t1)
        |> join(:t2, using: [:num, :name])
        |> select_command

    assert cmd.sql ==
      "select * from t1" <>
      " inner join t2 using (num, name);"
  end

end

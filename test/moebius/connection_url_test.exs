defmodule Moebius.ConnectionUrlTest do
  use ExUnit.Case, async: true

  test "Unix sockets keep the server port in the path and use transport port zero" do
    opts = Moebius.Connection.epgsql_options(socket_dir: "/tmp", port: 6543)
    assert opts.host == {:local, "/tmp/.s.PGSQL.6543"}
    assert opts.port == 0
  end

  describe "parse_connection/1" do
    test "splits a url into connection options" do
      assert Moebius.parse_connection("postgres://user:secret@db.example.com:6543/app") == [
               username: "user",
               password: "secret",
               database: "app",
               hostname: "db.example.com",
               port: 6543
             ]
    end

    test "keeps a colon in the password" do
      opts = Moebius.parse_connection("postgres://user:pa:ss:word@localhost/app")

      assert opts[:username] == "user"
      assert opts[:password] == "pa:ss:word"
    end

    test "decodes a percent-encoded password" do
      assert Moebius.parse_connection("postgres://user:p%40ss@localhost/app")[:password] == "p@ss"
    end

    test "leaves out what the url doesn't say" do
      assert Moebius.parse_connection("postgres://localhost/app") == [
               database: "app",
               hostname: "localhost"
             ]
    end

    test "a url without a database or host raises" do
      assert_raise ArgumentError, ~r/database name/, fn ->
        Moebius.parse_connection("postgres://localhost")
      end

      assert_raise ArgumentError, ~r/host/, fn -> Moebius.parse_connection("postgres:///app") end
    end
  end
end

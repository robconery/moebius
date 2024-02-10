import Config

config :moebius,
  connection: [
    url: "postgres://postgres:postgres@localhost:5432/moebius_test"
  ],
  scripts: "test/db"

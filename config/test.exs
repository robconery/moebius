import Config

config :moebius,
  connection: [
    url: "postgresql://postgres:postgres@localhost/moebius_test"
  ],
  scripts: "test/db"

import Config

config :moebius,
  connection: [
    url: "postgres://localhost/moebius_test"
  ],
  scripts: "test/db"

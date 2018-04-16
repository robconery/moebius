use Mix.Config

config :moebius_pool,
host: "localhost",
username: "meebuss",
password: "password",
database: "meebuss",
reconnect: :no_reconnect,
max_queue: :infinity,
pool_size: 25,
pool_max_overflow: 0,
timeout: 5000
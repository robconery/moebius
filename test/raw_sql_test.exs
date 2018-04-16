defmodule Moebius.BasicSelect do
  use ExUnit.Case

  describe "Basic SQL ops inline" do
    test "It returns 1" do
      res = "select 1 as duck" |> Moebius.run
      case res do
        {:ok, _, _} -> assert true
        {:error, err} -> flunk err
      end
    end
    test "It returns an error when error" do
      res = "select 'nothing'::jsonb" |> Moebius.run
      case res do
        {:ok, _, _} -> flunk "Nope"
        {:error, err} -> assert err
      end
    end
  end

end
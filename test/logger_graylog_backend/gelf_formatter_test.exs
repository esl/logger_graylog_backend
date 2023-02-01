defmodule LoggerGraylogBackend.GelfFormatterTest do
  use ExUnit.Case, async: true

  alias LoggerGraylogBackend.GelfFormatter, as: Formatter

  describe "format/5" do
    test "includes all mandatory GELF fields by default" do
      level = :warn
      message = "hello darkness my old friend"
      timestamp = generate_timestamp()
      host = "some-host"

      {:ok, gelf} = Formatter.format(host, level, message, timestamp, []) |> decode()

      assert "1.1" == gelf["version"]
      assert 4 == gelf["level"]
      assert message == gelf["short_message"]
      assert host == gelf["host"]
      assert_same_timestamp(timestamp, gelf["timestamp"])
    end

    test "includes all metadata as additional fields" do
      metadata = [meta1: "some-data", meta2: "some-other-data"]

      {:ok, gelf} =
        Formatter.format("host", :info, "hello", generate_timestamp(), metadata) |> decode()

      assert "some-data" == gelf["_meta1"]
      assert "some-other-data" == gelf["_meta2"]
    end
  end

  for level <- ~w(warn warning)a do
    describe "format/6 level: #{level}" do
      test "doesn't include timestamp if the option is passed" do
        {:ok, gelf} =
          Formatter.format(
            "host",
            unquote(level),
            "hello",
            generate_timestamp(),
            [],
            include_timestamp: false
          )
          |> decode()

        refute Map.has_key?(gelf, "timestamp")
      end
    end
  end

  ## Helpers

  @spec decode(iodata) :: {:ok, map()}
  defp decode(data) when is_binary(data), do: Jason.decode(data)
  defp decode(data), do: data |> IO.iodata_to_binary() |> decode()

  @spec generate_timestamp() :: Formatter.timestamp()
  defp generate_timestamp() do
    {{year, month, day}, {hour, min, sec}} = :calendar.universal_time()
    {{year, month, day}, {hour, min, sec, 0}}
  end

  @spec assert_same_timestamp(Formatter.timestamp(), seconds :: float) :: :ok | no_return
  defp assert_same_timestamp({{year, month, day}, {hour, min, sec, milli}}, millis) do
    expected_seconds =
      {{year, month, day}, {hour, min, sec}}
      |> NaiveDateTime.from_erl!()
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_unix(:second)

    assert expected_seconds + milli / 1000 == millis
    :ok
  end
end

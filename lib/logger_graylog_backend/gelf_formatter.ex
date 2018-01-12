defmodule LoggerGraylogBackend.GelfFormatter do
  @moduledoc false

  ## A couple of notes on formatting:
  ## * it formats log level as syslog log severity number
  ## * it formats the timestamp as Unix seconds, because Graylog expects that (timezone information
  ##   is lost)

  @gelf_version "1.1"

  @type host :: String.t()
  @type timestamp :: tuple()

  ## API

  @spec format(
          host,
          Logger.level(),
          Logger.message(),
          :calendar.datetime(),
          Logger.metadata()
        ) :: iodata
  def format(host, level, message, timestamp, metadata),
    do: format(host, level, message, timestamp, metadata, [])

  @spec format(
          host,
          Logger.level(),
          Logger.message(),
          :calendar.datetime(),
          Logger.metadata(),
          Keyword.t()
        ) :: iodata
  def format(host, level, message, timestamp, metadata, opts) do
    mandatory_fields = %{
      "version" => @gelf_version,
      "host" => host,
      "short_message" => IO.chardata_to_string(message),
      "level" => format_level(level)
    }

    timestamp_field = maybe_timestamp_field(timestamp, opts)

    additional_fields =
      metadata |> Enum.map(fn {k, v} -> {["_", to_string(k)], v} end) |> Enum.into(%{})

    mandatory_fields |> Map.merge(timestamp_field) |> Map.merge(additional_fields)
    |> Jason.encode_to_iodata!()
  end

  ## Helpers

  @spec maybe_timestamp_field(timestamp, Keyword.t()) :: map
  defp maybe_timestamp_field(timestamp, opts) do
    case Keyword.get(opts, :include_timestamp, true) do
      true ->
        %{"timestamp" => format_timestamp(timestamp)}

      false ->
        %{}
    end
  end

  @spec format_level(Logger.level()) :: 7 | 6 | 4 | 3
  defp format_level(:debug), do: 7
  defp format_level(:info), do: 6
  defp format_level(:warn), do: 4
  defp format_level(:error), do: 3

  @spec format_timestamp(timestamp) :: float
  defp format_timestamp({{year, month, day}, {hour, min, sec, milli}}) do
    seconds =
      {{year, month, day}, {hour, min, sec}}
      |> NaiveDateTime.from_erl!()
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.to_unix(:second)

    seconds + milli / 1000
  end

  ## Encoder implementation for pids

  defimpl Jason.Encoder, for: PID do
    def encode(pid, opts) do
      pid |> inspect() |> Jason.Encode.string(opts)
    end
  end
end

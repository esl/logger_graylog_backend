defmodule LoggerGraylogBackend.Tcp do
  @moduledoc false

  require Logger

  alias LoggerGraylogBackend.GelfFormatter, as: Formatter

  @behaviour :gen_event

  defstruct [
    :host,
    :port,
    :gelf_host,
    socket: :disconnected,
    level: :info,
    metadata_filter: [],
    include_timestamp: true
  ]

  @levels [:debug, :info, :warn, :error]

  @type host :: :inet.hostname() | :inet.ip_address()
  @type metadata_filter :: :all | [atom] | {module, function :: atom}
  @type state :: %__MODULE__{
          host: host,
          port: :inet.port_number(),
          socket: :disconnected | {:connected, :gen_tcp.socket()},
          level: Logger.level(),
          metadata_filter: metadata_filter,
          gelf_host: Formatter.host(),
          include_timestamp: boolean
        }

  ## :gen_event callbacks

  @impl :gen_event
  def init(__MODULE__) do
    init(app_env_config())
  end

  def init({__MODULE__, opts}) do
    config = Keyword.merge(app_env_config(), opts)
    init(config)
  end

  def init(config) do
    case init_state(config) do
      {:ok, state} ->
        {:ok, try_connect(state)}

      {:error, err_msg} ->
        Logger.error(fn -> "Couldn't start #{inspect(__MODULE__)}: #{err_msg}" end)
        {:error, err_msg}
    end
  end

  @impl :gen_event
  def handle_call({:configure, opts}, state) do
    case configure(state, opts) do
      {:ok, state} ->
        {:ok, :ok, state}

      {:error, _} = err ->
        {:ok, err, state}
    end
  end

  @impl :gen_event
  def handle_event(
        {level, gl, {Logger, message, timestamp, metadata}},
        %{socket: {:connected, _}} = state
      )
      when node(gl) == node() do
    with true <- should_log?(level, state),
         :ok <- log(level, message, timestamp, metadata, state) do
      {:ok, state}
    else
      :error ->
        {:ok, try_connect(%{state | socket: :disconnected})}

      _ ->
        {:ok, state}
    end
  end

  def handle_event(_, %{socket: :disconnected} = state) do
    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  @impl :gen_event
  def handle_info(
        {:tcp_closed, socket},
        %{socket: {:connected, socket}, host: host, port: port} = state
      ) do
    Logger.error(fn -> "Connection with #{format_endpoint(host, port)} closed" end)
    {:ok, try_connect(%{state | socket: :disconnected})}
  end

  def handle_info({:timeout, _, :reconnect}, %{socket: :disconnected} = state) do
    {:ok, try_connect(state)}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl :gen_event
  def terminate(_, _) do
    :ok
  end

  @impl :gen_event
  def code_change(_, _, state) do
    {:ok, state}
  end

  ## Helpers

  @spec should_log?(Logger.level(), state) :: boolean()
  defp should_log?(level, %{level: level_threshold}) do
    Logger.compare_levels(level, level_threshold) != :lt
  end

  @spec log(Logger.level(), Logger.message(), Formatter.timestamp(), Logger.metadata(), state) ::
          :ok | :error
  defp log(
         level,
         message,
         timestamp,
         metadata,
         %{
           socket: {:connected, socket},
           host: host,
           port: port,
           include_timestamp: include_timestamp
         } = state
       ) do
    metadata_to_send =
      extract_metadata(level, message, timestamp, metadata, state.metadata_filter)

    log =
      Formatter.format(
        state.gelf_host,
        level,
        message,
        timestamp,
        metadata_to_send,
        include_timestamp: include_timestamp
      )

    case :gen_tcp.send(socket, [log, 0]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(fn ->
          "Couldn't send log message to Graylog at #{format_endpoint(host, port)}: #{
            inspect(reason)
          }"
        end)

        :error
    end
  end

  @spec extract_metadata(
          Logger.level(),
          Logger.message(),
          Formatter.timestamp(),
          Logger.metadata(),
          metadata_filter
        ) :: Logger.metadata()
  defp extract_metadata(_, _, _, metadata, :all), do: metadata

  defp extract_metadata(level, message, ts, metadata, {module, function}),
    do: apply(module, function, [level, message, ts, metadata])

  defp extract_metadata(_, _, _, metadata, keys), do: Keyword.take(metadata, keys)

  @spec get_gelf_host(false | Formatter.host()) :: Formatter.host()
  defp get_gelf_host(false) do
    {:ok, host} = :inet.gethostname()
    to_string(host)
  end

  defp get_gelf_host(host) when is_binary(host) do
    host
  end

  @spec try_connect(state) :: state
  defp try_connect(%{socket: :disconnected, host: host, port: port} = state) do
    case :gen_tcp.connect(host, port, [:binary, active: false], 5000) do
      {:ok, socket} ->
        Logger.info(fn -> "Connected to #{format_endpoint(host, port)}" end)
        %{state | socket: {:connected, socket}}

      {:error, reason} ->
        reconnect_in = 5
        set_reconnection_timer(reconnect_in)

        Logger.error(fn ->
          "Couldn't connect to #{format_endpoint(host, port)}: #{inspect(reason)}. Retrying in #{
            reconnect_in
          }s"
        end)

        state
    end
  end

  @spec format_endpoint(host, :inet.port_number()) :: String.t()
  defp format_endpoint({_, _, _, _} = ipv4, port) do
    format_endpoint(:inet.ntoa(ipv4), port)
  end

  defp format_endpoint({_, _, _, _, _, _, _, _} = ipv6, port) do
    format_endpoint(:inet.ntoa(ipv6), port)
  end

  defp format_endpoint(host, port) do
    "#{host}:#{port}"
  end

  @spec set_reconnection_timer(seconds :: non_neg_integer()) :: :ok
  defp set_reconnection_timer(seconds) do
    :erlang.start_timer(seconds * 1000, self(), :reconnect)
  end

  @spec maybe_host_to_charlist(map) :: map
  defp maybe_host_to_charlist(%{host: host} = map) when is_binary(host),
    do: %{map | host: to_charlist(host)}

  defp maybe_host_to_charlist(map), do: map

  @spec app_env_config() :: Keyword.t()
  defp app_env_config() do
    Application.get_env(:logger_graylog_backend, __MODULE__, [])
  end

  @spec initial_opts_schema() :: Optium.schema()
  defp initial_opts_schema,
    do: %{
      port: [required: true, validator: &port_number?/1],
      host: [required: true],
      level: [default: :info, validator: &log_level?/1],
      metadata: [default: :all, validator: &metadata_opt?/1],
      override_host: [default: false, validator: &override_host_opt?/1],
      include_timestamp: [default: true, validator: &is_boolean/1]
    }

  @spec init_state(config :: Keyword.t()) :: {:ok, state} | {:error, String.t()}
  defp init_state(config) do
    case Optium.parse(config, initial_opts_schema()) do
      {:ok, opts} ->
        state = %__MODULE__{
          host: opts[:host],
          port: opts[:port],
          socket: :disconnected,
          level: opts[:level],
          metadata_filter: opts[:metadata],
          gelf_host: get_gelf_host(opts[:override_host]),
          include_timestamp: opts[:include_timestamp]
        }

        {:ok, maybe_host_to_charlist(state)}

      {:error, err} ->
        {:error, Exception.message(err)}
    end
  end

  @spec reconfigure_opts_schema() :: Optium.schema()
  defp reconfigure_opts_schema(),
    do: %{
      level: [validator: &log_level?/1],
      metadata: [validator: &metadata_opt?/1],
      override_host: [validator: &override_host_opt?/1],
      include_timestamp: [validator: &is_boolean/1]
    }

  @spec configure(state, config :: Keyword.t()) :: {:ok, state} | {:error, String.t()}
  defp configure(state, config) do
    case Optium.parse(config, reconfigure_opts_schema()) do
      {:ok, opts} ->
        new_gelf_host =
          case Keyword.has_key?(opts, :override_host) do
            true ->
              get_gelf_host(opts[:override_host])

            false ->
              state.gelf_host
          end

        new_include_timestamp =
          case is_boolean(opts[:include_timestamp]) do
            true ->
              opts[:include_timestamp]

            false ->
              state.include_timestamp
          end

        new_state = %__MODULE__{
          state
          | level: opts[:level] || state.level,
            metadata_filter: opts[:metadata] || state.metadata_filter,
            gelf_host: new_gelf_host,
            include_timestamp: new_include_timestamp
        }

        {:ok, new_state}

      {:error, err} ->
        {:error, Exception.message(err)}
    end
  end

  @spec port_number?(term) :: boolean()
  defp port_number?(term) when term > 0 and term <= 65_535, do: true
  defp port_number?(_), do: false

  @spec log_level?(term) :: boolean()
  defp log_level?(term) when term in @levels, do: true
  defp log_level?(_), do: false

  @spec metadata_opt?(term) :: boolean()
  defp metadata_opt?(:all), do: true
  defp metadata_opt?(term) when is_list(term), do: Enum.all?(term, &is_atom/1)
  defp metadata_opt?({module, function}) when is_atom(module) and is_atom(function), do: true
  defp metadata_opt?(_), do: false

  @spec override_host_opt?(term) :: boolean()
  defp override_host_opt?(false), do: true
  defp override_host_opt?(term) when is_binary(term), do: String.valid?(term)
  defp override_host_opt?(_), do: false
end

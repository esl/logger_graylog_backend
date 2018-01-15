## LoggerGraylogBackend

This application provides a [Logger](https://hexdocs.pm/logger) backend for sendings log messages
to Graylog. Currently only TCP transport is supported, and logs are always formatted in
[GELF](http://docs.graylog.org/en/stable/pages/gelf.html) format.

### Installation

This library is not available on Hex (yet). You need to pull it directly from GitHub:

```elixir
def deps do
  [{:logger_graylog_backend, github: "esl/logger_graylog_backend"}, ...]
end
```

### Usage

First you need to tell `Logger` to install this backend:

```elixir
config :logger, backends: [LoggerGraylogBackend.Tcp]
```

and then configure the backend itself:

```elixir
config :logger, LoggerGraylogBackend.Tcp,
  host: "your-graylog-hostname",
  port: 12201,
  # other options...
```

And that's it! Note that if the TCP backend won't be able to connect to the Graylog instance, it
will try reconnecting indefinitely (with backoff).

### Backend configuration

There are couple of configuration values you can provide to the backend:

* `:host` (**required**) - host name or IP address (basically everything accepted by `gen_tcp:connect/3`)
   of the Graylog instance
* `:port` (**required**) - port which the Graylog instance accepts TCP connections on
* `:level` (**optional**, default: `info`) - the log level (`:debug`, `:info`, `:warn` or `:error`)

### Formatter

Logs sent by the backend are always in GELF 1.1 format. The following fields are included in the
payload by default:

* `"version"` - always has value `"1.1"`
* `"host"` - hostname retrieved using `inet:gethostname/0` (might be overriden)
* `"timestamp"` - the log timestamp in seconds and milliseconds as fractional part (can be excluded)
* `"short_message"` - the log message
* `"level"` - the log severity formatted as a number as in [syslog](https://en.wikipedia.org/wiki/Syslog#Severity_level)

In addition, all metadata provided by Logger will be included as additional fields (thus prefixed
with `_`). What metadata is included in the message is also configurable.

#### Conifugration

You can configure the formatter using the following options:

* `:include_timestamp` (default: `true`) - tells the formatted to include the `"timestamp"` field.
  Note that Graylog generates the timestamp itself if the incoming log message doesn't have it
* `:override_host` (default: `false`)- if set, the `"host"` field in the GELF log will have the
  configured value. Might be set to `false` to make the formatter use system hostname
* `:metadata` (default: `:all`) - filters what metadata will be included in the message, possible
  values are:
  * `:all` - all metadata
  * list of atoms - only metadata with keys present in the provided list
  * `{module, function}` - a module/function pair which will be called when generatin the GELF
    message. The function should take four arguments (log level, log message, timestamp and
    all metadata) and return the metadata which will be included in the message

### Example configuration

```elixir
config :logger, backends: [LoggerGraylogBackend.Tcp]

config :logger, LoggerGraylogBackend.Tcp,
  host: "example.com",
  port: 12201,
  level: :warn,
  include_timestamp: false,
  override_host: "my-app",
  metadata: [:application, :file, :line]
```

### License

Copyright 2018 Erlang Solutions

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

